import "server-only";
import type { Business, FollowUpSettings, Lead } from "@prisma/client";
import { prisma } from "@/lib/db/prisma";

/** Offsets from lead.createdAt for each follow-up step (Section 25/26). */
const STEP_OFFSETS_MS: Record<number, number> = {
  1: 30 * 60 * 1000, // 30 minutes
  2: 24 * 60 * 60 * 1000, // 24 hours
  3: 3 * 24 * 60 * 60 * 1000, // 3 days
};

function stepEnabled(settings: FollowUpSettings, step: number): boolean {
  if (step === 1) return settings.delay30MinEnabled;
  if (step === 2) return settings.delay24HourEnabled;
  if (step === 3) return settings.delay3DayEnabled;
  return false;
}

export function isLeadEligibleForFollowUp(lead: Pick<Lead, "status" | "optedOut">): boolean {
  return !lead.optedOut && lead.status !== "CONVERTED" && lead.status !== "LOST" && lead.status !== "CLOSED";
}

/**
 * Schedules the next follow-up step for a lead, if follow-up automation is
 * enabled, the step is enabled, the business hasn't hit maxFollowUps, and
 * the lead is still eligible. Steps are anchored to lead.createdAt so they
 * never drift, even if the cron runs a little late.
 */
export async function scheduleNextFollowUp(business: Business, lead: Lead, step: number) {
  if (step > 3) return;

  const settings = await prisma.followUpSettings.findUnique({ where: { businessId: business.id } });
  if (!settings || !settings.enabled) return;
  if (!stepEnabled(settings, step)) return;
  if (!isLeadEligibleForFollowUp(lead)) return;

  const alreadyScheduledOrSent = await prisma.followUp.count({
    where: { leadId: lead.id, stepIndex: step, status: { in: ["PENDING", "SENT"] } },
  });
  if (alreadyScheduledOrSent > 0) return;

  const sentCount = await prisma.followUp.count({ where: { leadId: lead.id, status: "SENT" } });
  if (sentCount >= settings.maxFollowUps) return;

  const scheduledFor = new Date(lead.createdAt.getTime() + STEP_OFFSETS_MS[step]);

  await prisma.followUp.create({
    data: {
      businessId: business.id,
      leadId: lead.id,
      scheduledFor,
      channel: settings.defaultChannel,
      status: "PENDING",
      stepIndex: step,
    },
  });

  await prisma.lead.update({ where: { id: lead.id }, data: { nextFollowUpAt: scheduledFor } });
}
