"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { requireUser, getCurrentBusiness } from "@/lib/auth/session";
import { loadDemoData } from "@/lib/demo";
import { WEEKDAYS } from "@/lib/constants";

export interface OnboardingFormState {
  error?: string;
}

const OnboardingSchema = z.object({
  name: z.string().trim().min(2, "Business name is required."),
  industry: z.string().trim().min(1, "Select an industry."),
  services: z.string().trim().optional(),
  serviceArea: z.string().trim().optional(),
  aiTone: z.string().trim().min(1),
  loadDemo: z.boolean(),
});

export async function completeOnboardingAction(
  _prevState: OnboardingFormState,
  formData: FormData
): Promise<OnboardingFormState> {
  const user = await requireUser();

  const raw = {
    name: String(formData.get("name") || ""),
    industry: String(formData.get("industry") || ""),
    services: String(formData.get("services") || ""),
    serviceArea: String(formData.get("serviceArea") || ""),
    aiTone: String(formData.get("aiTone") || "professional"),
    loadDemo: formData.get("loadDemo") === "on",
  };

  const parsed = OnboardingSchema.safeParse(raw);
  if (!parsed.success) {
    return { error: parsed.error.issues[0].message };
  }

  const businessHours: Record<string, string> = {};
  for (const day of WEEKDAYS) {
    const value = formData.get(`hours_${day.key}`);
    businessHours[day.key] = typeof value === "string" && value.trim() ? value.trim() : "Closed";
  }

  const existing = await getCurrentBusiness();

  const business = existing
    ? await prisma.business.update({
        where: { id: existing.id },
        data: {
          name: parsed.data.name,
          industry: parsed.data.industry,
          aiServices: parsed.data.services || null,
          serviceArea: parsed.data.serviceArea || null,
          businessHours,
          aiTone: parsed.data.aiTone,
          onboardingCompleted: true,
          onboardingStep: 8,
        },
      })
    : await prisma.$transaction(async (tx) => {
        const created = await tx.business.create({
          data: {
            ownerId: user.id,
            name: parsed.data.name,
            industry: parsed.data.industry,
            aiServices: parsed.data.services || null,
            serviceArea: parsed.data.serviceArea || null,
            businessHours,
            aiTone: parsed.data.aiTone,
            onboardingCompleted: true,
            onboardingStep: 8,
          },
        });
        await tx.businessMember.create({
          data: { businessId: created.id, userId: user.id, role: "OWNER" },
        });
        await tx.followUpSettings.create({ data: { businessId: created.id } });
        await tx.notificationSettings.create({ data: { businessId: created.id } });
        await tx.subscription.create({
          data: { businessId: created.id, plan: "STARTER", status: "NONE" },
        });
        return created;
      });

  if (parsed.data.loadDemo) {
    await loadDemoData(business.id);
  }

  redirect("/dashboard");
}
