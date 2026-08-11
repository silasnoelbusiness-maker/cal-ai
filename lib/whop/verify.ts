import "server-only";
import { createHmac, timingSafeEqual } from "crypto";

/**
 * Whop webhook signature verification.
 *
 * The algorithm below mirrors `makeWebhookValidator` in Whop's official
 * `@whop/api` SDK (verified against the published package source), so this is
 * the same scheme Whop signs with — reimplemented here for two reasons:
 *
 *  1. `@whop/api` is still a 0.0.x release and pulls in Whop's entire GraphQL
 *     client; this endpoint sits in a payment path and only needs the HMAC.
 *  2. The SDK compares signatures with `!==`, which is not constant-time.
 *     This uses `timingSafeEqual` instead.
 *
 * Scheme:
 *   header:  x-whop-signature: t=<unix seconds>,v1=<hex hmac>
 *   signed:  `${timestamp}.${rawBody}`
 *   hmac:    HMAC-SHA256 with the webhook secret, lowercase hex
 *   replay:  reject when |now - timestamp| > 300s
 */

export const WHOP_SIGNATURE_HEADER = "x-whop-signature";

/** Whop's webhook payload API version, asserted before anything is trusted. */
export const WHOP_API_VERSION = "v5";

const MAX_CLOCK_SKEW_SECONDS = 300;

export type WhopVerifyFailure =
  | "missing_secret"
  | "missing_signature"
  | "malformed_signature"
  | "unsupported_version"
  | "invalid_timestamp"
  | "signature_mismatch"
  | "invalid_payload";

export type WhopVerifyResult =
  | { ok: true; payload: WhopWebhookPayload; signedAt: Date }
  | { ok: false; failure: WhopVerifyFailure };

export interface WhopWebhookPayload {
  api_version: string;
  action: string;
  data: Record<string, unknown>;
}

function constantTimeEqualsHex(a: string, b: string): boolean {
  // Hash both sides first so differing lengths can't throw and can't leak
  // length information through timing.
  const bufA = createHmac("sha256", "cmp").update(a).digest();
  const bufB = createHmac("sha256", "cmp").update(b).digest();
  return timingSafeEqual(bufA, bufB);
}

function isWhopWebhookPayload(value: unknown): value is WhopWebhookPayload {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  if (v.api_version !== WHOP_API_VERSION) return false;
  if (typeof v.action !== "string") return false;
  if (!v.data || typeof v.data !== "object") return false;
  return true;
}

/**
 * Verifies a raw request body against the `x-whop-signature` header.
 * `rawBody` MUST be the exact bytes received — re-serialising parsed JSON
 * changes key order/whitespace and will fail verification.
 */
export function verifyWhopWebhook(params: {
  rawBody: string;
  signatureHeader: string | null;
  secret: string | undefined;
  nowSeconds?: number;
}): WhopVerifyResult {
  const { rawBody, signatureHeader, secret } = params;

  if (!secret) return { ok: false, failure: "missing_secret" };
  if (!signatureHeader) return { ok: false, failure: "missing_signature" };

  // Parse `t=<timestamp>,v1=<signature>`. Tolerates extra comma-separated
  // parts and ordering, so an added scheme version won't break parsing.
  let timestampRaw: string | undefined;
  let sentSignature: string | undefined;
  for (const part of signatureHeader.split(",")) {
    const [key, value] = part.trim().split("=");
    if (key === "t") timestampRaw = value;
    else if (key === "v1") sentSignature = value;
  }

  if (!timestampRaw || !sentSignature) {
    // A header that parsed but carries only an unknown scheme version is
    // reported distinctly, so an upgrade shows up in logs as a version
    // problem rather than as a generic malformed header.
    return {
      ok: false,
      failure: signatureHeader.includes("t=") ? "unsupported_version" : "malformed_signature",
    };
  }

  const timestamp = Number.parseInt(timestampRaw, 10);
  if (Number.isNaN(timestamp)) return { ok: false, failure: "invalid_timestamp" };

  const now = params.nowSeconds ?? Math.round(Date.now() / 1000);
  if (Math.abs(now - timestamp) > MAX_CLOCK_SKEW_SECONDS) {
    return { ok: false, failure: "invalid_timestamp" };
  }

  const expected = createHmac("sha256", secret).update(`${timestamp}.${rawBody}`).digest("hex");
  if (!constantTimeEqualsHex(expected, sentSignature)) {
    return { ok: false, failure: "signature_mismatch" };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return { ok: false, failure: "invalid_payload" };
  }
  if (!isWhopWebhookPayload(parsed)) return { ok: false, failure: "invalid_payload" };

  return { ok: true, payload: parsed, signedAt: new Date(timestamp * 1000) };
}
