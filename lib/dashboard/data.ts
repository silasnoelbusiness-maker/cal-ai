import "server-only";
import { prisma } from "@/lib/db/prisma";

function monthRange(offset = 0) {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - offset, 1);
  const end = new Date(now.getFullYear(), now.getMonth() - offset + 1, 1);
  return { start, end };
}

function percentChange(current: number, previous: number): number | null {
  if (previous === 0) return current > 0 ? 100 : null;
  return ((current - previous) / previous) * 100;
}

export async function getDashboardMetrics(businessId: string) {
  const thisMonth = monthRange(0);
  const lastMonth = monthRange(1);

  // isDemo: false everywhere below — these are the headline business metrics
  // (including revenue), so sample/demo leads must never inflate them. Demo
  // leads stay visible (tagged) in the activity feeds further down the page.
  const [
    leadsThisMonth,
    leadsLastMonth,
    qualifiedThisMonth,
    qualifiedLastMonth,
    appointmentsThisMonth,
    appointmentsLastMonth,
    revenueThisMonth,
    revenueLastMonth,
  ] = await Promise.all([
    prisma.lead.count({
      where: { businessId, isDemo: false, createdAt: { gte: thisMonth.start, lt: thisMonth.end } },
    }),
    prisma.lead.count({
      where: { businessId, isDemo: false, createdAt: { gte: lastMonth.start, lt: lastMonth.end } },
    }),
    prisma.lead.count({
      where: {
        businessId,
        isDemo: false,
        qualificationScore: { not: null },
        createdAt: { gte: thisMonth.start, lt: thisMonth.end },
      },
    }),
    prisma.lead.count({
      where: {
        businessId,
        isDemo: false,
        qualificationScore: { not: null },
        createdAt: { gte: lastMonth.start, lt: lastMonth.end },
      },
    }),
    prisma.appointment.count({
      where: { businessId, lead: { isDemo: false }, createdAt: { gte: thisMonth.start, lt: thisMonth.end } },
    }),
    prisma.appointment.count({
      where: { businessId, lead: { isDemo: false }, createdAt: { gte: lastMonth.start, lt: lastMonth.end } },
    }),
    prisma.lead.aggregate({
      where: {
        businessId,
        isDemo: false,
        status: "CONVERTED",
        convertedAt: { gte: thisMonth.start, lt: thisMonth.end },
      },
      _sum: { estimatedValue: true },
    }),
    prisma.lead.aggregate({
      where: {
        businessId,
        isDemo: false,
        status: "CONVERTED",
        convertedAt: { gte: lastMonth.start, lt: lastMonth.end },
      },
      _sum: { estimatedValue: true },
    }),
  ]);

  const revenue = Number(revenueThisMonth._sum.estimatedValue || 0);
  const revenuePrev = Number(revenueLastMonth._sum.estimatedValue || 0);

  return {
    leads: { value: leadsThisMonth, change: percentChange(leadsThisMonth, leadsLastMonth) },
    qualified: { value: qualifiedThisMonth, change: percentChange(qualifiedThisMonth, qualifiedLastMonth) },
    appointments: {
      value: appointmentsThisMonth,
      change: percentChange(appointmentsThisMonth, appointmentsLastMonth),
    },
    revenue: { value: revenue, change: percentChange(revenue, revenuePrev) },
  };
}

export async function getPipelineSnapshot(businessId: string) {
  const grouped = await prisma.lead.groupBy({
    by: ["status"],
    where: { businessId, isDemo: false },
    _count: { _all: true },
  });
  const counts: Record<string, number> = {};
  for (const row of grouped) counts[row.status] = row._count._all;
  return counts;
}

export async function getRecentLeads(businessId: string, take = 6) {
  return prisma.lead.findMany({
    where: { businessId },
    orderBy: { createdAt: "desc" },
    take,
  });
}

export async function getRecentConversations(businessId: string, take = 5) {
  const conversations = await prisma.conversation.findMany({
    where: { businessId },
    orderBy: { updatedAt: "desc" },
    take,
    include: {
      lead: true,
      messages: { orderBy: { createdAt: "desc" }, take: 1 },
    },
  });
  return conversations;
}

export async function getUpcomingAppointments(businessId: string, take = 5) {
  return prisma.appointment.findMany({
    where: {
      businessId,
      status: { in: ["PENDING", "CONFIRMED"] },
      scheduledAt: { gte: new Date() },
    },
    orderBy: { scheduledAt: "asc" },
    take,
    include: { lead: true },
  });
}

export async function getRecentAiActivity(businessId: string, take = 6) {
  return prisma.message.findMany({
    where: { sender: "AI", conversation: { businessId } },
    orderBy: { createdAt: "desc" },
    take,
    include: { conversation: { include: { lead: true } } },
  });
}
