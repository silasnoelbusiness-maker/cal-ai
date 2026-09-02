import Link from "next/link";
import { Check, Minus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { PLAN_LIMITS, PLAN_ORDER } from "@/lib/plans";
import { PLAN_LIMIT_BEHAVIOUR, START_FREE } from "@/lib/marketing/product-facts";
import { cn } from "@/lib/utils";

export function PricingSection({ compact = false }: { compact?: boolean }) {
  return (
    <section id="pricing" className={cn("scroll-mt-20", !compact && "border-t border-border bg-background py-20 sm:py-24")}>
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        {!compact && (
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-semibold tracking-tight text-foreground">
              Simple, transparent pricing
            </h2>
            <p className="mt-4 text-lg text-muted">
              Every plan includes every feature. The only thing that changes is how much you can
              run through it each month.
            </p>
          </div>
        )}

        {/* In compact mode the page supplies the h1 and this section starts at
            the plan cards' h3, which would skip a level. A named h2 keeps the
            outline intact for screen readers without adding visible chrome. */}
        {compact && <h2 className="sr-only">Plans</h2>}

        <div className={cn("mx-auto grid max-w-4xl gap-6 sm:grid-cols-3", !compact && "mt-14")}>
          {PLAN_ORDER.map((planId) => {
            const plan = PLAN_LIMITS[planId];
            const popular = planId === "GROWTH";
            return (
              <Card
                key={planId}
                className={cn(
                  "flex min-w-0 flex-col p-6",
                  popular && "border-brand shadow-md ring-1 ring-brand"
                )}
              >
                {popular && (
                  <Badge className="mb-3 w-fit" variant="default">
                    Most popular
                  </Badge>
                )}
                <h3 className="text-lg font-semibold text-foreground">{plan.label}</h3>
                <p className="mt-2 flex items-baseline gap-1">
                  <span className="text-3xl font-semibold tracking-tight text-foreground">
                    ${plan.priceMonthly}
                  </span>
                  <span className="text-sm text-muted">/month</span>
                </p>
                <ul className="mt-6 flex-1 space-y-2.5 text-sm">
                  {plan.features.map((feature) => (
                    <li key={feature} className="flex items-start gap-2 text-muted">
                      <Check className="mt-0.5 h-4 w-4 shrink-0 text-brand" aria-hidden />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>
                <Button className="mt-6" variant={popular ? "default" : "outline"} asChild>
                  <Link href={`/signup?plan=${planId.toLowerCase()}`}>
                    Start Free
                    <span className="sr-only"> with the {plan.label} plan</span>
                  </Link>
                </Button>
              </Card>
            );
          })}
        </div>

        <div className="mx-auto mt-8 max-w-4xl rounded-lg border border-border bg-muted-surface/40 px-5 py-4">
          <p className="text-sm font-medium text-foreground">
            What &ldquo;Start Free&rdquo; means: {START_FREE.headline}.
          </p>
          <p className="mt-1 text-sm text-muted">{START_FREE.detail}</p>
        </div>

        <PlanComparison />
      </div>
    </section>
  );
}

/**
 * The comparison table.
 *
 * Deliberately honest about how little differs: only leads, AI messages and
 * team seats are enforced per plan (lib/plans.ts — `LimitCheckResource` is
 * exactly "leads" | "aiMessages" | "users"). Channels, integrations, the API,
 * CSV import and analytics are identical on every plan, so they're listed as
 * included rather than dressed up as tier features. Inventing differentiation
 * here would mean a customer upgrading for something they already had.
 */
const COMPARISON_ROWS: { label: string; values: Record<string, string> }[] = [
  {
    label: "Leads per month",
    values: {
      STARTER: PLAN_LIMITS.STARTER.leadsPerMonth.toLocaleString(),
      GROWTH: PLAN_LIMITS.GROWTH.leadsPerMonth.toLocaleString(),
      PRO: PLAN_LIMITS.PRO.leadsPerMonth.toLocaleString(),
    },
  },
  {
    label: "AI messages per month",
    values: {
      STARTER: PLAN_LIMITS.STARTER.aiMessagesPerMonth.toLocaleString(),
      GROWTH: PLAN_LIMITS.GROWTH.aiMessagesPerMonth.toLocaleString(),
      PRO: PLAN_LIMITS.PRO.aiMessagesPerMonth.toLocaleString(),
    },
  },
  {
    label: "Team members",
    values: {
      STARTER: String(PLAN_LIMITS.STARTER.maxUsers),
      GROWTH: String(PLAN_LIMITS.GROWTH.maxUsers),
      PRO: String(PLAN_LIMITS.PRO.maxUsers),
    },
  },
];

const INCLUDED_EVERYWHERE = [
  "AI replies and lead qualification",
  "Automated follow-up sequences",
  "Embeddable website form",
  "CSV lead import",
  "Lead capture API and API keys",
  "Email and web conversations",
  "Two-way SMS (with your own Twilio account)",
  "Analytics dashboard",
  "Appointment tracking",
];

export function PlanComparison() {
  return (
    <div className="mx-auto mt-12 max-w-4xl">
      <h3 className="text-center text-lg font-semibold text-foreground">Compare plans</h3>

      <div className="mt-6 overflow-x-auto rounded-lg border border-border">
        <table className="w-full min-w-[34rem] border-collapse text-sm">
          <caption className="sr-only">
            Monthly allowances for the Starter, Growth and Pro plans
          </caption>
          <thead>
            <tr className="border-b border-border bg-muted-surface/50">
              <th scope="col" className="p-3 text-left font-medium text-muted">
                Monthly allowance
              </th>
              {PLAN_ORDER.map((planId) => (
                <th key={planId} scope="col" className="p-3 text-left font-semibold text-foreground">
                  {PLAN_LIMITS[planId].label}
                  <span className="block text-xs font-normal text-muted">
                    ${PLAN_LIMITS[planId].priceMonthly}/mo
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {COMPARISON_ROWS.map((row) => (
              <tr key={row.label} className="border-b border-border last:border-0">
                <th scope="row" className="p-3 text-left font-normal text-muted">
                  {row.label}
                </th>
                {PLAN_ORDER.map((planId) => (
                  <td key={planId} className="p-3 font-medium text-foreground">
                    {row.values[planId]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-6 rounded-lg border border-border p-5">
        <p className="text-sm font-semibold text-foreground">Included on every plan</p>
        <ul className="mt-3 grid gap-2 sm:grid-cols-2">
          {INCLUDED_EVERYWHERE.map((item) => (
            <li key={item} className="flex items-start gap-2 text-sm text-muted">
              <Check className="mt-0.5 h-4 w-4 shrink-0 text-brand" aria-hidden />
              {item}
            </li>
          ))}
        </ul>
        <p className="mt-4 flex items-start gap-2 border-t border-border pt-4 text-sm text-muted">
          <Minus className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          <span>
            Not available on any plan yet: outbound phone calls, and one-click Facebook or Google
            Ads connectors. Leads from ad platforms come in via the API or a CSV export.
          </span>
        </p>
      </div>

      <div className="mt-6 rounded-lg border border-border bg-muted-surface/40 p-5">
        <p className="text-sm font-semibold text-foreground">If you hit a limit</p>
        <ul className="mt-2 space-y-1.5 text-sm text-muted">
          <li>{PLAN_LIMIT_BEHAVIOUR.leads}</li>
          <li>{PLAN_LIMIT_BEHAVIOUR.aiMessages}</li>
        </ul>
      </div>
    </div>
  );
}
