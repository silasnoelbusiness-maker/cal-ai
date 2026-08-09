import Link from "next/link";
import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { PLAN_LIMITS, PLAN_ORDER } from "@/lib/plans";
import { cn } from "@/lib/utils";

export function PricingSection({ compact = false }: { compact?: boolean }) {
  return (
    <section className={cn(!compact && "border-t border-border bg-surface py-20 sm:py-24")}>
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        {!compact && (
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-semibold tracking-tight text-foreground">
              Simple, transparent pricing
            </h2>
            <p className="mt-4 text-lg text-muted">
              Every plan includes AI lead qualification and automated follow-up. Billed monthly,
              cancel anytime.
            </p>
          </div>
        )}

        <div className={cn("mx-auto grid max-w-4xl gap-6 sm:grid-cols-3", !compact && "mt-14")}>
          {PLAN_ORDER.map((planId) => {
            const plan = PLAN_LIMITS[planId];
            const popular = planId === "GROWTH";
            return (
              <Card
                key={planId}
                className={cn(
                  "flex flex-col p-6",
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
                      <Check className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>
                <Button className="mt-6" variant={popular ? "default" : "outline"} asChild>
                  <Link href={`/signup?plan=${planId.toLowerCase()}`}>Start Free</Link>
                </Button>
              </Card>
            );
          })}
        </div>
      </div>
    </section>
  );
}
