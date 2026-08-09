import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiNotFound, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { currentMonthKey } from "@/lib/plans";
import { sendEmail } from "@/lib/resend/send-email";
import { sendSMS } from "@/lib/twilio/send-sms";

const BodySchema = z.object({
  content: z.string().trim().min(1, "Message can't be empty.").max(4000),
});

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { id } = await params;
  const conversation = await prisma.conversation.findFirst({
    where: { id, businessId: auth.business.id },
    include: { messages: { orderBy: { createdAt: "asc" } } },
  });
  if (!conversation) return apiNotFound("Conversation not found.");

  return NextResponse.json({ messages: conversation.messages });
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`messages:${auth.business.id}`, 60, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const { id } = await params;
  const conversation = await prisma.conversation.findFirst({
    where: { id, businessId: auth.business.id },
    include: { lead: true },
  });
  if (!conversation) return apiNotFound("Conversation not found.");

  const json = await request.json().catch(() => null);
  const parsed = BodySchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const message = await prisma.message.create({
    data: {
      conversationId: conversation.id,
      sender: "BUSINESS",
      content: parsed.data.content,
      aiGenerated: false,
    },
  });

  await prisma.$transaction([
    prisma.conversation.update({ where: { id: conversation.id }, data: { status: "OPEN" } }),
    prisma.lead.update({
      where: { id: conversation.leadId },
      data: {
        lastContactedAt: new Date(),
        status: conversation.lead.status === "NEW" ? "CONTACTED" : conversation.lead.status,
      },
    }),
  ]);

  const month = currentMonthKey();
  await prisma.usage.upsert({
    where: { businessId_month: { businessId: auth.business.id, month } },
    create: { businessId: auth.business.id, month, messagesCount: 1 },
    update: { messagesCount: { increment: 1 } },
  });

  // Best-effort outbound delivery — never fails the request if it doesn't go through.
  if (conversation.channel === "SMS" && conversation.lead.phone && conversation.lead.smsConsent) {
    await sendSMS({ to: conversation.lead.phone, body: parsed.data.content });
  } else if (conversation.channel === "EMAIL" && conversation.lead.email && conversation.lead.emailConsent) {
    await sendEmail({ to: conversation.lead.email, subject: "New message", text: parsed.data.content });
  }

  return NextResponse.json({ message }, { status: 201 });
}
