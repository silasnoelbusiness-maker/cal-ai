import type { Plan } from "@prisma/client";

/**
 * Centralized plan-limit configuration. This is the single source of truth
 * for what each subscription tier is allowed to do — never duplicate these
 * numbers elsewhere.
 */
export interface PlanLimits {
  plan: Plan;
  label: string;
  priceMonthly: number;
  leadsPerMonth: number;
  aiMessagesPerMonth: number;
  maxUsers: number;
  features: string[];
}

export const PLAN_LIMITS: Record<Plan, PlanLimits> = {
  STARTER: {
    plan: "STARTER",
    label: "Starter",
    priceMonthly: 49,
    leadsPerMonth: 100,
    aiMessagesPerMonth: 500,
    maxUsers: 1,
    features: [
      "Up to 100 leads / month",
      "500 AI messages / month",
      "1 team member",
      "AI lead qualification",
      "Automated follow-up",
      "Embeddable lead form",
      "Email notifications",
    ],
  },
  GROWTH: {
    plan: "GROWTH",
    label: "Growth",
    priceMonthly: 99,
    leadsPerMonth: 500,
    aiMessagesPerMonth: 2500,
    maxUsers: 3,
    features: [
      "Up to 500 leads / month",
      "2,500 AI messages / month",
      "3 team members",
      "Everything in Starter",
      "SMS follow-up",
      "Analytics dashboard",
      "Priority support",
    ],
  },
  PRO: {
    plan: "PRO",
    label: "Pro",
    priceMonthly: 199,
    leadsPerMonth: 2000,
    aiMessagesPerMonth: 10000,
    maxUsers: 10,
    features: [
      "Up to 2,000 leads / month",
      "10,000 AI messages / month",
      "10 team members",
      "Everything in Growth",
      "API access & webhooks",
      "Multiple lead sources",
      "Dedicated support",
    ],
  },
};

export const PLAN_ORDER: Plan[] = ["STARTER", "GROWTH", "PRO"];

export function currentMonthKey(date: Date = new Date()): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export interface UsageLike {
  leadsCount: number;
  aiMessagesCount: number;
}

export type LimitCheckResource = "leads" | "aiMessages" | "users";

export interface LimitCheckResult {
  allowed: boolean;
  limit: number;
  used: number;
  remaining: number;
  message?: string;
}

/**
 * Determine whether a business on `plan` may consume one more unit of
 * `resource`, given its current usage this billing period.
 */
export function checkPlanLimit(
  plan: Plan,
  resource: LimitCheckResource,
  usage: UsageLike,
  currentUserCount = 0
): LimitCheckResult {
  const limits = PLAN_LIMITS[plan];

  if (resource === "leads") {
    const used = usage.leadsCount;
    const allowed = used < limits.leadsPerMonth;
    return {
      allowed,
      limit: limits.leadsPerMonth,
      used,
      remaining: Math.max(limits.leadsPerMonth - used, 0),
      message: allowed
        ? undefined
        : `You've reached your ${limits.label} plan limit of ${limits.leadsPerMonth} leads this month. Upgrade your plan to capture more leads.`,
    };
  }

  if (resource === "aiMessages") {
    const used = usage.aiMessagesCount;
    const allowed = used < limits.aiMessagesPerMonth;
    return {
      allowed,
      limit: limits.aiMessagesPerMonth,
      used,
      remaining: Math.max(limits.aiMessagesPerMonth - used, 0),
      message: allowed
        ? undefined
        : `You've reached your ${limits.label} plan limit of ${limits.aiMessagesPerMonth} AI messages this month. Upgrade your plan or reply manually to continue.`,
    };
  }

  // users
  const allowed = currentUserCount < limits.maxUsers;
  return {
    allowed,
    limit: limits.maxUsers,
    used: currentUserCount,
    remaining: Math.max(limits.maxUsers - currentUserCount, 0),
    message: allowed
      ? undefined
      : `Your ${limits.label} plan allows up to ${limits.maxUsers} team member${limits.maxUsers === 1 ? "" : "s"}. Upgrade to invite more.`,
  };
}

export function planFromPriceId(priceId: string | null | undefined): Plan | null {
  if (!priceId) return null;
  if (priceId === process.env.STRIPE_PRICE_STARTER) return "STARTER";
  if (priceId === process.env.STRIPE_PRICE_GROWTH) return "GROWTH";
  if (priceId === process.env.STRIPE_PRICE_PRO) return "PRO";
  return null;
}
