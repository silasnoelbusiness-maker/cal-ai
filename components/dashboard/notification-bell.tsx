"use client";

import { useTransition } from "react";
import Link from "next/link";
import { Bell, Flame, Calendar, UserPlus, ShieldAlert, CheckCircle2, CreditCard, MessageSquare } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { formatRelativeTime } from "@/lib/utils";
import { markAllNotificationsReadAction } from "@/app/dashboard/notifications-actions";
import type { NotificationType } from "@prisma/client";

export interface NotificationItem {
  id: string;
  type: NotificationType;
  title: string;
  body: string;
  read: boolean;
  leadId: string | null;
  createdAt: Date;
}

const ICONS: Record<NotificationType, typeof Bell> = {
  NEW_LEAD: UserPlus,
  HOT_LEAD: Flame,
  QUALIFIED_LEAD: CheckCircle2,
  APPOINTMENT_BOOKED: Calendar,
  NEEDS_HUMAN: ShieldAlert,
  PAYMENT_FAILED: CreditCard,
  NEW_MESSAGE: MessageSquare,
};

export function NotificationBell({ notifications }: { notifications: NotificationItem[] }) {
  const [pending, startTransition] = useTransition();
  const unread = notifications.filter((n) => !n.read).length;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          className="relative inline-flex h-9 w-9 items-center justify-center rounded-md text-muted hover:bg-muted-surface hover:text-foreground"
          aria-label={`Notifications${unread > 0 ? ` (${unread} unread)` : ""}`}
        >
          <Bell className="h-4.5 w-4.5" />
          {unread > 0 && (
            <span className="absolute right-1.5 top-1.5 flex h-2 w-2 rounded-full bg-danger" />
          )}
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-80">
        <div className="flex items-center justify-between px-2 py-1">
          <DropdownMenuLabel className="px-0 py-0">Notifications</DropdownMenuLabel>
          {unread > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-6 px-2 text-xs"
              disabled={pending}
              onClick={() => startTransition(() => markAllNotificationsReadAction())}
            >
              Mark all read
            </Button>
          )}
        </div>
        <DropdownMenuSeparator />
        {notifications.length === 0 ? (
          <p className="px-2 py-6 text-center text-sm text-muted">You&apos;re all caught up.</p>
        ) : (
          <div className="max-h-96 overflow-y-auto scrollbar-thin">
            {notifications.map((n) => {
              const Icon = ICONS[n.type] || Bell;
              const content = (
                <div className="flex gap-2.5">
                  <span
                    className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full ${
                      n.read ? "bg-muted-surface text-muted" : "bg-brand/10 text-brand"
                    }`}
                  >
                    <Icon className="h-3.5 w-3.5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-foreground">{n.title}</p>
                    <p className="line-clamp-2 text-xs text-muted">{n.body}</p>
                    <p className="mt-0.5 text-[11px] text-muted">{formatRelativeTime(n.createdAt)}</p>
                  </div>
                </div>
              );
              return (
                <DropdownMenuItem key={n.id} className="items-start py-2" asChild>
                  {n.leadId ? (
                    <Link href={`/dashboard/leads/${n.leadId}`}>{content}</Link>
                  ) : (
                    <div>{content}</div>
                  )}
                </DropdownMenuItem>
              );
            })}
          </div>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
