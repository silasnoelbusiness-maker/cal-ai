import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiNotFound, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { checkPlanLimit, currentMonthKey } from "@/lib/plans";
import { AIUnavailableError, qualifyLead, type AiMessage } from "@/lib/ai";
import { notifyBusiness } from "@/lib/notifications";

const BodySchema = z.object({
  leadId: z.string().min(1),
});

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`ai-qualify:${auth.business.id}`, 30, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const json = await request.json().catch(() => null);
  const parsed = BodySchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const lead = await prisma.lead.findFirst({
    where: { id: parsed.data.leadId, businessId: auth.business.id },
  });
  if (!lead) return apiNotFound("Lead not found.");

  const month = currentMonthKey();
  const usage = await prisma.usage.upsert({
    where: { businessId_month: { businessId: auth.business.id, month } },
    create: { businessId: auth.business.id, month },
    update: {},
  });
  const subscription = await prisma.subscription.findUnique({ where: { businessId: auth.business.id } });
  const limitCheck = checkPlanLimit(subscription?.plan || "STARTER", "aiMessages", usage);
  if (!limitCheck.allowed) return apiError(limitCheck.message || "AI message limit reached.", 402);

  const conversations = await prisma.conversation.findMany({
    where: { leadId: lead.id },
    include: { messages: { orderBy: { createdAt: "asc" } } },
  });
  const messages: AiMessage[] = conversations
    .flatMap((c) => c.messages)
    .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
    .map((m) => ({ sender: m.sender, content: m.content }));

  try {
    const qualification = await qualifyLead({ business: auth.business, lead, messages });

    const updated = await prisma.lead.update({
      where: { id: lead.id },
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
        status: qualification.needs_human
          ? lead.status
          : lead.status === "NEW" || lead.status === "CONTACTED"
            ? "QUALIFIED"
            : lead.status,
      },
    });

    await prisma.leadEvent.create({
      data: {
        leadId: lead.id,
        businessId: auth.business.id,
        type: "AI_QUALIFIED",
        description: `AI re-qualified this lead as ${qualification.temperature} (score ${qualification.qualification_score}).`,
      },
    });

    await prisma.usage.update({
      where: { businessId_month: { businessId: auth.business.id, month } },
      data: { aiMessagesCount: { increment: 1 } },
    });

    if (qualification.needs_human) {
      await notifyBusiness({
        businessId: auth.business.id,
        type: "NEEDS_HUMAN",
        title: `Needs human attention: ${lead.firstName} ${lead.lastName || ""}`.trim(),
        body: qualification.recommended_action,
        leadId: lead.id,
      });
    }

    return NextResponse.json({ lead: updated, qualification });
  } catch (err) {
    if (err instanceof AIUnavailableError) return apiError(err.message, 503);
    console.error("[api/ai/qualify] unexpected error", err);
    return apiError("AI is temporarily unavailable.", 503);
  }
}
