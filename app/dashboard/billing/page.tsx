import type { Metadata } from "next";
import { Suspense } from "react";
import { Check } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { PLAN_LIMITS, PLAN_ORDER, currentMonthKey, effectivePlan } from "@/lib/plans";
import { isStripeConfigured } from "@/lib/auth/config";
import { hasBillableSubscription } from "@/lib/stripe/checkout";
import { PageHeader } from "@/components/dashboard/page-header";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ConfigNotice } from "@/components/ui/config-notice";
import { UsageBar } from "@/components/billing/usage-bar";
import { UpgradeButton } from "@/components/billing/upgrade-button";
import { ManageBillingButton } from "@/components/billing/manage-billing-button";
import { CheckoutStatusToast } from "@/components/billing/checkout-status-toast";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "Billing" };

export default async function BillingPage() {
  const { business } = await requireBusiness();

  const [subscription, usage, memberCount] = await Promise.all([
    prisma.subscription.upsert({
      where: { businessId: business.id },
      create: { businessId: business.id },
      update: {},
    }),
    prisma.usage.upsert({
      where: { businessId_month: { businessId: business.id, month: currentMonthKey() } },
      create: { businessId: business.id, month: currentMonthKey() },
      update: {},
    }),
    prisma.businessMember.count({ where: { businessId: business.id } }),
  ]);

  const limits = PLAN_LIMITS[subscription.plan];
  // What's actually enforced right now — differs from `limits` whenever the
  // subscription isn't active (e.g. canceled), so a lapsed Pro subscriber
  // doesn't keep seeing Pro-sized usage bars they no longer have access to.
  const enforcedLimits = PLAN_LIMITS[effectivePlan(subscription)];
  const hasActiveBilling = Boolean(subscription.stripeCustomerId);
  // Mirrors the server-side rule in changeSubscriptionPlan: only a live,
  // Stripe-billed subscription turns "Subscribe" into a plan *change*.
  const hasLiveBilling = hasBillableSubscription(subscription);

  return (
    <div>
      <Suspense fallback={null}>
        <CheckoutStatusToast />
      </Suspense>
      <PageHeader title="Billing" description="Your plan, usage, and payment details." />

      {!isStripeConfigured && (
        <ConfigNotice
          className="mb-6"
          title="Billing isn't configured"
          description="Set STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, and the STRIPE_PRICE_* variables to enable subscriptions."
        />
      )}

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader className="flex-row items-center justify-between space-y-0">
            <div>
              <CardTitle>Current plan</CardTitle>
              <CardDescription>
                {subscription.status === "ACTIVE" || subscription.status === "TRIALING"
                  ? `Renews ${formatDate(subscription.currentPeriodEnd)}`
                  : "No active subscription"}
              </CardDescription>
            </div>
            <Badge variant={subscription.status === "ACTIVE" ? "success" : "secondary"}>
              {limits.label} · {subscription.status.replace("_", " ").toLowerCase()}
            </Badge>
          </CardHeader>
          <CardContent className="space-y-5">
            {enforcedLimits.plan !== limits.plan && (
              <p className="text-xs text-warning">
                Your subscription isn&apos;t active, so {enforcedLimits.label} limits are currently enforced
                instead of {limits.label}.
              </p>
            )}
            <UsageBar label="Leads this month" used={usage.leadsCount} limit={enforcedLimits.leadsPerMonth} />
            <UsageBar
              label="AI messages this month"
              used={usage.aiMessagesCount}
              limit={enforcedLimits.aiMessagesPerMonth}
            />
            <UsageBar label="Team members" used={memberCount} limit={enforcedLimits.maxUsers} />
          </CardContent>
          {hasActiveBilling && (
            <div className="flex justify-end px-6 pb-6">
              <ManageBillingButton />
            </div>
          )}
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Need help?</CardTitle>
          </CardHeader>
          <CardContent className="text-sm text-muted">
            <p>
              Manage payment methods, view invoices, or cancel anytime from the billing portal once
              you&apos;re subscribed.
            </p>
          </CardContent>
        </Card>
      </div>

      <h2 className="mb-4 mt-8 text-lg font-semibold text-foreground">Plans</h2>
      <div className="grid gap-6 sm:grid-cols-3">
        {PLAN_ORDER.map((planId) => {
          const plan = PLAN_LIMITS[planId];
          const isCurrent = subscription.plan === planId && subscription.status === "ACTIVE";
          return (
            <Card key={planId} className={cn("flex flex-col p-6", isCurrent && "border-brand ring-1 ring-brand")}>
              <h3 className="text-lg font-semibold text-foreground">{plan.label}</h3>
              <p className="mt-2 flex items-baseline gap-1">
                <span className="text-2xl font-semibold text-foreground">${plan.priceMonthly}</span>
                <span className="text-sm text-muted">/month</span>
              </p>
              <ul className="mt-4 flex-1 space-y-2 text-sm">
                {plan.features.slice(0, 4).map((f) => (
                  <li key={f} className="flex items-start gap-2 text-muted">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
                    {f}
                  </li>
                ))}
              </ul>
              <div className="mt-5">
                {isCurrent ? (
                  <Badge variant="secondary" className="w-full justify-center py-2">
                    Current plan
                  </Badge>
                ) : (
                  <UpgradeButton
                    plan={planId}
                    variant={planId === "GROWTH" ? "default" : "outline"}
                    currentPlan={subscription.plan}
                    currentPeriodEnd={subscription.currentPeriodEnd}
                    isSubscribed={Boolean(subscription.stripeSubscriptionId) && hasLiveBilling}
                  >
                    {subscription.status === "ACTIVE" ? "Switch plan" : "Subscribe"}
                  </UpgradeButton>
                )}
              </div>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
