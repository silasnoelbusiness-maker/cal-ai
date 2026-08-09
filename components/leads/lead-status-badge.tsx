import type { LeadStatus } from "@prisma/client";
import { Badge } from "@/components/ui/badge";

const STATUS_CONFIG: Record<LeadStatus, { label: string; variant: React.ComponentProps<typeof Badge>["variant"] }> = {
  NEW: { label: "New", variant: "cold" },
  CONTACTED: { label: "Contacted", variant: "secondary" },
  QUALIFIED: { label: "Qualified", variant: "success" },
  APPOINTMENT: { label: "Appointment", variant: "default" },
  CONVERTED: { label: "Converted", variant: "success" },
  LOST: { label: "Lost", variant: "danger" },
  CLOSED: { label: "Closed", variant: "outline" },
};

export function LeadStatusBadge({ status }: { status: LeadStatus }) {
  const config = STATUS_CONFIG[status];
  return <Badge variant={config.variant}>{config.label}</Badge>;
}
