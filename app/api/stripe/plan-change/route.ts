import { NextResponse } from "next/server";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { cancelScheduledPlanChange } from "@/lib/stripe/checkout";
import { BillingUnavailableError } from "@/lib/stripe/client";

/**
 * Cancels a scheduled plan change ("Keep current plan"). The subscription
 * that's being kept is looked up from the session's own business — the
 * client sends no plan, id or schedule, so it can't cancel or redirect
 * anyone else's change.
 */
export async function DELETE() {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`stripe-plan-change:${auth.business.id}`, 10, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  try {
    const { released } = await cancelScheduledPlanChange(auth.business);
    return NextResponse.json({
      released,
      message: released
        ? "Scheduled change cancelled. You'll stay on your current plan."
        : "There was no scheduled change to cancel.",
    });
  } catch (err) {
    if (err instanceof BillingUnavailableError) return apiError(err.message, 503);
    console.error("[api/stripe/plan-change] failed", err);
    return apiError(err instanceof Error ? err.message : "Couldn't cancel the scheduled change.", 500);
  }
}
