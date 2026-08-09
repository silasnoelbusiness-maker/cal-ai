import { NextResponse, type NextRequest } from "next/server";
import twilio from "twilio";
import { prisma } from "@/lib/db/prisma";
import { isTwilioConfigured } from "@/lib/auth/config";
import { AIUnavailableError, generateBusinessReply, type AiMessage } from "@/lib/ai";
import { createLead } from "@/lib/leads/create-lead";
import { notifyBusiness } from "@/lib/notifications";
import { checkPlanLimit, currentMonthKey, effectivePlan } from "@/lib/plans";
import { rateLimit } from "@/lib/api/rate-limit";

const STOP_KEYWORDS = new Set(["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"]);
const START_KEYWORDS = new Set(["START", "YES", "UNSTOP"]);

function twiml(message?: string) {
  const body = message
    ? `<?xml version="1.0" encoding="UTF-8"?><Response><Message>${escapeXml(message)}</Message></Response>`
    : `<?xml version="1.0" encoding="UTF-8"?><Response></Response>`;
  return new NextResponse(body, { status: 200, headers: { "Content-Type": "text/xml" } });
}

function escapeXml(text: string) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/**
 * Inbound SMS webhook (Section 6 of the audit / Section 27 of the original
 * spec). Configure this URL as the "A message comes in" webhook on a
 * business's Twilio number (Settings → Integrations shows the exact URL).
 *
 * Twilio's signature is verified on every request — without a valid
 * signature, nothing here is trusted, since this endpoint is public and
 * would otherwise let anyone forge inbound messages / opt-outs on any
 * lead's behalf.
 */
export async function POST(request: NextRequest) {
  if (!isTwilioConfigured) {
    // No auth token means we cannot verify signatures — never process an
    // unverifiable webhook.
    return new NextResponse("SMS is not configured.", { status: 503 });
  }

  const rawBody = await request.text();
  const params = Object.fromEntries(new URLSearchParams(rawBody));

  const signature = request.headers.get("x-twilio-signature");
  const webhookUrl = `${process.env.NEXT_PUBLIC_APP_URL || ""}/api/webhooks/twilio/sms`;

  if (!signature || !twilio.validateRequest(process.env.TWILIO_AUTH_TOKEN!, signature, webhookUrl, params)) {
    console.warn("[webhooks/twilio/sms] invalid signature — rejecting");
    return new NextResponse("Invalid signature.", { status: 403 });
  }

  const from = params.From;
  const to = params.To;
  const body = (params.Body || "").trim();

  if (!from || !body) {
    return twiml();
  }

  // Best-effort abuse guard on top of signature verification — a compromised
  // or misbehaving sender shouldn't be able to hammer this endpoint.
  const { allowed } = rateLimit(`twilio-sms:${from}`, 20, 60_000);
  if (!allowed) return twiml();

  // Route to a business: prefer an exact match on a business's own
  // dedicated Twilio number; fall back to matching an existing lead's phone
  // number (covers the common V1 case of one business sharing the
  // platform-wide TWILIO_PHONE_NUMBER — see README for the limitation this
  // implies once more than one business is texting-enabled).
  let business = to ? await prisma.business.findUnique({ where: { twilioPhoneNumber: to } }) : null;

  const lead = business
    ? await prisma.lead.findFirst({ where: { businessId: business.id, phone: from }, orderBy: { createdAt: "desc" } })
    : await prisma.lead.findFirst({ where: { phone: from }, orderBy: { lastContactedAt: "desc" } });

  if (!business && lead) {
    business = await prisma.business.findUnique({ where: { id: lead.businessId } });
  }

  if (!business) {
    console.warn(`[webhooks/twilio/sms] could not resolve a business for inbound message to ${to}`);
    return twiml();
  }

  const upper = body.toUpperCase();

  if (STOP_KEYWORDS.has(upper)) {
    if (lead) {
      await prisma.lead.update({ where: { id: lead.id }, data: { optedOut: true } });
      await prisma.leadEvent.create({
        data: {
          leadId: lead.id,
          businessId: business.id,
          type: "STATUS_CHANGED",
          description: "Customer texted STOP — opted out of SMS and future follow-ups.",
        },
      });
    }
    return twiml("You've been unsubscribed and won't receive further messages. Reply START to resubscribe.");
  }

  if (START_KEYWORDS.has(upper)) {
    if (lead) {
      await prisma.lead.update({ where: { id: lead.id }, data: { optedOut: false, smsConsent: true } });
      await prisma.leadEvent.create({
        data: {
          leadId: lead.id,
          businessId: business.id,
          type: "STATUS_CHANGED",
          description: "Customer texted START — re-subscribed to SMS.",
        },
      });
    }
    return twiml(`You're resubscribed to messages from ${business.name}.`);
  }

  // Brand-new inbound number — treat it as a new lead reaching out directly
  // by text, reusing the same single entry point every other lead source
  // goes through (plan limits, first response, qualification, follow-up
  // scheduling, notifications).
  if (!lead) {
    const result = await createLead(business, {
      firstName: "SMS",
      lastName: from,
      phone: from,
      message: body,
      source: "sms",
      channel: "SMS",
      smsConsent: true,
    });
    if (!result.ok) {
      // Plan limit reached or another failure — still store nothing further,
      // and don't text back a confusing auto-reply.
      return twiml();
    }
    return twiml();
  }

  if (lead.optedOut) {
    // They opted out previously and are texting again without using START —
    // honor the opt-out; don't auto-reply or re-engage.
    return twiml();
  }

  // Existing lead replying — append the message, mark consent (they're
  // actively texting us), and continue the conversation.
  if (!lead.smsConsent) {
    await prisma.lead.update({ where: { id: lead.id }, data: { smsConsent: true } });
  }

  const conversation =
    (await prisma.conversation.findFirst({
      where: { leadId: lead.id },
      orderBy: { createdAt: "asc" },
      include: { messages: { orderBy: { createdAt: "asc" } } },
    })) ||
    (await prisma.conversation.create({
      data: { businessId: business.id, leadId: lead.id, channel: "SMS" },
      include: { messages: true },
    }));

  await prisma.message.create({ data: { conversationId: conversation.id, sender: "CUSTOMER", content: body } });
  await prisma.lead.update({
    where: { id: lead.id },
    data: { lastContactedAt: new Date(), status: lead.status === "NEW" ? "CONTACTED" : lead.status },
  });

  await notifyBusiness({
    businessId: business.id,
    type: "NEW_MESSAGE",
    title: `New text from ${lead.firstName} ${lead.lastName || ""}`.trim(),
    body,
    leadId: lead.id,
  });

  if (!business.aiEnabled) {
    return twiml();
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
    // Message is stored either way — the business can still reply manually
    // from the dashboard even though the AI limit is reached.
    return twiml();
  }

  try {
    const priorMessages: AiMessage[] = conversation.messages.map((m) => ({ sender: m.sender, content: m.content }));
    const messages: AiMessage[] = [...priorMessages, { sender: "CUSTOMER", content: body }];
    const reply = await generateBusinessReply({ business, lead, messages });

    await prisma.message.create({
      data: { conversationId: conversation.id, sender: "AI", content: reply.content, aiGenerated: true },
    });
    await prisma.usage.update({
      where: { businessId_month: { businessId: business.id, month } },
      data: { aiMessagesCount: { increment: 1 }, messagesCount: { increment: 1 } },
    });

    return twiml(reply.content);
  } catch (err) {
    if (!(err instanceof AIUnavailableError)) console.error("[webhooks/twilio/sms] AI reply failed", err);
    // AI unavailable — message is safely stored; business replies manually.
    return twiml();
  }
}
