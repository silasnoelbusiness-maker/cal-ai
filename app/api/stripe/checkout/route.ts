import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { changeSubscriptionPlan, createCheckoutSession, hasBillableSubscription } from "@/lib/stripe/checkout";
import { BillingUnavailableError } from "@/lib/stripe/client";
import { prisma } from "@/lib/db/prisma";

const BodySchema = z.object({ plan: z.enum(["STARTER", "GROWTH", "PRO"]) });

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`stripe-checkout:${auth.business.id}`, 10, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const json = await request.json().catch(() => null);
  const parsed = BodySchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || request.nextUrl.origin;

  try {
    const subscription = await prisma.subscription.findUnique({ where: { businessId: auth.business.id } });

    if (hasBillableSubscription(subscription)) {
      // Already paying — change the existing subscription's price instead
      // of starting a second Checkout Session, which would create a second
      // parallel subscription and double-bill the customer.
      if (subscription!.plan === parsed.data.plan) {
        return NextResponse.json({ changed: false, message: "You're already on that plan." });
      }

      const result = await changeSubscriptionPlan(auth.business, parsed.data.plan);

      if (result.kind === "unchanged") {
        return NextResponse.json({ changed: false, message: "You're already on that plan." });
      }
      if (result.kind === "downgrade_scheduled") {
        return NextResponse.json({
          changed: true,
          kind: "downgrade_scheduled",
          effectiveAt: result.effectiveAt.toISOString(),
          message: "Downgrade scheduled. Your current plan stays active until the end of this billing period.",
        });
      }
      return NextResponse.json({
        changed: true,
        kind: "upgraded",
        message: "Upgraded. You've been charged the prorated difference for the rest of this period.",
      });
    }

    const session = await createCheckoutSession(auth.business, parsed.data.plan, appUrl);
    return NextResponse.json({ url: session.url });
  } catch (err) {
    if (err instanceof BillingUnavailableError) return apiError(err.message, 503);
    console.error("[api/stripe/checkout] failed", err);
    return apiError(err instanceof Error ? err.message : "Couldn't start checkout.", 500);
  }
}
