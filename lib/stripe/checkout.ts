import "server-only";
import type { Business, Plan } from "@prisma/client";
import { getStripeClient } from "./client";
import { prisma } from "@/lib/db/prisma";

/**
 * Customer-facing brand shown at the top of Stripe Checkout.
 *
 * Converana is the SaaS brand; Noël Company Ltd remains the legal entity on
 * the Stripe account. `branding_settings.display_name` changes the Checkout
 * heading only — Stripe still shows the registered business name in terms,
 * receipts and invoices, so this does not alter or misrepresent the legal
 * entity behind the transaction.
 */
const CHECKOUT_DISPLAY_NAME = "Converana";

function priceIdForPlan(plan: Plan): string | null {
  if (plan === "STARTER") return process.env.STRIPE_PRICE_STARTER || null;
  if (plan === "GROWTH") return process.env.STRIPE_PRICE_GROWTH || null;
  if (plan === "PRO") return process.env.STRIPE_PRICE_PRO || null;
  return null;
}

/**
 * Stripe pins a currency to a Customer once that customer has been billed,
 * and then refuses any price in a different currency:
 *
 *   "The price specified only supports `usd`. This doesn't match the
 *    expected currency: `eur`."
 *
 * A cancelled subscription still leaves its stripeCustomerId on the row (the
 * webhook only changes status), so without this the stale customer would
 * block every future checkout after a currency change — permanently, with no
 * way out from inside the app.
 *
 * Stripe gives no dedicated error code for this, so the message is matched.
 * Kept deliberately narrow: only a currency-mismatch is retried, and only by
 * dropping the customer so Stripe creates a fresh one. Every other error
 * still propagates untouched.
 */
function isCurrencyMismatchError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return /expected currency|only supports `?[a-z]{3}`?/i.test(message) && /currency/i.test(message);
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

  const baseParams = {
    mode: "subscription" as const,
    line_items: [{ price: priceId, quantity: 1 }],
    client_reference_id: business.id,
    metadata: { businessId: business.id, plan },
    subscription_data: { metadata: { businessId: business.id, plan } },
    allow_promotion_codes: true,
    // Show the customer-facing brand at the top of Checkout. Per Stripe this
    // overrides ONLY the heading — the legal entity (Noël Company Ltd) still
    // appears in terms, receipts and invoices, which is exactly what we want:
    // customers recognise Converana, while the legal/account details on the
    // Stripe account are untouched.
    branding_settings: { display_name: CHECKOUT_DISPLAY_NAME },
    success_url: `${appUrl}/dashboard/billing?checkout=success`,
    cancel_url: `${appUrl}/dashboard/billing?checkout=cancelled`,
  };

  try {
    return await stripe.checkout.sessions.create({
      ...baseParams,
      customer: subscription?.stripeCustomerId || undefined,
      customer_email: subscription?.stripeCustomerId ? undefined : business.email || undefined,
    });
  } catch (err) {
    // Only a stored customer can cause a currency mismatch — with no customer
    // Stripe creates one in the price's own currency.
    if (!subscription?.stripeCustomerId || !isCurrencyMismatchError(err)) throw err;

    console.warn(
      `[stripe/checkout] customer ${subscription.stripeCustomerId} is pinned to a different ` +
        `currency than the ${plan} price; starting checkout with a fresh customer for business ${business.id}`
    );

    // Retry once without the stale customer. The resulting subscription's new
    // customer id is written back by the webhook's normal upsert, so the
    // database self-heals with no manual step.
    return await stripe.checkout.sessions.create({
      ...baseParams,
      customer_email: business.email || undefined,
    });
  }
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
