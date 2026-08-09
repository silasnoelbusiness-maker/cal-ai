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
 * True when the business has a subscription Stripe is actively billing —
 * changing plans for these must update the existing subscription, never
 * start a second Checkout Session (which would create a second, parallel
 * subscription and double-bill the customer).
 */
export function hasBillableSubscription(
  subscription: { status: string; stripeSubscriptionId: string | null } | null
) {
  return Boolean(
    subscription?.stripeSubscriptionId &&
      (subscription.status === "ACTIVE" || subscription.status === "TRIALING" || subscription.status === "PAST_DUE")
  );
}

/**
 * Changes the price on an existing Stripe subscription in place (upgrade or
 * downgrade), with prorations. Used instead of Checkout whenever the
 * business already has a subscription Stripe is billing.
 */
export async function changeSubscriptionPlan(business: Business, plan: Plan) {
  const priceId = priceIdForPlan(plan);
  if (!priceId) {
    throw new Error(
      `No Stripe price configured for the ${plan} plan. Set STRIPE_PRICE_${plan} in your environment.`
    );
  }

  const subscription = await prisma.subscription.findUnique({ where: { businessId: business.id } });
  if (!subscription?.stripeSubscriptionId) {
    throw new Error("No active subscription to change.");
  }

  const stripe = getStripeClient();
  const stripeSubscription = await stripe.subscriptions.retrieve(subscription.stripeSubscriptionId);
  const itemId = stripeSubscription.items.data[0]?.id;
  if (!itemId) {
    throw new Error("Couldn't find the subscription item to update.");
  }

  await stripe.subscriptions.update(subscription.stripeSubscriptionId, {
    items: [{ id: itemId, price: priceId }],
    proration_behavior: "create_prorations",
    metadata: { businessId: business.id, plan },
  });
  // The webhook (customer.subscription.updated) is still what actually
  // writes the new plan/status to our database — this call only tells
  // Stripe to change it.
}

/**
 * Creates a Stripe Checkout session for a brand-new subscription. The
 * business id travels as client_reference_id and in metadata — the webhook
 * is the only thing that ever updates subscription state, never the client
 * redirect. Never call this for a business that already has a billable
 * subscription — use changeSubscriptionPlan instead, or it will create a
 * second, parallel subscription.
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

  if (hasBillableSubscription(subscription)) {
    throw new Error("This business already has an active subscription — change its plan instead of starting a new checkout.");
  }

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
