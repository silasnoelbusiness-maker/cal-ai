import Link from "next/link";
import type { Metadata } from "next";
import { Users, CheckCircle2, Calendar, DollarSign, Sparkles, ArrowRight, Plus } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import {
  getDashboardMetrics,
  getPipelineSnapshot,
  getRecentLeads,
  getRecentConversations,
  getUpcomingAppointments,
  getRecentAiActivity,
} from "@/lib/dashboard/data";
import { MetricCard } from "@/components/ui/metric-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/empty-state";
import { Avatar } from "@/components/ui/avatar";
import { LeadStatusBadge } from "@/components/leads/lead-status-badge";
import { TemperatureBadge } from "@/components/leads/temperature-badge";
import { AddTestLeadButton } from "@/components/dashboard/add-test-lead-button";
import { formatCurrency, formatRelativeTime, formatDateTime } from "@/lib/utils";
import type { LeadStatus } from "@prisma/client";

export const metadata: Metadata = { title: "Dashboard" };

const PIPELINE_STAGES: { status: LeadStatus; label: string }[] = [
  { status: "NEW", label: "New" },
  { status: "CONTACTED", label: "Contacted" },
  { status: "QUALIFIED", label: "Qualified" },
  { status: "APPOINTMENT", label: "Appointment" },
  { status: "CONVERTED", label: "Converted" },
];

export default async function DashboardPage() {
  const { business } = await requireBusiness();

  const [metrics, pipeline, recentLeads, recentConversations, upcomingAppointments, aiActivity] =
    await Promise.all([
      getDashboardMetrics(business.id),
      getPipelineSnapshot(business.id),
      getRecentLeads(business.id),
      getRecentConversations(business.id),
      getUpcomingAppointments(business.id),
      getRecentAiActivity(business.id),
    ]);

  const totalLeadsEver = Object.values(pipeline).reduce((a, b) => a + b, 0);

  if (totalLeadsEver === 0) {
    return (
      <div className="mx-auto max-w-2xl py-10">
        <EmptyState
          icon={Users}
          title="No leads yet"
          description="Connect your website form or API, or add a test lead to see how LeadLoop captures, qualifies, and follows up automatically."
          action={<AddTestLeadButton />}
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <MetricCard
          label="Recovered revenue"
          value={formatCurrency(metrics.revenue.value)}
          change={metrics.revenue.change}
          icon={DollarSign}
          emphasize
        />
        <MetricCard label="Leads" value={String(metrics.leads.value)} change={metrics.leads.change} icon={Users} />
        <MetricCard
          label="Qualified"
          value={String(metrics.qualified.value)}
          change={metrics.qualified.change}
          icon={CheckCircle2}
        />
        <MetricCard
          label="Appointments"
          value={String(metrics.appointments.value)}
          change={metrics.appointments.change}
          icon={Calendar}
        />
      </div>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <CardTitle>Lead pipeline</CardTitle>
          <Link href="/dashboard/leads" className="text-sm font-medium text-brand hover:underline">
            View all
          </Link>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
            {PIPELINE_STAGES.map((stage) => (
              <Link
                key={stage.status}
                href={`/dashboard/leads?status=${stage.status}`}
                className="rounded-lg border border-border p-3 transition-colors hover:bg-muted-surface"
              >
                <p className="text-xs font-medium text-muted">{stage.label}</p>
                <p className="mt-1 text-xl font-semibold text-foreground">{pipeline[stage.status] || 0}</p>
              </Link>
            ))}
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="min-w-0">
          <CardHeader className="flex-row items-center justify-between space-y-0">
            <CardTitle>Recent leads</CardTitle>
            <Link href="/dashboard/leads" className="text-sm font-medium text-brand hover:underline">
              View all
            </Link>
          </CardHeader>
          <CardContent className="space-y-1">
            {recentLeads.map((lead) => (
              <Link
                key={lead.id}
                href={`/dashboard/leads/${lead.id}`}
                className="flex items-center gap-3 rounded-md px-2 py-2.5 -mx-2 transition-colors hover:bg-muted-surface"
              >
                <Avatar name={`${lead.firstName} ${lead.lastName || ""}`} />
                <div className="min-w-0 flex-1">
                  <p className="flex items-center gap-1.5 truncate text-sm font-medium text-foreground">
                    {lead.firstName} {lead.lastName}
                    {lead.isDemo && (
                      <Badge variant="secondary" className="shrink-0">
                        Demo
                      </Badge>
                    )}
                  </p>
                  <p className="truncate text-xs text-muted">{lead.serviceRequested || "Unknown service"}</p>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1">
                  <TemperatureBadge temperature={lead.temperature} />
                  <span className="text-[11px] text-muted">{formatRelativeTime(lead.createdAt)}</span>
                </div>
              </Link>
            ))}
          </CardContent>
        </Card>

        <Card className="min-w-0">
          <CardHeader className="flex-row items-center justify-between space-y-0">
            <CardTitle>Recent conversations</CardTitle>
            <Link href="/dashboard/conversations" className="text-sm font-medium text-brand hover:underline">
              View all
            </Link>
          </CardHeader>
          <CardContent className="space-y-1">
            {recentConversations.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted">No conversations yet.</p>
            ) : (
              recentConversations.map((convo) => (
                <Link
                  key={convo.id}
                  href={`/dashboard/conversations?id=${convo.id}`}
                  className="flex items-center gap-3 rounded-md px-2 py-2.5 -mx-2 transition-colors hover:bg-muted-surface"
                >
                  <Avatar name={`${convo.lead.firstName} ${convo.lead.lastName || ""}`} />
                  <div className="min-w-0 flex-1">
                    <p className="flex items-center gap-1.5 truncate text-sm font-medium text-foreground">
                      {convo.lead.firstName} {convo.lead.lastName}
                      {convo.lead.isDemo && (
                        <Badge variant="secondary" className="shrink-0">
                          Demo
                        </Badge>
                      )}
                    </p>
                    <p className="truncate text-xs text-muted">
                      {convo.messages[0]?.content || "No messages yet"}
                    </p>
                  </div>
                  <LeadStatusBadge status={convo.lead.status} />
                </Link>
              ))
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="min-w-0">
          <CardHeader className="flex-row items-center justify-between space-y-0">
            <CardTitle>Upcoming appointments</CardTitle>
            <Link href="/dashboard/appointments" className="text-sm font-medium text-brand hover:underline">
              View all
            </Link>
          </CardHeader>
          <CardContent className="space-y-1">
            {upcomingAppointments.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted">No upcoming appointments.</p>
            ) : (
              upcomingAppointments.map((appt) => (
                <div key={appt.id} className="flex items-center gap-3 rounded-md px-2 py-2.5 -mx-2">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-success-surface text-success">
                    <Calendar className="h-4 w-4" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="flex items-center gap-1.5 truncate text-sm font-medium text-foreground">
                      {appt.lead.firstName} {appt.lead.lastName}
                      {appt.lead.isDemo && (
                        <Badge variant="secondary" className="shrink-0">
                          Demo
                        </Badge>
                      )}
                    </p>
                    <p className="truncate text-xs text-muted">{formatDateTime(appt.scheduledAt)}</p>
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card className="min-w-0">
          <CardHeader className="flex-row items-center justify-between space-y-0">
            <CardTitle>Recent AI activity</CardTitle>
            <Sparkles className="h-4 w-4 text-brand" />
          </CardHeader>
          <CardContent className="space-y-1">
            {aiActivity.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted">No AI activity yet.</p>
            ) : (
              aiActivity.map((message) => (
                <div key={message.id} className="flex gap-3 rounded-md px-2 py-2.5 -mx-2">
                  <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-brand/10 text-brand">
                    <Sparkles className="h-3.5 w-3.5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm text-foreground">
                      <span className="font-medium">
                        {message.conversation.lead.firstName} {message.conversation.lead.lastName}
                      </span>{" "}
                      · {message.content}
                    </p>
                    <p className="flex items-center gap-1.5 text-[11px] text-muted">
                      {formatRelativeTime(message.createdAt)}
                      {message.conversation.lead.isDemo && <Badge variant="secondary">Demo</Badge>}
                    </p>
                  </div>
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>

      <div className="flex justify-end">
        <Button variant="outline" asChild>
          <Link href="/dashboard/leads">
            <Plus className="h-4 w-4" />
            Add a lead
            <ArrowRight className="h-4 w-4" />
          </Link>
        </Button>
      </div>
    </div>
  );
}
