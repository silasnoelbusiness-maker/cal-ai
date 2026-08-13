"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { requireBusiness } from "@/lib/auth/session";
import { createLead } from "@/lib/leads/create-lead";
import type { LeadStatus, LeadTemperature } from "@prisma/client";

export interface LeadFormState {
  error?: string;
}

const EditLeadSchema = z.object({
  firstName: z.string().trim().min(1, "First name is required."),
  lastName: z.string().trim().optional(),
  email: z.union([z.email("Enter a valid email."), z.literal("")]).optional(),
  phone: z.string().trim().optional(),
  serviceRequested: z.string().trim().optional(),
  estimatedValue: z.string().trim().optional(),
});

const CreateLeadSchema = z.object({
  firstName: z.string().trim().min(1, "First name is required."),
  lastName: z.string().trim().optional(),
  email: z.union([z.email("Enter a valid email."), z.literal("")]).optional(),
  phone: z.string().trim().optional(),
  serviceRequested: z.string().trim().optional(),
  source: z.string().trim().optional(),
  message: z.string().trim().optional(),
  smsConsent: z.boolean().optional(),
});

export async function createLeadAction(
  _prevState: LeadFormState,
  formData: FormData
): Promise<LeadFormState> {
  const { business } = await requireBusiness();

  const parsed = CreateLeadSchema.safeParse({
    firstName: formData.get("firstName") || "",
    lastName: formData.get("lastName") || "",
    email: formData.get("email") || "",
    phone: formData.get("phone") || "",
    serviceRequested: formData.get("serviceRequested") || "",
    source: formData.get("source") || "manual",
    message: formData.get("message") || "",
    smsConsent: formData.get("smsConsent") === "on",
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0].message };
  }

  const result = await createLead(business, parsed.data);
  if (!result.ok) {
    return { error: result.error };
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/leads");
  redirect(`/dashboard/leads/${result.leadId}`);
}

export async function updateLeadStatusAction(leadId: string, status: LeadStatus) {
  const { business } = await requireBusiness();
  const data: { status: LeadStatus; convertedAt?: Date } = { status };
  if (status === "CONVERTED") data.convertedAt = new Date();

  await prisma.lead.updateMany({ where: { id: leadId, businessId: business.id }, data });
  await prisma.leadEvent.create({
    data: {
      leadId,
      businessId: business.id,
      type: "STATUS_CHANGED",
      description: `Status changed to ${status}.`,
    },
  });

  revalidatePath("/dashboard/leads");
  revalidatePath(`/dashboard/leads/${leadId}`);
  revalidatePath("/dashboard");
}

export async function updateLeadTemperatureAction(leadId: string, temperature: LeadTemperature) {
  const { business } = await requireBusiness();
  await prisma.lead.updateMany({ where: { id: leadId, businessId: business.id }, data: { temperature } });
  revalidatePath("/dashboard/leads");
  revalidatePath(`/dashboard/leads/${leadId}`);
}

export async function deleteLeadAction(leadId: string) {
  const { business } = await requireBusiness();
  await prisma.lead.deleteMany({ where: { id: leadId, businessId: business.id } });
  revalidatePath("/dashboard/leads");
  revalidatePath("/dashboard");
  redirect("/dashboard/leads");
}

const TEST_LEADS = [
  {
    firstName: "Taylor",
    lastName: "Reed",
    email: "taylor.reed@example.com",
    phone: "+15125550199",
    serviceRequested: "AC Repair",
    message: "My air conditioner is blowing warm air, can someone take a look this week?",
  },
  {
    firstName: "Jordan",
    lastName: "Blake",
    email: "jordan.blake@example.com",
    phone: "+15125550188",
    serviceRequested: "Drain Cleaning",
    message: "Kitchen sink is draining really slowly, looking for a quote.",
  },
  {
    firstName: "Casey",
    lastName: "Morgan",
    email: "casey.morgan@example.com",
    phone: "+15125550177",
    serviceRequested: "Roof Inspection",
    message: "Noticed a few shingles missing after the storm, want it checked out.",
  },
];

export async function createTestLeadAction() {
  const { business } = await requireBusiness();
  const sample = TEST_LEADS[Math.floor(Math.random() * TEST_LEADS.length)];

  const result = await createLead(business, {
    ...sample,
    source: "manual",
    channel: "WEB",
  });

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/leads");
  return result;
}

export async function updateLeadDetailsAction(
  leadId: string,
  _prevState: LeadFormState,
  formData: FormData
): Promise<LeadFormState> {
  const { business } = await requireBusiness();

  const parsed = EditLeadSchema.safeParse({
    firstName: formData.get("firstName") || "",
    lastName: formData.get("lastName") || "",
    email: formData.get("email") || "",
    phone: formData.get("phone") || "",
    serviceRequested: formData.get("serviceRequested") || "",
    estimatedValue: formData.get("estimatedValue") || "",
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const estimatedValue = parsed.data.estimatedValue ? Number(parsed.data.estimatedValue) : null;
  if (parsed.data.estimatedValue && (Number.isNaN(estimatedValue) || (estimatedValue ?? 0) < 0)) {
    return { error: "Enter a valid estimated value." };
  }

  const result = await prisma.lead.updateMany({
    where: { id: leadId, businessId: business.id },
    data: {
      firstName: parsed.data.firstName,
      lastName: parsed.data.lastName || null,
      email: parsed.data.email || null,
      phone: parsed.data.phone || null,
      serviceRequested: parsed.data.serviceRequested || null,
      estimatedValue,
    },
  });
  if (result.count === 0) return { error: "Lead not found." };

  revalidatePath(`/dashboard/leads/${leadId}`);
  revalidatePath("/dashboard/leads");
  return {};
}

/**
 * Records or withdraws a lead's consent for one channel.
 *
 * Both the follow-up cron and the manual send path refuse to send without
 * the matching flag, so this is the switch that lets a business bring an
 * imported lead — which arrives with no consent on file — into outreach,
 * one lead at a time and only deliberately. Business-scoped like every other
 * lead action: the lead id is filtered by the session's business, so it can
 * never flip a flag on someone else's lead.
 */
export async function setLeadConsentAction(
  leadId: string,
  channel: "sms" | "email",
  granted: boolean
) {
  const { business } = await requireBusiness();

  await prisma.lead.updateMany({
    where: { id: leadId, businessId: business.id },
    data: channel === "sms" ? { smsConsent: granted } : { emailConsent: granted },
  });

  await prisma.leadEvent.create({
    data: {
      leadId,
      businessId: business.id,
      type: "CONSENT_CHANGED",
      description: granted
        ? `${channel === "sms" ? "SMS" : "Email"} consent recorded by the business.`
        : `${channel === "sms" ? "SMS" : "Email"} consent withdrawn.`,
    },
  });

  revalidatePath(`/dashboard/leads/${leadId}`);
}

/**
 * Toggles a lead's opt-out flag (Section 68 SMS/email compliance). Opted-out
 * leads are excluded from all follow-up automation.
 */
export async function toggleLeadOptOutAction(leadId: string, optedOut: boolean) {
  const { business } = await requireBusiness();
  await prisma.lead.updateMany({ where: { id: leadId, businessId: business.id }, data: { optedOut } });
  await prisma.leadEvent.create({
    data: {
      leadId,
      businessId: business.id,
      type: "STATUS_CHANGED",
      description: optedOut
        ? "Lead marked as opted out — automated follow-ups stopped."
        : "Lead opt-out removed — automated follow-ups re-enabled.",
    },
  });
  revalidatePath(`/dashboard/leads/${leadId}`);
}
