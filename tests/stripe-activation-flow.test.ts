import { beforeEach, describe, expect, it, vi } from "vitest";
import { planFromPriceId } from "@/lib/plans";
import { mapStripeStatus } from "@/lib/stripe/status";
import { effectivePlan } from "@/lib/plans";

/**
 * End-to-end verification of the automatic Stripe activation path:
 *
 *   plan chosen -> Checkout -> webhook -> subscription stored ->
 *   plan assigned -> limits available -> cancellation/failure downgrade
 *
 * No real Stripe calls and no charges: the pieces the webhook composes are
 * exercised directly against real Stripe-shaped payloads.
 */

const PRICES = {
  starter: "price_live_starter",
  growth: "price_live_growth",
  pro: "price_live_pro",
};

beforeEach(() => {
  vi.clearAllMocks();
  process.env.STRIPE_PRICE_STARTER = PRICES.starter;
  process.env.STRIPE_PRICE_GROWTH = PRICES.growth;
  process.env.STRIPE_PRICE_PRO = PRICES.pro;
});

describe("checkout price -> plan assignment", () => {
  it("assigns each plan from its own Stripe price id", () => {
    expect(planFromPriceId(PRICES.starter)).toBe("STARTER");
    expect(planFromPriceId(PRICES.growth)).toBe("GROWTH");
    expect(planFromPriceId(PRICES.pro)).toBe("PRO");
  });

  it("returns null for an unknown price rather than guessing a paid tier", () => {
    expect(planFromPriceId("price_someone_elses")).toBeNull();
    expect(planFromPriceId(null)).toBeNull();
    expect(planFromPriceId(undefined)).toBeNull();
  });
});

describe("subscription becomes active automatically after payment", () => {
  // The exact composition the webhook performs on
  // customer.subscription.created/updated.
  function activationFrom(stripeStatus: string, priceId: string) {
    const plan = planFromPriceId(priceId) || "STARTER";
    const status = mapStripeStatus(stripeStatus as never);
    return { plan, status, enforced: effectivePlan({ plan, status }) };
  }

  it("a paid Growth checkout results in an ACTIVE Growth subscription with Growth limits", () => {
    const r = activationFrom("active", PRICES.growth);
    expect(r.status).toBe("ACTIVE");
    expect(r.plan).toBe("GROWTH");
    expect(r.enforced).toBe("GROWTH");
  });

  it("a paid Pro checkout yields Pro limits", () => {
    expect(activationFrom("active", PRICES.pro).enforced).toBe("PRO");
  });

  it("a trialing subscription still grants its plan's limits", () => {
    const r = activationFrom("trialing", PRICES.pro);
    expect(r.status).toBe("TRIALING");
    expect(r.enforced).toBe("PRO");
  });

  it("an incomplete checkout does NOT grant paid limits", () => {
    const r = activationFrom("incomplete", PRICES.pro);
    expect(r.status).toBe("INCOMPLETE");
    expect(r.enforced).toBe("STARTER");
  });
});

describe("cancellation and payment failure downgrade automatically", () => {
  it("cancellation drops a Pro account back to Starter limits", () => {
    expect(effectivePlan({ plan: "PRO", status: "CANCELED" })).toBe("STARTER");
  });

  it("an unpaid subscription loses its paid limits", () => {
    expect(effectivePlan({ plan: "PRO", status: "UNPAID" })).toBe("STARTER");
  });

  it("past_due keeps access during the dunning grace period", () => {
    // Deliberate: Stripe retries failed payments before giving up, and the
    // customer is emailed. Access is removed once Stripe cancels or marks
    // the subscription unpaid.
    expect(mapStripeStatus("past_due" as never)).toBe("PAST_DUE");
    expect(effectivePlan({ plan: "GROWTH", status: "PAST_DUE" })).toBe("GROWTH");
  });

  it("a business with no subscription at all gets Starter limits", () => {
    expect(effectivePlan(null)).toBe("STARTER");
    expect(effectivePlan(undefined)).toBe("STARTER");
  });

  it("the default NONE status a billing-page visit creates grants nothing", () => {
    // billing/page.tsx upserts an empty row so the page can render; schema
    // defaults are plan STARTER / status NONE, which must not be paid access.
    expect(effectivePlan({ plan: "STARTER", status: "NONE" })).toBe("STARTER");
    expect(effectivePlan({ plan: "PRO", status: "NONE" })).toBe("STARTER");
  });
});

describe("upgrades and downgrades", () => {
  it("switching price on the same subscription reassigns the plan", () => {
    // customer.subscription.updated carrying the new price.
    expect(planFromPriceId(PRICES.starter)).toBe("STARTER");
    expect(planFromPriceId(PRICES.pro)).toBe("PRO");
  });

  it("a downgrade still enforces the new lower plan while active", () => {
    expect(effectivePlan({ plan: "STARTER", status: "ACTIVE" })).toBe("STARTER");
  });
});

describe("client cannot fake paid access", () => {
  it("plan is derived from the Stripe price id, never from a client-supplied plan name", () => {
    // The checkout route accepts a plan name only to choose which Stripe
    // price to bill. Access itself comes from the webhook's price id, so a
    // forged request cannot mint a plan without a real payment.
    expect(planFromPriceId("PRO")).toBeNull();
    expect(planFromPriceId("pro")).toBeNull();
    expect(planFromPriceId("")).toBeNull();
  });
});
