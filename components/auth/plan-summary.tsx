import Link from "next/link";
import { Check, CreditCard } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { PLAN_LIMITS, PLAN_ORDER } from "@/lib/plans";
import { START_FREE } from "@/lib/marketing/product-facts";
import { cn } from "@/lib/utils";
import type { Plan } from "@prisma/client";

/**
 * Turns `?plan=growth` into a visible, changeable summary.
 *
 * Someone who picked a plan on the pricing page needs to see that choice
 * carried over — landing on a bare form makes it feel like the click was
 * lost. Switching plans is a link back to the same page with a different
 * query, so it works without JavaScript and keeps a real URL for each
 * choice.
 */

/** Narrows an untrusted `?plan=` value to a real plan, or null. */
export function parsePlanParam(value: string | string[] | undefined): Plan | null {
  if (typeof value !== "string") return null;
  const upper = value.toUpperCase();
  return PLAN_ORDER.find((p) => p === upper) ?? null;
}

export function PlanSummary({ plan }: { plan: Plan }) {
  const limits = PLAN_LIMITS[plan];

  return (
    <div className="rounded-lg border border-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-medium uppercase tracking-wide text-muted">Selected plan</p>
          <p className="mt-0.5 text-lg font-semibold text-foreground">{limits.label}</p>
        </div>
        <p className="shrink-0 text-right">
          <span className="text-lg font-semibold text-foreground">${limits.priceMonthly}</span>
          <span className="block text-xs text-muted">per month</span>
        </p>
      </div>

      <ul className="mt-3 space-y-1.5 border-t border-border pt-3 text-sm text-muted">
        <li className="flex items-start gap-2">
          <Check className="mt-0.5 h-4 w-4 shrink-0 text-brand" aria-hidden />
          Up to {limits.leadsPerMonth.toLocaleString()} leads a month
        </li>
        <li className="flex items-start gap-2">
          <Check className="mt-0.5 h-4 w-4 shrink-0 text-brand" aria-hidden />
          {limits.aiMessagesPerMonth.toLocaleString()} AI messages a month
        </li>
        <li className="flex items-start gap-2">
          <CreditCard className="mt-0.5 h-4 w-4 shrink-0 text-brand" aria-hidden />
          No card needed to create your account
        </li>
      </ul>

      <p className="mt-3 border-t border-border pt-3 text-xs text-muted">
        {START_FREE.detail}
      </p>

      <div className="mt-3">
        <p className="text-xs font-medium text-muted">Change plan</p>
        <div className="mt-1.5 flex flex-wrap gap-1.5">
          {PLAN_ORDER.map((option) => {
            const selected = option === plan;
            return (
              <Link
                key={option}
                href={`/signup?plan=${option.toLowerCase()}`}
                aria-current={selected ? "true" : undefined}
                className={cn(
                  "rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2",
                  selected
                    ? "border-brand bg-brand text-brand-foreground"
                    : "border-border text-muted hover:bg-muted-surface hover:text-foreground"
                )}
              >
                {PLAN_LIMITS[option].label}
              </Link>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/** Compact banner used when no plan was pre-selected. */
export function NoPlanSelectedNote() {
  return (
    <div className="rounded-lg border border-border bg-surface p-4">
      <p className="text-sm font-medium text-foreground">{START_FREE.headline}</p>
      <p className="mt-1 text-sm text-muted">{START_FREE.detail}</p>
      <Badge variant="secondary" className="mt-3">
        Pick a plan later from your billing page
      </Badge>
    </div>
  );
}
