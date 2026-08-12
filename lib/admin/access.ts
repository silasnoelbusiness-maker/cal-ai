import "server-only";
import { prisma } from "@/lib/db/prisma";
import { hasBillableSubscription } from "@/lib/stripe/checkout";
import type { Plan } from "@prisma/client";

/**
 * Emergency/support-only manual paid-access control.
 *
 * This is NOT part of the customer flow. Customers subscribe through Stripe
 * Checkout and are activated automatically by the Stripe webhook
 * (app/api/stripe/webhook), which is the authoritative writer of subscription
 * state. These helpers exist purely so support can recover an account when
 * something goes wrong — a webhook that never arrived, a billing dispute, a
 * goodwill comp — without waiting on a fix.
 *
 * It writes the SAME Subscription row Stripe writes, so `effectivePlan()` and
 * every plan-limit check keep working untouched and there is no second source
 * of truth for access. Reuses the existing schema exactly as-is: no new
 * columns, no migration.
 *
 * Caveat worth knowing when using it: a manual grant has no Stripe
 * subscription behind it, so Stripe will not renew or cancel it, and a later
 * Stripe webhook for the same business will overwrite whatever was set here.
 */

export type AccessResult =
  | { ok: true; businessId: string; businessName: string; plan: Plan }
  | { ok: false; error: string };

/**
 * Resolves an email to the business whose access is being changed.
 * Mirrors getCurrentBusiness(): a user's primary business is their earliest
 * membership.
 */
type FindResult =
  | { found: true; business: { id: string; name: string } }
  | { found: false; error: string };

async function findBusinessByEmail(email: string): Promise<FindResult> {
  const normalised = email.trim().toLowerCase();
  if (!normalised) return { found: false, error: "Enter an email address." };

  const user = await prisma.user.findUnique({ where: { email: normalised } });
  if (!user) {
    return {
      found: false,
      error:
        "No Converana account with that email. The customer must sign up first — activation only works on an existing account.",
    };
  }

  const membership = await prisma.businessMember.findFirst({
    where: { userId: user.id },
    orderBy: { createdAt: "asc" },
    include: { business: true },
  });
  if (!membership) {
    return {
      found: false,
      error: "That account exists but hasn't finished onboarding yet, so it has no business to activate.",
    };
  }

  return { found: true, business: membership.business };
}

/** Grants paid access at the given plan. Idempotent — re-running is a no-op. */
export async function grantPaidAccess(email: string, plan: Plan): Promise<AccessResult> {
  const found = await findBusinessByEmail(email);
  if (!found.found) return { ok: false, error: found.error };

  const { business } = found;

  await prisma.subscription.upsert({
    where: { businessId: business.id },
    create: { businessId: business.id, plan, status: "ACTIVE" },
    update: { plan, status: "ACTIVE" },
  });

  return { ok: true, businessId: business.id, businessName: business.name, plan };
}

/**
 * Revokes paid access. Sets status CANCELED rather than deleting the row:
 * effectivePlan() stops honouring the plan as soon as the status is not
 * active, while the last plan is retained for display and re-activation.
 */
export async function revokePaidAccess(email: string): Promise<AccessResult> {
  const found = await findBusinessByEmail(email);
  if (!found.found) return { ok: false, error: found.error };

  const { business } = found;

  const existing = await prisma.subscription.findUnique({ where: { businessId: business.id } });
  if (!existing) {
    return { ok: false, error: "That business has no subscription, so there is nothing to revoke." };
  }

  await prisma.subscription.update({
    where: { businessId: business.id },
    data: { status: "CANCELED" },
  });

  return { ok: true, businessId: business.id, businessName: business.name, plan: existing.plan };
}

/**
 * Detaches a business from its stored Stripe customer/subscription ids so the
 * next checkout starts a brand-new Stripe customer.
 *
 * Needed when the stored customer is pinned to a currency that no longer
 * matches the configured prices (Stripe locks a customer's currency once
 * billed). createCheckoutSession already recovers from this automatically, so
 * this is a manual lever for support rather than a required step.
 *
 * Refuses to run while Stripe is still actively billing the subscription —
 * clearing the ids then would orphan a live subscription that keeps charging
 * the customer with nothing in Converana pointing at it.
 */
export async function resetStripeBillingLink(email: string): Promise<AccessResult> {
  const found = await findBusinessByEmail(email);
  if (!found.found) return { ok: false, error: found.error };

  const { business } = found;
  const existing = await prisma.subscription.findUnique({ where: { businessId: business.id } });

  if (!existing) {
    return { ok: false, error: "That business has no subscription record, so there is nothing to reset." };
  }

  if (hasBillableSubscription(existing)) {
    return {
      ok: false,
      error:
        "That subscription is still being billed by Stripe. Cancel it in the Stripe dashboard first — " +
        "clearing the link now would leave a live subscription charging with nothing pointing at it.",
    };
  }

  await prisma.subscription.update({
    where: { businessId: business.id },
    data: { stripeCustomerId: null, stripeSubscriptionId: null, status: "NONE" },
  });

  return { ok: true, businessId: business.id, businessName: business.name, plan: existing.plan };
}

/** Read-only lookup so an admin can confirm current state before changing it. */
export async function lookupAccess(email: string) {
  const found = await findBusinessByEmail(email);
  if (!found.found) return { ok: false as const, error: found.error };

  const subscription = await prisma.subscription.findUnique({
    where: { businessId: found.business.id },
  });

  return {
    ok: true as const,
    business: found.business,
    subscription,
  };
}
