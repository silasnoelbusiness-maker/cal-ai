"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button, type ButtonProps } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { PLAN_LIMITS, PLAN_ORDER } from "@/lib/plans";
import { formatDate } from "@/lib/utils";
import type { Plan } from "@prisma/client";

/**
 * Starts a subscription or changes an existing one.
 *
 * When the business already has a subscription, a plan change is a real
 * billing event — an upgrade is charged immediately and a downgrade takes
 * effect later — so it is never a one-click action. The confirmation dialog
 * spells out which of the two will happen and what it costs, so switching
 * can't be mistaken for a free instant toggle.
 */
export function UpgradeButton({
  plan,
  children,
  variant,
  currentPlan,
  currentPeriodEnd,
  isSubscribed = false,
}: {
  plan: Plan;
  children: React.ReactNode;
  variant?: ButtonProps["variant"];
  /** Current plan, when the business already has a live subscription. */
  currentPlan?: Plan;
  /** End of the paid period — when a downgrade would take effect. */
  currentPeriodEnd?: Date | string | null;
  isSubscribed?: boolean;
}) {
  const [pending, startTransition] = useTransition();
  const [open, setOpen] = useState(false);
  const router = useRouter();

  const isUpgrade =
    isSubscribed && currentPlan ? PLAN_ORDER.indexOf(plan) > PLAN_ORDER.indexOf(currentPlan) : false;
  const isDowngrade =
    isSubscribed && currentPlan ? PLAN_ORDER.indexOf(plan) < PLAN_ORDER.indexOf(currentPlan) : false;

  const target = PLAN_LIMITS[plan];
  const from = currentPlan ? PLAN_LIMITS[currentPlan] : null;

  function submit() {
    startTransition(async () => {
      try {
        const res = await fetch("/api/stripe/checkout", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ plan }),
        });
        const data = await res.json();

        if (!res.ok) {
          // Surface Stripe's reason (e.g. a declined card on an upgrade) —
          // the plan is unchanged in that case.
          toast.error(data.error || "Couldn't change your plan.");
          return;
        }

        // New subscription: hand off to Stripe Checkout.
        if (data.url) {
          window.location.href = data.url;
          return;
        }

        setOpen(false);
        if (data.changed) toast.success(data.message);
        else toast.info(data.message || "Nothing to change.");
        router.refresh();
      } catch {
        toast.error("Billing is temporarily unavailable.");
      }
    });
  }

  // No existing subscription — go straight to Stripe Checkout, which is
  // itself the confirmation step.
  if (!isSubscribed) {
    return (
      <Button variant={variant} loading={pending} onClick={submit} className="w-full">
        {children}
      </Button>
    );
  }

  return (
    <>
      <Button variant={variant} onClick={() => setOpen(true)} className="w-full">
        {children}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {isUpgrade ? `Upgrade to ${target.label}?` : `Switch to ${target.label}?`}
            </DialogTitle>
            <DialogDescription>
              {isUpgrade ? (
                <>
                  You&apos;ll be charged a prorated amount today for the rest of your current billing
                  period, then ${target.priceMonthly}/month from your next renewal.{" "}
                  {from && `Your ${from.label} plan ends as soon as the payment goes through.`} If the
                  payment doesn&apos;t succeed, you stay on {from?.label ?? "your current plan"}.
                </>
              ) : isDowngrade ? (
                <>
                  You&apos;ll keep {from?.label ?? "your current"} access until{" "}
                  <strong>{currentPeriodEnd ? formatDate(currentPeriodEnd) : "the end of this billing period"}</strong>
                  , then move to {target.label} at ${target.priceMonthly}/month. You won&apos;t be
                  charged today, and this period isn&apos;t refunded.
                </>
              ) : (
                <>You&apos;re already on the {target.label} plan.</>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={pending}>
              Cancel
            </Button>
            <Button type="button" onClick={submit} loading={pending}>
              {isUpgrade ? "Confirm and pay" : "Schedule change"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
