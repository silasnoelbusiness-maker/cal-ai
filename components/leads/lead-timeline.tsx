import { Sparkles, UserPlus, ArrowRightLeft, CalendarCheck, MessageCircle, MessageCircleOff, Clock } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime } from "@/lib/utils";
import type { LeadEvent } from "@prisma/client";

const ICONS: Record<string, typeof Sparkles> = {
  LEAD_CREATED: UserPlus,
  AI_QUALIFIED: Sparkles,
  STATUS_CHANGED: ArrowRightLeft,
  APPOINTMENT_BOOKED: CalendarCheck,
  FOLLOW_UP_SENT: MessageCircle,
  FOLLOW_UP_FAILED: MessageCircleOff,
};

export function LeadTimeline({ events }: { events: LeadEvent[] }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2 space-y-0">
        <Clock className="h-4 w-4 text-muted" />
        <CardTitle>Timeline</CardTitle>
      </CardHeader>
      <CardContent>
        {events.length === 0 ? (
          <p className="py-4 text-sm text-muted">No activity yet.</p>
        ) : (
          <ol className="space-y-4">
            {events.map((event, i) => {
              const Icon = ICONS[event.type] || Clock;
              return (
                <li key={event.id} className="relative flex gap-3 pl-1">
                  {i < events.length - 1 && (
                    <span className="absolute left-[15px] top-7 h-[calc(100%-4px)] w-px bg-border" />
                  )}
                  <span className="z-10 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted-surface text-muted">
                    <Icon className="h-3.5 w-3.5" />
                  </span>
                  <div className="min-w-0 flex-1 pb-1">
                    <p className="text-sm text-foreground">{event.description}</p>
                    <p className="text-xs text-muted">{formatDateTime(event.createdAt)}</p>
                  </div>
                </li>
              );
            })}
          </ol>
        )}
      </CardContent>
    </Card>
  );
}
