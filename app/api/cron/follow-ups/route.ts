import { NextResponse, type NextRequest } from "next/server";
import { prisma } from "@/lib/db/prisma";
import { AIUnavailableError, generateFollowUp, type AiMessage } from "@/lib/ai";
import { isLeadEligibleForFollowUp, scheduleNextFollowUp } from "@/lib/follow-ups/schedule";
import { checkPlanLimit, currentMonthKey, effectivePlan } from "@/lib/plans";
import { sendEmail } from "@/lib/resend/send-email";
import { sendSMS } from "@/lib/twilio/send-sms";
import { safeCompare } from "@/lib/api/timing-safe-equal";

const BATCH_SIZE = 25;

function isAuthorized(request: NextRequest): boolean {
  const secret = process.env.LEADLOOP_API_SECRET;
  if (!secret) return false;
  const header = request.headers.get("authorization");
  if (header && safeCompare(header, `Bearer ${secret}`)) return true;
  const query = request.nextUrl.searchParams.get("secret");
  return Boolean(query) && safeCompare(query!, secret);
}

/**
 * Processes due follow-ups (Section 26/59/67). Trigger this on a schedule —
 * e.g. a Vercel Cron job or any external scheduler — pointed at this route
 * with `Authorization: Bearer $LEADLOOP_API_SECRET`. Every step re-verifies
 * the lead is still eligible before sending anything.
 */
export async function POST(request: NextRequest) {
  return handle(request);
}

export async function GET(request: NextRequest) {
  return handle(request);
}

async function handle(request: NextRequest) {
  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "Unauthorized." }, { status: 401 });
  }

  const due = await prisma.followUp.findMany({
    where: { status: "PENDING", scheduledFor: { lte: new Date() } },
    orderBy: { scheduledFor: "asc" },
    take: BATCH_SIZE,
    include: { lead: true, business: true },
  });

  let sent = 0;
  let skipped = 0;
  let cancelled = 0;

  for (const followUp of due) {
    const { lead, business } = followUp;

    if (!isLeadEligibleForFollowUp(lead)) {
      await prisma.followUp.update({ where: { id: followUp.id }, data: { status: "CANCELLED" } });
      cancelled++;
      continue;
    }

    // If the lead has progressed past initial contact, treat it as already
    // engaged — don't interrupt an active conversation with a scripted
    // check-in, and don't queue further automated steps.
    if (lead.status !== "NEW" && lead.status !== "CONTACTED") {
      await prisma.followUp.update({ where: { id: followUp.id }, data: { status: "SKIPPED" } });
      skipped++;
      continue;
    }

    const month = currentMonthKey();
    const usage = await prisma.usage.upsert({
      where: { businessId_month: { businessId: business.id, month } },
      create: { businessId: business.id, month },
      update: {},
    });
    const subscription = await prisma.subscription.findUnique({ where: { businessId: business.id } });
    const limitCheck = checkPlanLimit(effectivePlan(subscription), "aiMessages", usage);
    if (!limitCheck.allowed) {
      // Leave PENDING — will be retried on a future run once usage resets
      // or the business upgrades. Don't burn through the follow-up chain
      // silently.
      skipped++;
      continue;
    }

    const conversation =
      (await prisma.conversation.findFirst({
        where: { leadId: lead.id },
        orderBy: { createdAt: "asc" },
        include: { messages: { orderBy: { createdAt: "asc" } } },
      })) ||
      (await prisma.conversation.create({
        data: { businessId: business.id, leadId: lead.id, channel: "WEB" },
        include: { messages: true },
      }));

    try {
      const messages: AiMessage[] = conversation.messages.map((m) => ({ sender: m.sender, content: m.content }));
      const followUpMessage = await generateFollowUp({
        business,
        lead,
        messages,
        stepIndex: followUp.stepIndex,
      });

      await prisma.message.create({
        data: {
          conversationId: conversation.id,
          sender: "AI",
          content: followUpMessage.content,
          aiGenerated: true,
        },
      });

      if (followUp.channel === "SMS" && lead.phone && lead.smsConsent) {
        await sendSMS({ to: lead.phone, body: followUpMessage.content, from: business.twilioPhoneNumber });
      } else if (followUp.channel === "EMAIL" && lead.email && lead.emailConsent) {
        await sendEmail({ to: lead.email, subject: `Following up — ${business.name}`, text: followUpMessage.content });
      }

      await prisma.$transaction([
        prisma.followUp.update({
          where: { id: followUp.id },
          data: { status: "SENT", sentAt: new Date(), message: followUpMessage.content },
        }),
        prisma.lead.update({
          where: { id: lead.id },
          data: { lastContactedAt: new Date(), status: lead.status === "NEW" ? "CONTACTED" : lead.status },
        }),
        prisma.leadEvent.create({
          data: {
            leadId: lead.id,
            businessId: business.id,
            type: "FOLLOW_UP_SENT",
            description: `Follow-up #${followUp.stepIndex} sent via ${followUp.channel}.`,
          },
        }),
        prisma.usage.update({
          where: { businessId_month: { businessId: business.id, month } },
          data: { aiMessagesCount: { increment: 1 }, messagesCount: { increment: 1 } },
        }),
      ]);

      await scheduleNextFollowUp(business, { ...lead, status: "CONTACTED" }, followUp.stepIndex + 1);
      sent++;
    } catch (err) {
      if (err instanceof AIUnavailableError) {
        skipped++;
        continue;
      }
      console.error("[cron/follow-ups] failed to process follow-up", followUp.id, err);
      skipped++;
    }
  }

  if (sent > 0) {
    console.log(`[cron/follow-ups] sent=${sent} skipped=${skipped} cancelled=${cancelled}`);
  }

  return NextResponse.json({ processed: due.length, sent, skipped, cancelled });
}
