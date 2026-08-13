"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { CalendarClock } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { PLAN_LIMITS } from "@/lib/plans";
import { formatDate } from "@/lib/utils";
import type { Plan } from "@prisma/client";

/**
 * Persistent reminder of a plan change Stripe has already scheduled.
 *
 * The confirmation dialog shown when the downgrade was requested is gone by
 * the next page load, so without this a customer has no way to see — or undo
 * — a downgrade they scheduled days ago. The plan and date come from Stripe
 * via the server component; this component renders them and offers the undo.
 */
export function PendingPlanChangeNotice({
  fromPlan,
  toPlan,
  effectiveAt,
}: {
  fromPlan: Plan;
  toPlan: Plan;
  effectiveAt: Date | string;
}) {
  const [open, setOpen] = useState(false);
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  const from = PLAN_LIMITS[fromPlan];
  const to = PLAN_LIMITS[toPlan];
  const when = formatDate(effectiveAt);

  function keepCurrentPlan() {
    startTransition(async () => {
      try {
        const res = await fetch("/api/stripe/plan-change", { method: "DELETE" });
        const data = await res.json();

        if (!res.ok) {
          toast.error(data.error || "Couldn't cancel the scheduled change.");
          return;
        }

        setOpen(false);
        toast.success(data.message);
        router.refresh();
      } catch {
        toast.error("Billing is temporarily unavailable.");
      }
    });
  }

  return (
    <>
      <div
        className="mb-6 flex flex-col gap-3 rounded-lg border border-warning/30 bg-warning-surface px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between"
        role="status"
      >
        <div className="flex items-start gap-3">
          <CalendarClock className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
          <div className="min-w-0">
            <p className="font-medium text-foreground">
              Your plan will change from {from.label} to {to.label} on {when}.
            </p>
            <p className="mt-0.5 text-muted">
              You keep your {from.label} plan and its limits until then. Nothing is charged today.
            </p>
          </div>
        </div>
        <Button variant="outline" size="sm" className="shrink-0" onClick={() => setOpen(true)}>
          Keep current plan
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Stay on {from.label}?</DialogTitle>
            <DialogDescription>
              This cancels the scheduled change to {to.label} on {when}. You&apos;ll stay on{" "}
              {from.label} at ${from.priceMonthly}/month and keep renewing as normal. Nothing is
              charged now, and you can schedule the change again at any time.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={pending}>
              Keep the change
            </Button>
            <Button type="button" onClick={keepCurrentPlan} loading={pending}>
              Stay on {from.label}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
