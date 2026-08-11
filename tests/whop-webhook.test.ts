import { createHmac } from "crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { verifyWhopWebhook, WHOP_API_VERSION } from "@/lib/whop/verify";
import {
  outcomeForAction,
  planFromWhopIds,
  reconcileWithPayloadValidity,
  statusForOutcome,
} from "@/lib/whop/events";
import { extractBusinessId, extractEmail } from "@/lib/whop/link";

const SECRET = "whop_test_secret_value";

function sign(body: string, timestamp: number, secret = SECRET) {
  const sig = createHmac("sha256", secret).update(`${timestamp}.${body}`).digest("hex");
  return `t=${timestamp},v1=${sig}`;
}

function membershipBody(overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    api_version: WHOP_API_VERSION,
    action: "membership.went_valid",
    data: { id: "mem_123", user_id: "user_abc", plan_id: "plan_growth", valid: true, ...overrides },
  });
}

describe("verifyWhopWebhook", () => {
  const now = 1_800_000_000;

  it("accepts a correctly signed payload", () => {
    const body = membershipBody();
    const result = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: sign(body, now),
      secret: SECRET,
      nowSeconds: now,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.payload.action).toBe("membership.went_valid");
      expect(result.signedAt.getTime()).toBe(now * 1000);
    }
  });

  it("rejects a missing signature header — an unsigned webhook is never trusted", () => {
    const body = membershipBody();
    const r = verifyWhopWebhook({ rawBody: body, signatureHeader: null, secret: SECRET, nowSeconds: now });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("missing_signature");
  });

  it("rejects when the signing secret is not configured", () => {
    const body = membershipBody();
    const r = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: sign(body, now),
      secret: undefined,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("missing_secret");
  });

  it("rejects a signature computed with the wrong secret", () => {
    const body = membershipBody();
    const r = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: sign(body, now, "attacker_secret"),
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("signature_mismatch");
  });

  it("rejects a tampered body even when the signature is well-formed", () => {
    const original = membershipBody();
    const header = sign(original, now);
    const tampered = membershipBody({ plan_id: "plan_pro" }); // attacker upgrades the plan
    const r = verifyWhopWebhook({
      rawBody: tampered,
      signatureHeader: header,
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("signature_mismatch");
  });

  it("rejects a replayed event outside the 5-minute window", () => {
    const body = membershipBody();
    const old = now - 301;
    const r = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: sign(body, old),
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("invalid_timestamp");
  });

  it("accepts an event just inside the clock-skew window", () => {
    const body = membershipBody();
    const r = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: sign(body, now - 299),
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(true);
  });

  it("rejects an unsupported signature scheme version", () => {
    const body = membershipBody();
    const r = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: `t=${now},v2=deadbeef`,
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("unsupported_version");
  });

  it("rejects a payload whose api_version is not v5", () => {
    const body = JSON.stringify({ api_version: "v4", action: "membership.went_valid", data: {} });
    const r = verifyWhopWebhook({
      rawBody: body,
      signatureHeader: sign(body, now),
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.failure).toBe("invalid_payload");
  });

  it("uses the exact raw bytes — reserialised JSON must not verify", () => {
    const body = membershipBody();
    const header = sign(body, now);
    const reserialised = JSON.stringify(JSON.parse(body).data); // different bytes
    const r = verifyWhopWebhook({
      rawBody: reserialised,
      signatureHeader: header,
      secret: SECRET,
      nowSeconds: now,
    });
    expect(r.ok).toBe(false);
  });
});

describe("event name mapping", () => {
  it("maps Whop's current v5 action names", () => {
    expect(outcomeForAction("membership.went_valid")).toBe("activate");
    expect(outcomeForAction("membership.went_invalid")).toBe("deactivate");
    expect(outcomeForAction("payment.succeeded")).toBe("payment_succeeded");
    expect(outcomeForAction("payment.failed")).toBe("payment_failed");
  });

  it("also maps the legacy/alternate names", () => {
    expect(outcomeForAction("membership_activated")).toBe("activate");
    expect(outcomeForAction("membership_deactivated")).toBe("deactivate");
    expect(outcomeForAction("invoice_paid")).toBe("payment_succeeded");
    expect(outcomeForAction("invoice_past_due")).toBe("payment_failed");
  });

  it("maps app_* variants the same way", () => {
    expect(outcomeForAction("app_membership.went_valid")).toBe("activate");
    expect(outcomeForAction("app_payment.failed")).toBe("payment_failed");
  });

  it("ignores unrelated events rather than guessing", () => {
    expect(outcomeForAction("dispute.created")).toBe("ignore");
    expect(outcomeForAction("refund.created")).toBe("ignore");
    expect(outcomeForAction("membership.metadata_updated")).toBe("ignore");
  });
});

describe("paid access rules", () => {
  it("grants access on activation and successful payment", () => {
    expect(statusForOutcome("activate")).toBe("ACTIVE");
    expect(statusForOutcome("payment_succeeded")).toBe("ACTIVE");
  });

  it("past due never maps to an active status", () => {
    expect(statusForOutcome("payment_failed")).toBe("PAST_DUE");
    expect(statusForOutcome("payment_failed")).not.toBe("ACTIVE");
    expect(statusForOutcome("payment_failed")).not.toBe("TRIALING");
  });

  it("deactivation cancels", () => {
    expect(statusForOutcome("deactivate")).toBe("CANCELED");
  });

  it("an activate event whose payload says valid:false is downgraded to a deactivation", () => {
    expect(reconcileWithPayloadValidity("activate", false)).toBe("deactivate");
    expect(reconcileWithPayloadValidity("activate", true)).toBe("activate");
    // Missing flag leaves the action's own meaning intact.
    expect(reconcileWithPayloadValidity("activate", undefined)).toBe("activate");
  });
});

describe("plan mapping", () => {
  beforeEach(() => {
    process.env.WHOP_PLAN_STARTER = "plan_starter";
    process.env.WHOP_PLAN_GROWTH = "plan_growth";
    process.env.WHOP_PLAN_PRO = "plan_pro";
  });

  it("maps configured plan ids", () => {
    expect(planFromWhopIds({ planId: "plan_growth" })).toBe("GROWTH");
    expect(planFromWhopIds({ planId: "plan_pro" })).toBe("PRO");
  });

  it("falls back to product id", () => {
    expect(planFromWhopIds({ planId: null, productId: "plan_starter" })).toBe("STARTER");
  });

  it("returns null for an unmapped plan rather than guessing one", () => {
    expect(planFromWhopIds({ planId: "plan_unknown" })).toBeNull();
    expect(planFromWhopIds({})).toBeNull();
  });
});

describe("account linking helpers", () => {
  it("extracts an explicit business id from metadata", () => {
    expect(extractBusinessId({ metadata: { converana_business_id: "biz-1" } })).toBe("biz-1");
    expect(extractBusinessId({ metadata: {} })).toBeNull();
    expect(extractBusinessId({})).toBeNull();
  });

  it("extracts an email from metadata, normalised", () => {
    expect(extractEmail({ metadata: { converana_email: "Owner@Example.com " } })).toBe("owner@example.com");
  });

  it("extracts an email from checkout custom fields", () => {
    expect(
      extractEmail({ custom_field_responses: [{ question: "Your email", answer: "a@b.com" }] })
    ).toBe("a@b.com");
  });

  it("ignores non-email values", () => {
    expect(extractEmail({ metadata: { email: "not-an-email" } })).toBeNull();
    expect(extractEmail({})).toBeNull();
  });
});
