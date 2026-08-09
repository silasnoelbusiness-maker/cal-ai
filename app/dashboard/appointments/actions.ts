"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { requireBusiness } from "@/lib/auth/session";
import { notifyBusiness } from "@/lib/notifications";
import type { AppointmentStatus } from "@prisma/client";

export interface AppointmentFormState {
  error?: string;
}

const CreateAppointmentSchema = z.object({
  leadId: z.string().min(1),
  scheduledAt: z.string().min(1, "Choose a date and time."),
  notes: z.string().trim().optional(),
});

export async function createAppointmentAction(
  _prevState: AppointmentFormState,
  formData: FormData
): Promise<AppointmentFormState> {
  const { business } = await requireBusiness();

  const parsed = CreateAppointmentSchema.safeParse({
    leadId: formData.get("leadId"),
    scheduledAt: formData.get("scheduledAt"),
    notes: formData.get("notes") || "",
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const scheduledAt = new Date(parsed.data.scheduledAt);
  if (Number.isNaN(scheduledAt.getTime())) return { error: "Enter a valid date and time." };

  const lead = await prisma.lead.findFirst({ where: { id: parsed.data.leadId, businessId: business.id } });
  if (!lead) return { error: "Lead not found." };

  await prisma.$transaction([
    prisma.appointment.create({
      data: {
        businessId: business.id,
        leadId: lead.id,
        scheduledAt,
        notes: parsed.data.notes || null,
        status: "PENDING",
      },
    }),
    prisma.lead.update({ where: { id: lead.id }, data: { status: "APPOINTMENT" } }),
    prisma.leadEvent.create({
      data: {
        leadId: lead.id,
        businessId: business.id,
        type: "APPOINTMENT_BOOKED",
        description: `Appointment scheduled for ${scheduledAt.toLocaleString()}.`,
      },
    }),
  ]);

  await notifyBusiness({
    businessId: business.id,
    type: "APPOINTMENT_BOOKED",
    title: `Appointment booked: ${lead.firstName} ${lead.lastName || ""}`.trim(),
    body: `Scheduled for ${scheduledAt.toLocaleString()}.`,
    leadId: lead.id,
  });

  revalidatePath("/dashboard/appointments");
  revalidatePath(`/dashboard/leads/${lead.id}`);
  revalidatePath("/dashboard");
  return {};
}

export async function updateAppointmentStatusAction(appointmentId: string, status: AppointmentStatus) {
  const { business } = await requireBusiness();

  const appointment = await prisma.appointment.findFirst({
    where: { id: appointmentId, businessId: business.id },
  });
  if (!appointment) return;

  await prisma.appointment.update({ where: { id: appointmentId }, data: { status } });

  if (status === "COMPLETED") {
    await prisma.lead.updateMany({
      where: { id: appointment.leadId, businessId: business.id, status: { not: "CONVERTED" } },
      data: {},
    });
  }

  revalidatePath("/dashboard/appointments");
  revalidatePath(`/dashboard/leads/${appointment.leadId}`);
  revalidatePath("/dashboard");
}
