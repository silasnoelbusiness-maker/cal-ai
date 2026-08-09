"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, X, CheckCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { updateAppointmentStatusAction } from "@/app/dashboard/appointments/actions";
import type { AppointmentStatus } from "@prisma/client";

export function AppointmentActions({ appointmentId, status }: { appointmentId: string; status: AppointmentStatus }) {
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  function update(next: AppointmentStatus, label: string) {
    startTransition(async () => {
      await updateAppointmentStatusAction(appointmentId, next);
      toast.success(label);
      router.refresh();
    });
  }

  if (status === "COMPLETED" || status === "CANCELLED") return null;

  return (
    <div className="flex items-center gap-1.5">
      {status === "PENDING" && (
        <Button size="sm" variant="outline" disabled={pending} onClick={() => update("CONFIRMED", "Appointment confirmed")}>
          <Check className="h-3.5 w-3.5" />
          Confirm
        </Button>
      )}
      {status === "CONFIRMED" && (
        <Button size="sm" variant="outline" disabled={pending} onClick={() => update("COMPLETED", "Marked as completed")}>
          <CheckCheck className="h-3.5 w-3.5" />
          Complete
        </Button>
      )}
      <Button
        size="sm"
        variant="outline"
        className="text-danger hover:bg-danger-surface"
        disabled={pending}
        onClick={() => update("CANCELLED", "Appointment cancelled")}
      >
        <X className="h-3.5 w-3.5" />
        Cancel
      </Button>
    </div>
  );
}
