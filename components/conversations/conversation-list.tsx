import Link from "next/link";
import { Sparkles } from "lucide-react";
import { Avatar } from "@/components/ui/avatar";
import { TemperatureBadge } from "@/components/leads/temperature-badge";
import { cn, formatRelativeTime } from "@/lib/utils";
import type { Conversation, ConversationChannel, Lead, Message } from "@prisma/client";

export interface ConversationListItem extends Conversation {
  lead: Lead;
  messages: Message[];
}

const CHANNEL_LABELS: Record<ConversationChannel, string> = {
  WEB: "Web",
  SMS: "SMS",
  EMAIL: "Email",
  PHONE: "Phone",
};

export function ConversationList({
  conversations,
  selectedId,
}: {
  conversations: ConversationListItem[];
  selectedId?: string;
}) {
  return (
    <div className="divide-y divide-border overflow-y-auto scrollbar-thin">
      {conversations.map((convo) => {
        const lastMessage = convo.messages[0];
        const name = `${convo.lead.firstName} ${convo.lead.lastName || ""}`.trim();
        const active = convo.id === selectedId;

        return (
          <Link
            key={convo.id}
            href={`/dashboard/conversations?id=${convo.id}`}
            className={cn(
              "flex gap-3 px-4 py-3.5 transition-colors hover:bg-muted-surface",
              active && "bg-brand/5"
            )}
          >
            <Avatar name={name} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center justify-between gap-2">
                <p className="truncate text-sm font-medium text-foreground">{name}</p>
                <span className="shrink-0 text-[11px] text-muted">
                  {lastMessage ? formatRelativeTime(lastMessage.createdAt) : ""}
                </span>
              </div>
              <p className="mt-0.5 flex items-center gap-1 truncate text-xs text-muted">
                {lastMessage?.aiGenerated && <Sparkles className="h-3 w-3 shrink-0 text-brand" />}
                {lastMessage ? lastMessage.content : "No messages yet"}
              </p>
              <div className="mt-1.5 flex items-center gap-1.5">
                <TemperatureBadge temperature={convo.lead.temperature} />
                <span className="rounded-full border border-border px-1.5 py-0.5 text-[10px] font-medium text-muted">
                  {CHANNEL_LABELS[convo.channel]}
                </span>
                {convo.needsHuman && (
                  <span className="rounded-full bg-danger-surface px-1.5 py-0.5 text-[10px] font-medium text-danger">
                    Needs human
                  </span>
                )}
              </div>
            </div>
          </Link>
        );
      })}
    </div>
  );
}
