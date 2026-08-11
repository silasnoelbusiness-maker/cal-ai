import { NextResponse, type NextRequest } from "next/server";
import type Stripe from "stripe";
import { getStripeClient } from "@/lib/stripe/client";
import { isStripeConfigured } from "@/lib/auth/config";
import { prisma } from "@/lib/db/prisma";
import { planFromPriceId } from "@/lib/plans";
import { notifyBusiness } from "@/lib/notifications";
import { mapStripeStatus } from "@/lib/stripe/status";
import type { Plan } from "@prisma/client";

/**
 * Stripe webhook handler — the ONLY place subscription state is written.
 * Client-side billing state (query params, local state) is never trusted;
 * this route verifies Stripe's signature and is the single source of truth.
 */
export async function POST(request: NextRequest) {
  if (!isStripeConfigured) {
    return NextResponse.json({ error: "Billing isn't configured." }, { status: 503 });
  }

  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  const signature = request.headers.get("stripe-signature");
  if (!webhookSecret || !signature) {
    return NextResponse.json({ error: "Missing webhook signature." }, { status: 400 });
  }

  const rawBody = await request.text();
  const stripe = getStripeClient();

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
  } catch (err) {
    console.error("[stripe/webhook] signature verification failed", err);
    return NextResponse.json({ error: "Invalid signature." }, { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed":
        await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session);
        break;
      case "customer.subscription.created":
      case "customer.subscription.updated":
        await handleSubscriptionUpsert(event.data.object as Stripe.Subscription);
        break;
      case "customer.subscription.deleted":
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription);
        break;
      case "invoice.payment_failed":
        await handlePaymentFailed(event.data.object as Stripe.Invoice);
        break;
      default:
        break;
    }
  } catch (err) {
    console.error(`[stripe/webhook] failed to handle ${event.type}`, err);
    // Return 200 anyway for events we can't map to a business, so Stripe
    // doesn't retry indefinitely on non-recoverable data issues.
  }

  return NextResponse.json({ received: true });
}

async function resolveBusinessId(subscription: Stripe.Subscription): Promise<string | null> {
  if (subscription.metadata?.businessId) return subscription.metadata.businessId;
  const customerId = typeof subscription.customer === "string" ? subscription.customer : subscription.customer.id;
  const existing = await prisma.subscription.findFirst({ where: { stripeCustomerId: customerId } });
  return existing?.businessId || null;
}

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  const businessId = session.client_reference_id || session.metadata?.businessId;
  if (!businessId) return;

  const customerId = typeof session.customer === "string" ? session.customer : session.customer?.id;
  if (!customerId) return;

  await prisma.subscription.upsert({
    where: { businessId },
    create: { businessId, stripeCustomerId: customerId },
    update: { stripeCustomerId: customerId },
  });
}

async function handleSubscriptionUpsert(subscription: Stripe.Subscription) {
  const businessId = await resolveBusinessId(subscription);
  if (!businessId) return;

  const item = subscription.items.data[0];
  const plan: Plan = planFromPriceId(item?.price?.id) || "STARTER";
  const customerId = typeof subscription.customer === "string" ? subscription.customer : subscription.customer.id;
  const currentPeriodEnd = item?.current_period_end ? new Date(item.current_period_end * 1000) : null;

  await prisma.subscription.upsert({
    where: { businessId },
    create: {
      businessId,
      stripeCustomerId: customerId,
      stripeSubscriptionId: subscription.id,
      plan,
      status: mapStripeStatus(subscription.status),
      currentPeriodEnd,
    },
    update: {
      stripeCustomerId: customerId,
      stripeSubscriptionId: subscription.id,
      plan,
      status: mapStripeStatus(subscription.status),
      currentPeriodEnd,
    },
  });
}

async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  const businessId = await resolveBusinessId(subscription);
  if (!businessId) return;

  await prisma.subscription.updateMany({
    where: { businessId },
    data: { status: "CANCELED" },
  });
}

async function handlePaymentFailed(invoice: Stripe.Invoice) {
  const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
  if (!customerId) return;

  const subscription = await prisma.subscription.findFirst({ where: { stripeCustomerId: customerId } });
  if (!subscription) return;

  await prisma.subscription.update({ where: { businessId: subscription.businessId }, data: { status: "PAST_DUE" } });

  await notifyBusiness({
    businessId: subscription.businessId,
    type: "PAYMENT_FAILED",
    title: "Payment failed",
    body: "Your last payment didn't go through. Update your billing details to keep Converana active.",
  });
}
