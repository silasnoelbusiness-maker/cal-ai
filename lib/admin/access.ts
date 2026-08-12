import "server-only";
import { prisma } from "@/lib/db/prisma";
import type { Plan } from "@prisma/client";

/**
 * Manual paid-access control for the V1 launch.
 *
 * Customers buy through Whop externally; an admin then activates them here
 * after confirming the purchase. This writes the SAME Subscription row that
 * Stripe writes, so `effectivePlan()` and every plan-limit check keep working
 * untouched — there is no second source of truth for access.
 *
 * Reuses the existing schema exactly as-is: no new columns, no migration.
 * A manual grant is recorded with status ACTIVE and no Stripe identifiers,
 * which is what distinguishes it from a Stripe-billed subscription.
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
