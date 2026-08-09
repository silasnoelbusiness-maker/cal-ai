import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiUnauthorized } from "@/lib/api/response";
import { changeSubscriptionPlan, createCheckoutSession, hasBillableSubscription } from "@/lib/stripe/checkout";
import { BillingUnavailableError } from "@/lib/stripe/client";
import { prisma } from "@/lib/db/prisma";

const BodySchema = z.object({ plan: z.enum(["STARTER", "GROWTH", "PRO"]) });

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

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
        return NextResponse.json({ url: `${appUrl}/dashboard/billing` });
      }
      await changeSubscriptionPlan(auth.business, parsed.data.plan);
      return NextResponse.json({ url: `${appUrl}/dashboard/billing?checkout=success` });
    }

    const session = await createCheckoutSession(auth.business, parsed.data.plan, appUrl);
    return NextResponse.json({ url: session.url });
  } catch (err) {
    if (err instanceof BillingUnavailableError) return apiError(err.message, 503);
    console.error("[api/stripe/checkout] failed", err);
    return apiError(err instanceof Error ? err.message : "Couldn't start checkout.", 500);
  }
}
