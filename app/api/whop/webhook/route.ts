import { NextResponse, type NextRequest } from "next/server";
import { prisma } from "@/lib/db/prisma";
import { verifyWhopWebhook, WHOP_SIGNATURE_HEADER } from "@/lib/whop/verify";
import {
  outcomeForAction,
  planFromWhopIds,
  reconcileWithPayloadValidity,
  statusForOutcome,
} from "@/lib/whop/events";
import { resolveBusinessForWhop } from "@/lib/whop/link";
import { notifyBusiness } from "@/lib/notifications";
import type { Plan } from "@prisma/client";

/**
 * Whop webhook handler.
 *
 * Like the Stripe webhook, this is the ONLY place Whop-driven subscription
 * state is written — checkout redirects and client state are never trusted.
 * Nothing in the body is acted on until the signature verifies.
 *
 * Runs alongside the Stripe webhook during the migration; both write the
 * shared `plan`/`status` columns, which remain the single source of truth
 * for access (read via effectivePlan()).
 */

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

export async function POST(request: NextRequest) {
  const secret = process.env.WHOP_WEBHOOK_SECRET;
  if (!secret) {
    // Never accept unsigned traffic just because the secret is missing.
    console.error("[whop/webhook] WHOP_WEBHOOK_SECRET is not configured — rejecting");
    return NextResponse.json({ error: "Whop billing isn't configured." }, { status: 503 });
  }

  // Raw body: re-serialising parsed JSON would change bytes and break the HMAC.
  const rawBody = await request.text();
  const verification = verifyWhopWebhook({
    rawBody,
    signatureHeader: request.headers.get(WHOP_SIGNATURE_HEADER),
    secret,
  });

  if (!verification.ok) {
    console.warn(`[whop/webhook] rejected: ${verification.failure}`);
    // 400 for anything unverifiable — Whop should not treat these as
    // retryable successes, and no state has been touched.
    return NextResponse.json({ error: "Invalid signature." }, { status: 400 });
  }

  const { payload, signedAt } = verification;
  const data = payload.data as Record<string, unknown>;

  const rawOutcome = outcomeForAction(payload.action);
  if (rawOutcome === "ignore") {
    // Acknowledge so Whop stops retrying events we intentionally don't act on.
    return NextResponse.json({ received: true, action: payload.action, handled: false });
  }

  // The payload's own `valid` flag outranks the event name: an "activate"
  // whose membership is not valid is treated as a deactivation.
  const outcome = reconcileWithPayloadValidity(rawOutcome, data.valid);

  // On membership events `data.id` IS the membership; on payment events
  // `data.id` is the payment and the membership is `data.membership_id`.
  const isPaymentEvent = rawOutcome === "payment_succeeded" || rawOutcome === "payment_failed";
  const membershipId = isPaymentEvent ? str(data.membership_id) : str(data.id);
  const whopUserId = str(data.user_id);

  const link = await resolveBusinessForWhop({ membershipId, whopUserId, data });

  if (link.via === "unresolved") {
    // Acknowledged but deliberately not acted on — guessing an owner could
    // grant a stranger's paid access to the wrong account.
    console.warn(
      `[whop/webhook] could not link action=${payload.action} membership=${membershipId ?? "n/a"} ` +
        `whopUser=${whopUserId ?? "n/a"} email=${link.attemptedEmail ?? "none"} — no access changed`
    );
    return NextResponse.json({ received: true, handled: false, reason: "unlinked" });
  }

  const businessId = link.businessId;
  const existing = await prisma.subscription.findUnique({ where: { businessId } });

  // Idempotency / ordering guard. Whop retries deliver the same logical event
  // again; every write below is an upsert to the same terminal state, so a
  // replay is harmless. What must be prevented is an OLDER event overwriting
  // a newer one (e.g. a delayed went_invalid landing after a reactivation).
  if (existing?.whopLastEventAt && signedAt < existing.whopLastEventAt) {
    console.warn(
      `[whop/webhook] dropping stale event action=${payload.action} signedAt=${signedAt.toISOString()} ` +
        `lastApplied=${existing.whopLastEventAt.toISOString()}`
    );
    return NextResponse.json({ received: true, handled: false, reason: "stale_event" });
  }

  const status = statusForOutcome(outcome);
  if (!status) {
    return NextResponse.json({ received: true, handled: false });
  }

  // An unpaid invoice must never create paid access where none existed.
  if (outcome === "payment_failed" && !existing) {
    console.warn("[whop/webhook] payment_failed for a business with no subscription — not creating one");
    return NextResponse.json({ received: true, handled: false, reason: "no_subscription_to_downgrade" });
  }

  const mappedPlan = planFromWhopIds({
    planId: str(data.plan_id),
    productId: str(data.product_id),
  });

  // Only ever change the plan on a grant. On downgrades the previous plan is
  // retained for display/re-subscribe; effectivePlan() stops honouring it
  // once the status is no longer active.
  let plan: Plan | undefined;
  if (outcome === "activate" || outcome === "payment_succeeded") {
    if (mappedPlan) {
      plan = mappedPlan;
    } else {
      console.warn(
        `[whop/webhook] unmapped Whop plan_id=${str(data.plan_id) ?? "n/a"} ` +
          `product_id=${str(data.product_id) ?? "n/a"} — set WHOP_PLAN_STARTER/GROWTH/PRO. ` +
          `Keeping the existing plan rather than guessing.`
      );
    }
  }

  const periodEndSeconds = data.renewal_period_end ?? data.expires_at;
  const currentPeriodEnd =
    typeof periodEndSeconds === "number" && Number.isFinite(periodEndSeconds)
      ? new Date(periodEndSeconds * 1000)
      : undefined;

  await prisma.subscription.upsert({
    where: { businessId },
    create: {
      businessId,
      status,
      plan: plan ?? "STARTER",
      whopMembershipId: membershipId,
      whopUserId,
      whopPlanId: str(data.plan_id),
      whopLastEventAt: signedAt,
      currentPeriodEnd,
    },
    update: {
      status,
      ...(plan ? { plan } : {}),
      ...(membershipId ? { whopMembershipId: membershipId } : {}),
      ...(whopUserId ? { whopUserId } : {}),
      ...(str(data.plan_id) ? { whopPlanId: str(data.plan_id) } : {}),
      whopLastEventAt: signedAt,
      ...(currentPeriodEnd ? { currentPeriodEnd } : {}),
    },
  });

  if (outcome === "payment_failed") {
    await notifyBusiness({
      businessId,
      type: "PAYMENT_FAILED",
      title: "Payment failed",
      body: "Your last payment didn't go through. Update your billing details to keep Converana active.",
    });
  }

  console.log(
    `[whop/webhook] applied action=${payload.action} outcome=${outcome} status=${status} ` +
      `business=${businessId} via=${link.via}`
  );

  return NextResponse.json({ received: true, handled: true });
}
