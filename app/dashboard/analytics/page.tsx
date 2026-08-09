import type { Metadata } from "next";
import { BarChart3 } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import { getAnalytics } from "@/lib/analytics/data";
import { PageHeader } from "@/components/dashboard/page-header";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { MetricCard } from "@/components/ui/metric-card";
import { EmptyState } from "@/components/ui/empty-state";
import { LeadsTrendChart } from "@/components/analytics/leads-trend-chart";
import { FunnelChart } from "@/components/analytics/funnel-chart";
import { TemperatureBreakdown } from "@/components/analytics/temperature-breakdown";
import { formatCurrency, formatDuration, formatNumber, formatPercent } from "@/lib/utils";

export const metadata: Metadata = { title: "Analytics" };

export default async function AnalyticsPage() {
  const { business } = await requireBusiness();
  const data = await getAnalytics(business.id, 30);

  if (data.totalLeads === 0) {
    return (
      <div>
        <PageHeader title="Analytics" description="Recovered-lead performance over the last 30 days." />
        <EmptyState
          icon={BarChart3}
          title="No data yet"
          description="Analytics will populate once leads start coming in."
        />
      </div>
    );
  }

  return (
    <div>
      <PageHeader title="Analytics" description="Recovered-lead performance over the last 30 days." />

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        <MetricCard label="Total leads" value={formatNumber(data.totalLeads)} />
        <MetricCard label="Contact rate" value={formatPercent(data.contactRate)} />
        <MetricCard label="Qualification rate" value={formatPercent(data.qualificationRate)} />
        <MetricCard label="Appointment rate" value={formatPercent(data.appointmentRate)} />
        <MetricCard label="Conversion rate" value={formatPercent(data.conversionRate)} />
        <MetricCard label="Recovered revenue (est.)" value={formatCurrency(data.recoveredRevenue)} emphasize />
        <MetricCard label="Avg. response time" value={formatDuration(data.avgResponseMinutes)} />
        <MetricCard label="AI conversations" value={formatNumber(data.aiConversations)} />
        <MetricCard label="Follow-up success rate" value={formatPercent(data.followUpSuccessRate)} />
      </div>

      <p className="mt-3 text-xs text-muted">
        Recovered revenue is an estimate — converted leads&apos; estimated job value, not confirmed
        actual revenue.
      </p>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Leads over time</CardTitle>
            <CardDescription>Daily lead volume, last 30 days.</CardDescription>
          </CardHeader>
          <CardContent>
            <LeadsTrendChart data={data.leadsOverTime} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Conversion funnel</CardTitle>
            <CardDescription>Where leads are in the pipeline.</CardDescription>
          </CardHeader>
          <CardContent>
            <FunnelChart data={data.funnel} />
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Lead temperature</CardTitle>
          <CardDescription>AI-assessed intent across all leads in range.</CardDescription>
        </CardHeader>
        <CardContent>
          <TemperatureBreakdown data={data.temperatureBreakdown} />
        </CardContent>
      </Card>
    </div>
  );
}
