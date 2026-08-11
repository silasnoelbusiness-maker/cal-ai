"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { requireBusiness } from "@/lib/auth/session";
import { WEEKDAYS } from "@/lib/constants";

export interface SettingsFormState {
  error?: string;
  success?: string;
}

const BusinessSchema = z.object({
  name: z.string().trim().min(2, "Business name is required."),
  industry: z.string().trim().optional(),
  website: z.union([z.url("Enter a valid URL."), z.literal("")]).optional(),
  phone: z.string().trim().optional(),
  email: z.union([z.email("Enter a valid email."), z.literal("")]).optional(),
  serviceArea: z.string().trim().optional(),
  timezone: z.string().trim().min(1),
  aiEnabled: z.boolean(),
});

export async function updateBusinessSettingsAction(
  _prevState: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  const { business } = await requireBusiness();

  const parsed = BusinessSchema.safeParse({
    name: formData.get("name"),
    industry: formData.get("industry") || "",
    website: formData.get("website") || "",
    phone: formData.get("phone") || "",
    email: formData.get("email") || "",
    serviceArea: formData.get("serviceArea") || "",
    timezone: formData.get("timezone") || "America/Chicago",
    aiEnabled: formData.get("aiEnabled") === "on",
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const businessHours: Record<string, string> = {};
  for (const day of WEEKDAYS) {
    const value = formData.get(`hours_${day.key}`);
    businessHours[day.key] = typeof value === "string" && value.trim() ? value.trim() : "Closed";
  }

  await prisma.business.update({
    where: { id: business.id },
    data: {
      name: parsed.data.name,
      industry: parsed.data.industry || null,
      website: parsed.data.website || null,
      phone: parsed.data.phone || null,
      email: parsed.data.email || null,
      serviceArea: parsed.data.serviceArea || null,
      timezone: parsed.data.timezone,
      aiEnabled: parsed.data.aiEnabled,
      businessHours,
    },
  });

  revalidatePath("/dashboard/settings");
  return { success: "Business settings saved." };
}

const AiSettingsSchema = z.object({
  aiDescription: z.string().trim().optional(),
  aiServices: z.string().trim().optional(),
  aiTypicalCustomer: z.string().trim().optional(),
  aiTone: z.string().trim().min(1),
  aiBookingUrl: z.union([z.url("Enter a valid URL."), z.literal("")]).optional(),
  aiEmergencyInstructions: z.string().trim().optional(),
  aiPricingInfo: z.string().trim().optional(),
  aiCustomInstructions: z.string().trim().optional(),
});

export async function updateAiSettingsAction(
  _prevState: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  const { business } = await requireBusiness();

  const parsed = AiSettingsSchema.safeParse({
    aiDescription: formData.get("aiDescription") || "",
    aiServices: formData.get("aiServices") || "",
    aiTypicalCustomer: formData.get("aiTypicalCustomer") || "",
    aiTone: formData.get("aiTone") || "professional",
    aiBookingUrl: formData.get("aiBookingUrl") || "",
    aiEmergencyInstructions: formData.get("aiEmergencyInstructions") || "",
    aiPricingInfo: formData.get("aiPricingInfo") || "",
    aiCustomInstructions: formData.get("aiCustomInstructions") || "",
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const questions = formData.getAll("faq_question");
  const answers = formData.getAll("faq_answer");
  const faqs = questions
    .map((q, i) => ({ question: String(q).trim(), answer: String(answers[i] || "").trim() }))
    .filter((f) => f.question && f.answer);

  await prisma.business.update({
    where: { id: business.id },
    data: {
      aiDescription: parsed.data.aiDescription || null,
      aiServices: parsed.data.aiServices || null,
      aiTypicalCustomer: parsed.data.aiTypicalCustomer || null,
      aiTone: parsed.data.aiTone,
      aiBookingUrl: parsed.data.aiBookingUrl || null,
      aiEmergencyInstructions: parsed.data.aiEmergencyInstructions || null,
      aiPricingInfo: parsed.data.aiPricingInfo || null,
      aiCustomInstructions: parsed.data.aiCustomInstructions || null,
      aiFaqs: faqs,
    },
  });

  revalidatePath("/dashboard/settings/ai");
  return { success: "AI assistant settings saved." };
}

const NotificationSettingsSchema = z.object({
  emailEnabled: z.boolean(),
  smsEnabled: z.boolean(),
  onNewLead: z.boolean(),
  onHotLead: z.boolean(),
  onQualifiedLead: z.boolean(),
  onAppointmentBooked: z.boolean(),
  onNeedsHuman: z.boolean(),
});

export async function updateNotificationSettingsAction(
  _prevState: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  const { business } = await requireBusiness();

  const parsed = NotificationSettingsSchema.parse({
    emailEnabled: formData.get("emailEnabled") === "on",
    smsEnabled: formData.get("smsEnabled") === "on",
    onNewLead: formData.get("onNewLead") === "on",
    onHotLead: formData.get("onHotLead") === "on",
    onQualifiedLead: formData.get("onQualifiedLead") === "on",
    onAppointmentBooked: formData.get("onAppointmentBooked") === "on",
    onNeedsHuman: formData.get("onNeedsHuman") === "on",
  });

  await prisma.notificationSettings.upsert({
    where: { businessId: business.id },
    create: { businessId: business.id, ...parsed },
    update: parsed,
  });

  revalidatePath("/dashboard/settings/notifications");
  return { success: "Notification preferences saved." };
}

const SmsSettingsSchema = z.object({
  twilioPhoneNumber: z.union([
    z.string().trim().regex(/^\+[1-9]\d{6,14}$/, "Enter the number in E.164 format, e.g. +15125550100."),
    z.literal(""),
  ]),
});

export async function updateSmsSettingsAction(
  _prevState: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  const { business } = await requireBusiness();

  const parsed = SmsSettingsSchema.safeParse({
    twilioPhoneNumber: formData.get("twilioPhoneNumber") || "",
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  try {
    await prisma.business.update({
      where: { id: business.id },
      data: { twilioPhoneNumber: parsed.data.twilioPhoneNumber || null },
    });
  } catch (err) {
    if (err instanceof Error && "code" in err && (err as { code?: string }).code === "P2002") {
      return { error: "That number is already configured on another Converana account." };
    }
    throw err;
  }

  revalidatePath("/dashboard/settings/integrations");
  return { success: "SMS number saved." };
}
