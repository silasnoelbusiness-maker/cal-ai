import Link from "next/link";
import { ChevronLeft, ExternalLink } from "lucide-react";
import { Avatar } from "@/components/ui/avatar";
import { TemperatureBadge } from "@/components/leads/temperature-badge";
import { LeadStatusBadge } from "@/components/leads/lead-status-badge";
import { Badge } from "@/components/ui/badge";
import type { Conversation, ConversationChannel, Lead } from "@prisma/client";

const CHANNEL_LABELS: Record<ConversationChannel, string> = {
  WEB: "Web chat",
  SMS: "SMS",
  EMAIL: "Email",
  PHONE: "Phone",
};

export function ConversationDetailHeader({
  conversation,
  lead,
}: {
  conversation: Conversation;
  lead: Lead;
}) {
  const name = `${lead.firstName} ${lead.lastName || ""}`.trim();

  return (
    <div className="flex items-center justify-between gap-3 border-b border-border p-4">
      <div className="flex min-w-0 items-center gap-3">
        <Link href="/dashboard/conversations" className="text-muted hover:text-foreground md:hidden">
          <ChevronLeft className="h-5 w-5" />
        </Link>
        <Avatar name={name} />
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-foreground">{name}</p>
          <div className="mt-0.5 flex flex-wrap items-center gap-1.5">
            <TemperatureBadge temperature={lead.temperature} />
            <LeadStatusBadge status={lead.status} />
            <Badge variant="outline">{CHANNEL_LABELS[conversation.channel]}</Badge>
          </div>
        </div>
      </div>
      <Link
        href={`/dashboard/leads/${lead.id}`}
        className="flex shrink-0 items-center gap-1 text-xs font-medium text-brand hover:underline"
      >
        View lead
        <ExternalLink className="h-3 w-3" />
      </Link>
    </div>
  );
}
