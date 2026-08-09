import "server-only";
import type { Business, ConversationChannel } from "@prisma/client";
import { prisma } from "@/lib/db/prisma";
import { checkPlanLimit, currentMonthKey } from "@/lib/plans";
import { AIUnavailableError, generateBusinessReply, qualifyLead } from "@/lib/ai";
import { notifyBusiness } from "@/lib/notifications";
import { scheduleNextFollowUp } from "@/lib/follow-ups/schedule";

export interface CreateLeadInput {
  firstName: string;
  lastName?: string;
  email?: string;
  phone?: string;
  source?: string;
  serviceRequested?: string;
  message?: string;
  channel?: ConversationChannel;
  smsConsent?: boolean;
  emailConsent?: boolean;
}

export interface CreateLeadResult {
  ok: boolean;
  leadId?: string;
  error?: string;
}

/**
 * The single entry point for creating a lead, used by manual creation, the
 * "Add Test Lead" action, the public lead-capture API, and the embeddable
 * form. Handles plan limits, the initial conversation, AI first response,
 * AI qualification, and business notifications in one consistent place.
 */
export async function createLead(
  business: Business,
  input: CreateLeadInput
): Promise<CreateLeadResult> {
  const month = currentMonthKey();
  const usage = await prisma.usage.upsert({
    where: { businessId_month: { businessId: business.id, month } },
    create: { businessId: business.id, month },
    update: {},
  });

  const subscription = await prisma.subscription.findUnique({ where: { businessId: business.id } });
  const plan = subscription?.plan || "STARTER";
  const limitCheck = checkPlanLimit(plan, "leads", usage);
  if (!limitCheck.allowed) {
    return { ok: false, error: limitCheck.message };
  }

  const lead = await prisma.lead.create({
    data: {
      businessId: business.id,
      firstName: input.firstName,
      lastName: input.lastName || null,
      email: input.email || null,
      phone: input.phone || null,
      source: input.source || "manual",
      serviceRequested: input.serviceRequested || null,
      message: input.message || null,
      smsConsent: input.smsConsent ?? false,
      emailConsent: input.emailConsent ?? true,
    },
  });

  await prisma.leadEvent.create({
    data: {
      leadId: lead.id,
      businessId: business.id,
      type: "LEAD_CREATED",
      description: `Lead captured from ${lead.source}.`,
    },
  });

  await prisma.usage.update({
    where: { businessId_month: { businessId: business.id, month } },
    data: { leadsCount: { increment: 1 } },
  });

  await notifyBusiness({
    businessId: business.id,
    type: "NEW_LEAD",
    title: `New lead: ${lead.firstName} ${lead.lastName || ""}`.trim(),
    body: lead.serviceRequested
      ? `Interested in ${lead.serviceRequested}${lead.message ? ` — "${lead.message}"` : ""}`
      : lead.message || "New lead received.",
    leadId: lead.id,
  });

  const conversation = await prisma.conversation.create({
    data: {
      businessId: business.id,
      leadId: lead.id,
      channel: input.channel || "WEB",
    },
  });

  if (input.message) {
    await prisma.message.create({
      data: { conversationId: conversation.id, sender: "CUSTOMER", content: input.message },
    });
  }

  const followUpSettings = await prisma.followUpSettings.findUnique({ where: { businessId: business.id } });
  const immediateResponseEnabled = followUpSettings ? followUpSettings.immediateResponse : true;

  if (business.aiEnabled && immediateResponseEnabled) {
    await runInitialAiPipeline(business, lead.id, conversation.id, usage.aiMessagesCount, plan);
  }

  try {
    await scheduleNextFollowUp(business, lead, 1);
  } catch (err) {
    console.error("[leads] failed to schedule initial follow-up", err);
  }

  return { ok: true, leadId: lead.id };
}

async function runInitialAiPipeline(
  business: Business,
  leadId: string,
  conversationId: string,
  aiMessagesUsed: number,
  plan: Parameters<typeof checkPlanLimit>[0]
) {
  const month = currentMonthKey();
  const aiLimitCheck = checkPlanLimit(plan, "aiMessages", { leadsCount: 0, aiMessagesCount: aiMessagesUsed });
  if (!aiLimitCheck.allowed) return;

  const lead = await prisma.lead.findUnique({ where: { id: leadId } });
  if (!lead) return;

  try {
    const reply = await generateBusinessReply({
      business,
      lead,
      messages: lead.message ? [{ sender: "CUSTOMER", content: lead.message }] : [],
    });

    await prisma.message.create({
      data: { conversationId, sender: "AI", content: reply.content, aiGenerated: true },
    });
    await prisma.lead.update({
      where: { id: leadId },
      data: { status: "CONTACTED", lastContactedAt: new Date() },
    });
    await prisma.usage.update({
      where: { businessId_month: { businessId: business.id, month } },
      data: { aiMessagesCount: { increment: 1 }, messagesCount: { increment: 1 } },
    });
  } catch (err) {
    if (!(err instanceof AIUnavailableError)) console.error("[leads] AI first response failed", err);
  }

  try {
    const messages = lead.message
      ? ([{ sender: "CUSTOMER", content: lead.message } as const])
      : [];
    const qualification = await qualifyLead({ business, lead, messages });

    await prisma.lead.update({
      where: { id: leadId },
      data: {
        temperature: qualification.temperature,
        qualificationScore: qualification.qualification_score,
        aiIntent: qualification.intent,
        aiUrgency: qualification.urgency,
        aiLocation: qualification.location,
        aiBudget: qualification.budget,
        aiAvailability: qualification.availability,
        aiSummary: qualification.summary,
        aiRecommendedAction: qualification.recommended_action,
        needsHuman: qualification.needs_human,
        status: qualification.needs_human ? "CONTACTED" : "QUALIFIED",
      },
    });

    await prisma.leadEvent.create({
      data: {
        leadId,
        businessId: business.id,
        type: "AI_QUALIFIED",
        description: `AI qualified this lead as ${qualification.temperature} (score ${qualification.qualification_score}).`,
      },
    });

    if (qualification.temperature === "HOT") {
      await notifyBusiness({
        businessId: business.id,
        type: "HOT_LEAD",
        title: `🔥 Hot lead: ${lead.firstName} ${lead.lastName || ""}`.trim(),
        body: qualification.summary,
        leadId,
      });
    } else {
      await notifyBusiness({
        businessId: business.id,
        type: "QUALIFIED_LEAD",
        title: `Lead qualified: ${lead.firstName} ${lead.lastName || ""}`.trim(),
        body: qualification.summary,
        leadId,
      });
    }

    if (qualification.needs_human) {
      await notifyBusiness({
        businessId: business.id,
        type: "NEEDS_HUMAN",
        title: `Needs human attention: ${lead.firstName} ${lead.lastName || ""}`.trim(),
        body: qualification.recommended_action,
        leadId,
      });
    }
  } catch (err) {
    if (!(err instanceof AIUnavailableError)) console.error("[leads] AI qualification failed", err);
  }
}
