import "server-only";
import { prisma } from "@/lib/db/prisma";
import type { NotificationType } from "@prisma/client";
import { isResendConfigured } from "@/lib/auth/config";
import { sendEmail } from "@/lib/resend/send-email";

/**
 * Creates an in-app notification and, if the business has email
 * notifications enabled and Resend is configured, emails the business
 * owner too. Never throws — notification delivery must never break the
 * calling flow (lead creation, qualification, etc.).
 */
export async function notifyBusiness(params: {
  businessId: string;
  type: NotificationType;
  title: string;
  body: string;
  leadId?: string;
}) {
  try {
    await prisma.notification.create({
      data: {
        businessId: params.businessId,
        type: params.type,
        title: params.title,
        body: params.body,
        leadId: params.leadId,
      },
    });

    const [settings, business] = await Promise.all([
      prisma.notificationSettings.findUnique({ where: { businessId: params.businessId } }),
      prisma.business.findUnique({ where: { id: params.businessId } }),
    ]);

    const eventEnabled = settings ? isEventEnabled(settings, params.type) : true;
    const emailEnabled = settings?.emailEnabled ?? true;

    if (eventEnabled && emailEnabled && isResendConfigured && business?.email) {
      await sendEmail({
        to: business.email,
        subject: params.title,
        text: params.body,
      });
    }
  } catch (err) {
    console.error("[notifications] failed to notify business", err);
  }
}

function isEventEnabled(
  settings: { onNewLead: boolean; onHotLead: boolean; onQualifiedLead: boolean; onAppointmentBooked: boolean; onNeedsHuman: boolean },
  type: NotificationType
): boolean {
  switch (type) {
    case "NEW_LEAD":
      return settings.onNewLead;
    case "HOT_LEAD":
      return settings.onHotLead;
    case "QUALIFIED_LEAD":
      return settings.onQualifiedLead;
    case "APPOINTMENT_BOOKED":
      return settings.onAppointmentBooked;
    case "NEEDS_HUMAN":
      return settings.onNeedsHuman;
    default:
      return true;
  }
}
