import "server-only";
import type { Business, Plan } from "@prisma/client";
import { getStripeClient } from "./client";
import { prisma } from "@/lib/db/prisma";

function priceIdForPlan(plan: Plan): string | null {
  if (plan === "STARTER") return process.env.STRIPE_PRICE_STARTER || null;
  if (plan === "GROWTH") return process.env.STRIPE_PRICE_GROWTH || null;
  if (plan === "PRO") return process.env.STRIPE_PRICE_PRO || null;
  return null;
}

/**
 * Creates a Stripe Checkout session for a plan. The business id travels as
 * client_reference_id and in metadata — the webhook is the only thing that
 * ever updates subscription state, never the client redirect.
 */
export async function createCheckoutSession(business: Business, plan: Plan, appUrl: string) {
  const priceId = priceIdForPlan(plan);
  if (!priceId) {
    throw new Error(
      `No Stripe price configured for the ${plan} plan. Set STRIPE_PRICE_${plan} in your environment.`
    );
  }

  const stripe = getStripeClient();
  const subscription = await prisma.subscription.findUnique({ where: { businessId: business.id } });

  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    line_items: [{ price: priceId, quantity: 1 }],
    client_reference_id: business.id,
    customer: subscription?.stripeCustomerId || undefined,
    customer_email: subscription?.stripeCustomerId ? undefined : business.email || undefined,
    metadata: { businessId: business.id, plan },
    subscription_data: { metadata: { businessId: business.id, plan } },
    allow_promotion_codes: true,
    success_url: `${appUrl}/dashboard/billing?checkout=success`,
    cancel_url: `${appUrl}/dashboard/billing?checkout=cancelled`,
  });

  return session;
}

export async function createPortalSession(business: Business, appUrl: string) {
  const stripe = getStripeClient();
  const subscription = await prisma.subscription.findUnique({ where: { businessId: business.id } });

  if (!subscription?.stripeCustomerId) {
    throw new Error("No billing account found yet. Start a subscription first.");
  }

  const session = await stripe.billingPortal.sessions.create({
    customer: subscription.stripeCustomerId,
    return_url: `${appUrl}/dashboard/billing`,
  });

  return session;
}
