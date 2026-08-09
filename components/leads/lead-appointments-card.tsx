import { Calendar } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ScheduleAppointmentDialog } from "@/components/appointments/schedule-appointment-dialog";
import { formatDateTime } from "@/lib/utils";
import type { Appointment, AppointmentStatus } from "@prisma/client";

const STATUS_VARIANT: Record<AppointmentStatus, React.ComponentProps<typeof Badge>["variant"]> = {
  PENDING: "warning",
  CONFIRMED: "success",
  COMPLETED: "secondary",
  CANCELLED: "danger",
};

export function LeadAppointmentsCard({ leadId, appointments }: { leadId: string; appointments: Appointment[] }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <CardTitle>Appointments</CardTitle>
        <ScheduleAppointmentDialog leadId={leadId} />
      </CardHeader>
      <CardContent className="space-y-2">
        {appointments.length === 0 ? (
          <p className="py-4 text-sm text-muted">No appointments scheduled yet.</p>
        ) : (
          appointments.map((appt) => (
            <div
              key={appt.id}
              className="flex items-center justify-between gap-3 rounded-md border border-border px-3 py-2.5"
            >
              <div className="flex items-center gap-2.5">
                <Calendar className="h-4 w-4 text-muted" />
                <span className="text-sm text-foreground">{formatDateTime(appt.scheduledAt)}</span>
              </div>
              <Badge variant={STATUS_VARIANT[appt.status]}>
                {appt.status.charAt(0) + appt.status.slice(1).toLowerCase()}
              </Badge>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}
