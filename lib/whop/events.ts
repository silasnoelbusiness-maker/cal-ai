import type { Plan, SubscriptionStatus } from "@prisma/client";

/**
 * Whop event handling.
 *
 * Naming note: Whop's current v5 payloads (per the official @whop/api SDK)
 * use `membership.went_valid`, `membership.went_invalid`,
 * `payment.succeeded` and `payment.failed`. Older/alternate docs and
 * dashboards refer to the same concepts as `membership_activated`,
 * `membership_deactivated`, `invoice_paid` and `invoice_past_due`. Both
 * spellings are accepted and normalised to the same outcome so the endpoint
 * keeps working across either naming, and `app_*` variants are treated the
 * same as their non-prefixed counterparts.
 */

export type WhopOutcome =
  | "activate" // grant paid access
  | "deactivate" // remove paid access
  | "payment_succeeded" // confirm paid access
  | "payment_failed" // mark past due — must NOT grant access
  | "ignore";

const ACTIVATE = new Set([
  "membership.went_valid",
  "app_membership.went_valid",
  "membership_activated",
  "membership.activated",
]);

const DEACTIVATE = new Set([
  "membership.went_invalid",
  "app_membership.went_invalid",
  "membership_deactivated",
  "membership.deactivated",
]);

const PAYMENT_OK = new Set(["payment.succeeded", "app_payment.succeeded", "invoice_paid", "invoice.paid"]);

const PAYMENT_BAD = new Set([
  "payment.failed",
  "app_payment.failed",
  "invoice_past_due",
  "invoice.past_due",
  "invoice_payment_failed",
]);

export function outcomeForAction(action: string): WhopOutcome {
  const a = action.trim().toLowerCase();
  if (ACTIVATE.has(a)) return "activate";
  if (DEACTIVATE.has(a)) return "deactivate";
  if (PAYMENT_OK.has(a)) return "payment_succeeded";
  if (PAYMENT_BAD.has(a)) return "payment_failed";
  return "ignore";
}

/**
 * Maps an outcome to the subscription status to persist.
 *
 * `payment_failed` deliberately maps to PAST_DUE and never to an active
 * status — an unpaid invoice must not be able to grant paid access. The
 * caller additionally refuses to create a *new* paid subscription from a
 * payment_failed event; it can only downgrade an existing one.
 */
export function statusForOutcome(outcome: WhopOutcome): SubscriptionStatus | null {
  switch (outcome) {
    case "activate":
    case "payment_succeeded":
      return "ACTIVE";
    case "deactivate":
      return "CANCELED";
    case "payment_failed":
      return "PAST_DUE";
    default:
      return null;
  }
}

/**
 * Resolves a Whop plan/product id to a Converana plan using the
 * WHOP_PLAN_* environment variables. Returns null when unmapped — the caller
 * must then refuse to guess a plan rather than silently granting one.
 */
export function planFromWhopIds(ids: { planId?: string | null; productId?: string | null }): Plan | null {
  const candidates = [ids.planId, ids.productId].filter(Boolean) as string[];
  const map: [string | undefined, Plan][] = [
    [process.env.WHOP_PLAN_STARTER, "STARTER"],
    [process.env.WHOP_PLAN_GROWTH, "GROWTH"],
    [process.env.WHOP_PLAN_PRO, "PRO"],
  ];
  for (const candidate of candidates) {
    for (const [envValue, plan] of map) {
      if (envValue && envValue === candidate) return plan;
    }
  }
  return null;
}

/**
 * Whop membership payloads carry a `valid` boolean and a `status` string.
 * `valid` is authoritative for access, so an "activate" action whose payload
 * says the membership is not valid is treated as a deactivation — the event
 * name alone is never allowed to grant access.
 */
export function reconcileWithPayloadValidity(outcome: WhopOutcome, valid: unknown): WhopOutcome {
  if (outcome === "activate" && valid === false) return "deactivate";
  return outcome;
}
