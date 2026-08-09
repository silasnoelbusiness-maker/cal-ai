import Link from "next/link";
import { ArrowUpDown } from "lucide-react";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Avatar } from "@/components/ui/avatar";
import { LeadStatusBadge } from "@/components/leads/lead-status-badge";
import { TemperatureBadge } from "@/components/leads/temperature-badge";
import { LeadRowActions } from "@/components/leads/lead-row-actions";
import { formatDate, unknownOr } from "@/lib/utils";
import type { Lead } from "@prisma/client";

const SOURCE_LABELS: Record<string, string> = {
  website: "Website",
  embed: "Embedded form",
  api: "API",
  manual: "Manual",
  google_ads: "Google Ads",
  facebook_ads: "Facebook Ads",
  referral: "Referral",
  phone: "Phone",
  other: "Other",
};

export function LeadsTable({
  leads,
  currentSort,
  currentDir,
  buildSortHref,
}: {
  leads: Lead[];
  currentSort: string;
  currentDir: string;
  buildSortHref: (sort: string) => string;
}) {
  function renderSortHeader(sort: string, children: React.ReactNode) {
    const active = currentSort === sort;
    return (
      <Link href={buildSortHref(sort)} className="inline-flex items-center gap-1 hover:text-foreground">
        {children}
        <ArrowUpDown className={`h-3 w-3 ${active ? "text-brand" : "text-muted"}`} />
        {active && <span className="sr-only">({currentDir === "asc" ? "ascending" : "descending"})</span>}
      </Link>
    );
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Name</TableHead>
          <TableHead>Service</TableHead>
          <TableHead>Source</TableHead>
          <TableHead>Temperature</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>{renderSortHeader("createdAt", "Created")}</TableHead>
          <TableHead>{renderSortHeader("lastContactedAt", "Last contact")}</TableHead>
          <TableHead className="text-right">Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {leads.map((lead) => {
          const name = `${lead.firstName} ${lead.lastName || ""}`.trim();
          return (
            <TableRow key={lead.id} className="cursor-pointer">
              <TableCell>
                <Link href={`/dashboard/leads/${lead.id}`} className="flex items-center gap-2.5">
                  <Avatar name={name} className="h-7 w-7 text-[11px]" />
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-foreground">{name}</p>
                    <p className="truncate text-xs text-muted">{lead.email || lead.phone || "No contact info"}</p>
                  </div>
                </Link>
              </TableCell>
              <TableCell className="text-sm text-muted">{unknownOr(lead.serviceRequested)}</TableCell>
              <TableCell className="text-sm text-muted">{SOURCE_LABELS[lead.source] || lead.source}</TableCell>
              <TableCell>
                <TemperatureBadge temperature={lead.temperature} />
              </TableCell>
              <TableCell>
                <LeadStatusBadge status={lead.status} />
              </TableCell>
              <TableCell className="whitespace-nowrap text-sm text-muted">{formatDate(lead.createdAt)}</TableCell>
              <TableCell className="whitespace-nowrap text-sm text-muted">
                {lead.lastContactedAt ? formatDate(lead.lastContactedAt) : "Never"}
              </TableCell>
              <TableCell className="text-right">
                <LeadRowActions leadId={lead.id} leadName={name} />
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
