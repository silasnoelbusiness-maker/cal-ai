import "server-only";
import { prisma } from "@/lib/db/prisma";

export interface AnalyticsData {
  totalLeads: number;
  contactRate: number;
  qualificationRate: number;
  appointmentRate: number;
  conversionRate: number;
  recoveredRevenue: number;
  avgResponseMinutes: number | null;
  aiConversations: number;
  followUpSuccessRate: number | null;
  leadsOverTime: { date: string; leads: number }[];
  funnel: { stage: string; count: number }[];
  temperatureBreakdown: { temperature: "HOT" | "WARM" | "COLD"; count: number }[];
}

export async function getAnalytics(businessId: string, rangeDays = 30): Promise<AnalyticsData> {
  const since = new Date(Date.now() - rangeDays * 24 * 60 * 60 * 1000);

  // isDemo: false — analytics (especially recovered revenue) must reflect
  // real business performance only; sample/demo leads are never counted here.
  const leads = await prisma.lead.findMany({
    where: { businessId, isDemo: false, createdAt: { gte: since } },
    include: {
      appointments: true,
      conversations: { include: { messages: { orderBy: { createdAt: "asc" } } } },
      followUps: true,
    },
  });

  const totalLeads = leads.length;

  const contacted = leads.filter((l) => l.status !== "NEW").length;
  const qualified = leads.filter((l) => l.qualificationScore !== null).length;
  const withAppointment = leads.filter((l) => l.appointments.length > 0).length;
  const converted = leads.filter((l) => l.status === "CONVERTED");

  const recoveredRevenue = converted.reduce((sum, l) => sum + Number(l.estimatedValue || 0), 0);

  const responseTimes: number[] = [];
  let aiConversations = 0;
  for (const lead of leads) {
    for (const convo of lead.conversations) {
      const firstResponse = convo.messages.find((m) => m.sender === "AI" || m.sender === "BUSINESS");
      if (firstResponse) {
        responseTimes.push((firstResponse.createdAt.getTime() - lead.createdAt.getTime()) / 60000);
      }
      if (convo.messages.some((m) => m.sender === "AI")) aiConversations++;
    }
  }
  const avgResponseMinutes =
    responseTimes.length > 0 ? responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length : null;

  const leadsWithFollowUp = leads.filter((l) => l.followUps.some((f) => f.status === "SENT"));
  const followUpSuccessRate =
    leadsWithFollowUp.length > 0
      ? (leadsWithFollowUp.filter((l) => l.status === "QUALIFIED" || l.status === "APPOINTMENT" || l.status === "CONVERTED")
          .length /
          leadsWithFollowUp.length) *
        100
      : null;

  // Daily lead counts for the trend chart.
  const dayBuckets = new Map<string, number>();
  for (let i = rangeDays - 1; i >= 0; i--) {
    const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000);
    dayBuckets.set(d.toISOString().slice(0, 10), 0);
  }
  for (const lead of leads) {
    const key = lead.createdAt.toISOString().slice(0, 10);
    if (dayBuckets.has(key)) dayBuckets.set(key, (dayBuckets.get(key) || 0) + 1);
  }
  const leadsOverTime = Array.from(dayBuckets.entries()).map(([date, count]) => ({
    date: new Date(date).toLocaleDateString("en-US", { month: "short", day: "numeric" }),
    leads: count,
  }));

  const funnel = [
    { stage: "New", count: totalLeads },
    { stage: "Contacted", count: contacted },
    { stage: "Qualified", count: qualified },
    { stage: "Appointment", count: withAppointment },
    { stage: "Converted", count: converted.length },
  ];

  const temperatureBreakdown: AnalyticsData["temperatureBreakdown"] = (["HOT", "WARM", "COLD"] as const).map(
    (t) => ({ temperature: t, count: leads.filter((l) => l.temperature === t).length })
  );

  return {
    totalLeads,
    contactRate: totalLeads > 0 ? (contacted / totalLeads) * 100 : 0,
    qualificationRate: totalLeads > 0 ? (qualified / totalLeads) * 100 : 0,
    appointmentRate: totalLeads > 0 ? (withAppointment / totalLeads) * 100 : 0,
    conversionRate: totalLeads > 0 ? (converted.length / totalLeads) * 100 : 0,
    recoveredRevenue,
    avgResponseMinutes,
    aiConversations,
    followUpSuccessRate,
    leadsOverTime,
    funnel,
    temperatureBreakdown,
  };
}
