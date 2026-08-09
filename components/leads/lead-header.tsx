import Link from "next/link";
import { ChevronLeft } from "lucide-react";
import { TemperatureBadge } from "@/components/leads/temperature-badge";
import { LeadStatusControl } from "@/components/leads/lead-status-control";
import { QualifyButton } from "@/components/leads/qualify-button";
import { DeleteLeadButton } from "@/components/leads/delete-lead-button";
import { Badge } from "@/components/ui/badge";
import type { Lead } from "@prisma/client";

export function LeadHeader({ lead }: { lead: Lead }) {
  const name = `${lead.firstName} ${lead.lastName || ""}`.trim();

  return (
    <div className="mb-6">
      <Link
        href="/dashboard/leads"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-foreground"
      >
        <ChevronLeft className="h-4 w-4" />
        Back to leads
      </Link>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <h1 className="text-xl font-semibold text-foreground sm:text-2xl">{name}</h1>
          <TemperatureBadge temperature={lead.temperature} />
          {lead.needsHuman && <Badge variant="danger">Needs human</Badge>}
          {lead.isDemo && <Badge variant="secondary">Demo</Badge>}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <LeadStatusControl leadId={lead.id} status={lead.status} />
          <QualifyButton leadId={lead.id} />
          <DeleteLeadButton leadId={lead.id} leadName={name} />
        </div>
      </div>
    </div>
  );
}
