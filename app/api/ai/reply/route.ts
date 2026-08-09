import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiNotFound, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { checkPlanLimit, currentMonthKey } from "@/lib/plans";
import { AIUnavailableError, generateBusinessReply, type AiMessage } from "@/lib/ai";

const BodySchema = z.object({
  conversationId: z.string().min(1),
});

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`ai-reply:${auth.business.id}`, 30, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const json = await request.json().catch(() => null);
  const parsed = BodySchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const conversation = await prisma.conversation.findFirst({
    where: { id: parsed.data.conversationId, businessId: auth.business.id },
    include: { lead: true, messages: { orderBy: { createdAt: "asc" } } },
  });
  if (!conversation) return apiNotFound("Conversation not found.");

  const month = currentMonthKey();
  const usage = await prisma.usage.upsert({
    where: { businessId_month: { businessId: auth.business.id, month } },
    create: { businessId: auth.business.id, month },
    update: {},
  });
  const subscription = await prisma.subscription.findUnique({ where: { businessId: auth.business.id } });
  const limitCheck = checkPlanLimit(subscription?.plan || "STARTER", "aiMessages", usage);
  if (!limitCheck.allowed) return apiError(limitCheck.message || "AI message limit reached.", 402);

  try {
    const messages: AiMessage[] = conversation.messages.map((m) => ({
      sender: m.sender,
      content: m.content,
    }));
    const reply = await generateBusinessReply({ business: auth.business, lead: conversation.lead, messages });
    return NextResponse.json({ content: reply.content });
  } catch (err) {
    if (err instanceof AIUnavailableError) return apiError(err.message, 503);
    console.error("[api/ai/reply] unexpected error", err);
    return apiError("AI is temporarily unavailable. You can still reply manually.", 503);
  }
}
