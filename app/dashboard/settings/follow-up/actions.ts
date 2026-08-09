"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { requireBusiness } from "@/lib/auth/session";

export interface SettingsFormState {
  error?: string;
  success?: string;
}

const Schema = z.object({
  enabled: z.boolean(),
  immediateResponse: z.boolean(),
  delay30MinEnabled: z.boolean(),
  delay24HourEnabled: z.boolean(),
  delay3DayEnabled: z.boolean(),
  maxFollowUps: z.coerce.number().int().min(0).max(10),
  defaultChannel: z.enum(["SMS", "EMAIL"]),
});

export async function updateFollowUpSettingsAction(
  _prevState: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  const { business } = await requireBusiness();

  const parsed = Schema.safeParse({
    enabled: formData.get("enabled") === "on",
    immediateResponse: formData.get("immediateResponse") === "on",
    delay30MinEnabled: formData.get("delay30MinEnabled") === "on",
    delay24HourEnabled: formData.get("delay24HourEnabled") === "on",
    delay3DayEnabled: formData.get("delay3DayEnabled") === "on",
    maxFollowUps: formData.get("maxFollowUps") || 4,
    defaultChannel: formData.get("defaultChannel") || "EMAIL",
  });

  if (!parsed.success) return { error: parsed.error.issues[0].message };

  await prisma.followUpSettings.upsert({
    where: { businessId: business.id },
    create: { businessId: business.id, ...parsed.data },
    update: parsed.data,
  });

  revalidatePath("/dashboard/settings/follow-up");
  return { success: "Follow-up settings saved." };
}
