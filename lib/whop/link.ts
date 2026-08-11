import "server-only";
import { prisma } from "@/lib/db/prisma";

/**
 * Resolving a Whop membership to a Converana business.
 *
 * Whop's v5 membership/payment payloads do NOT contain the customer's email
 * address — they carry `user_id`, `plan_id`, `product_id`, `membership_id`,
 * optional `metadata`, and custom field responses. So linking cannot rely on
 * email being present in the event; it is resolved in priority order:
 *
 *   1. An existing subscription already linked to this membership id.
 *   2. An existing subscription already linked to this Whop user id.
 *   3. `metadata.converana_business_id` — set this at checkout for the most
 *      reliable link.
 *   4. An email found in `metadata` or in the checkout custom-field
 *      responses, matched against the unique `User.email`, then followed to
 *      that user's earliest business (mirroring getCurrentBusiness()).
 *
 * When none resolve the caller records the event and acknowledges it without
 * granting anything — guessing an owner would be worse than doing nothing.
 */

const EMAIL_KEYS = ["converana_email", "email", "user_email", "customer_email", "account_email"];
const BUSINESS_ID_KEYS = ["converana_business_id", "business_id", "businessId"];

function looksLikeEmail(value: unknown): value is string {
  return typeof value === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
}

export function extractEmail(data: Record<string, unknown>): string | null {
  const metadata = (data.metadata ?? null) as Record<string, unknown> | null;
  if (metadata) {
    for (const key of EMAIL_KEYS) {
      const v = metadata[key];
      if (looksLikeEmail(v)) return v.trim().toLowerCase();
    }
  }

  // Checkout custom fields arrive as an array of { question/name, answer/value }.
  const responses = data.custom_field_responses;
  if (Array.isArray(responses)) {
    for (const entry of responses) {
      if (!entry || typeof entry !== "object") continue;
      const rec = entry as Record<string, unknown>;
      for (const v of [rec.answer, rec.value, rec.response]) {
        if (looksLikeEmail(v)) return v.trim().toLowerCase();
      }
    }
  }

  return null;
}

export function extractBusinessId(data: Record<string, unknown>): string | null {
  const metadata = (data.metadata ?? null) as Record<string, unknown> | null;
  if (!metadata) return null;
  for (const key of BUSINESS_ID_KEYS) {
    const v = metadata[key];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return null;
}

export type LinkResult =
  | { businessId: string; via: "membership_id" | "whop_user_id" | "metadata_business_id" | "email" }
  | { businessId: null; via: "unresolved"; attemptedEmail: string | null };

export async function resolveBusinessForWhop(params: {
  membershipId: string | null;
  whopUserId: string | null;
  data: Record<string, unknown>;
}): Promise<LinkResult> {
  const { membershipId, whopUserId, data } = params;

  if (membershipId) {
    const existing = await prisma.subscription.findUnique({
      where: { whopMembershipId: membershipId },
      select: { businessId: true },
    });
    if (existing) return { businessId: existing.businessId, via: "membership_id" };
  }

  if (whopUserId) {
    const existing = await prisma.subscription.findFirst({
      where: { whopUserId },
      select: { businessId: true },
    });
    if (existing) return { businessId: existing.businessId, via: "whop_user_id" };
  }

  const metadataBusinessId = extractBusinessId(data);
  if (metadataBusinessId) {
    const business = await prisma.business.findUnique({
      where: { id: metadataBusinessId },
      select: { id: true },
    });
    if (business) return { businessId: business.id, via: "metadata_business_id" };
  }

  const email = extractEmail(data);
  if (email) {
    const user = await prisma.user.findUnique({
      where: { email },
      select: { id: true },
    });
    if (user) {
      // Mirrors getCurrentBusiness(): a user's primary business is their
      // earliest membership.
      const membership = await prisma.businessMember.findFirst({
        where: { userId: user.id },
        orderBy: { createdAt: "asc" },
        select: { businessId: true },
      });
      if (membership) return { businessId: membership.businessId, via: "email" };
    }
  }

  return { businessId: null, via: "unresolved", attemptedEmail: email };
}
