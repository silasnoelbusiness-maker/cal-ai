import { Calendar, Clock } from "lucide-react";
import type { AppointmentStatus } from "@prisma/client";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/ui/avatar";
import { formatDateTime } from "@/lib/utils";

const STATUS_VARIANT: Record<AppointmentStatus, React.ComponentProps<typeof Badge>["variant"]> = {
  PENDING: "warning",
  CONFIRMED: "success",
  COMPLETED: "secondary",
  CANCELLED: "danger",
};

export function AppointmentCard({
  leadName,
  service,
  scheduledAt,
  status,
  actions,
}: {
  leadName: string;
  service?: string | null;
  scheduledAt: Date | string;
  status: AppointmentStatus;
  actions?: React.ReactNode;
}) {
  return (
    <Card className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-center gap-3">
        <Avatar name={leadName} />
        <div>
          <p className="text-sm font-medium text-foreground">{leadName}</p>
          <p className="text-sm text-muted">{service || "Unknown"}</p>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-3 sm:justify-end">
        <div className="flex items-center gap-1.5 text-sm text-muted">
          <Calendar className="h-3.5 w-3.5" />
          <Clock className="h-3.5 w-3.5 -ml-1" />
          {formatDateTime(scheduledAt)}
        </div>
        <Badge variant={STATUS_VARIANT[status]}>{status.charAt(0) + status.slice(1).toLowerCase()}</Badge>
        {actions}
      </div>
    </Card>
  );
}
