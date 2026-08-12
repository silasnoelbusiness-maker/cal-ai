"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { isAdminEmail } from "@/lib/admin/config";
import { grantPaidAccess, lookupAccess, revokePaidAccess } from "@/lib/admin/access";

export interface AdminAccessState {
  error?: string;
  success?: string;
  lookup?: {
    businessName: string;
    plan: string | null;
    status: string | null;
  };
}

const GrantSchema = z.object({
  email: z.string().trim().min(1, "Enter an email address.").email("Enter a valid email address."),
  plan: z.enum(["STARTER", "GROWTH", "PRO"]),
});

const EmailSchema = z.object({
  email: z.string().trim().min(1, "Enter an email address.").email("Enter a valid email address."),
});

/**
 * Every action re-checks admin status server-side against the session's own
 * email. The page component's check is only a UI convenience — it is never
 * what protects the mutation, so a normal user POSTing directly to this
 * action still cannot grant themselves anything.
 */
async function assertAdmin(): Promise<string | null> {
  const user = await requireUser();
  if (!isAdminEmail(user.email)) {
    console.warn(`[admin] non-admin attempted an access change: ${user.email}`);
    return "Not authorised.";
  }
  return null;
}

export async function grantAccessAction(
  _prev: AdminAccessState,
  formData: FormData
): Promise<AdminAccessState> {
  const denied = await assertAdmin();
  if (denied) return { error: denied };

  const parsed = GrantSchema.safeParse({
    email: formData.get("email"),
    plan: formData.get("plan"),
  });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const result = await grantPaidAccess(parsed.data.email, parsed.data.plan);
  if (!result.ok) return { error: result.error };

  revalidatePath("/dashboard/admin");
  return {
    success: `${result.businessName} is now active on the ${result.plan} plan.`,
  };
}

export async function revokeAccessAction(
  _prev: AdminAccessState,
  formData: FormData
): Promise<AdminAccessState> {
  const denied = await assertAdmin();
  if (denied) return { error: denied };

  const parsed = EmailSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const result = await revokePaidAccess(parsed.data.email);
  if (!result.ok) return { error: result.error };

  revalidatePath("/dashboard/admin");
  return { success: `Paid access revoked for ${result.businessName}.` };
}

export async function lookupAccessAction(
  _prev: AdminAccessState,
  formData: FormData
): Promise<AdminAccessState> {
  const denied = await assertAdmin();
  if (denied) return { error: denied };

  const parsed = EmailSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) return { error: parsed.error.issues[0].message };

  const result = await lookupAccess(parsed.data.email);
  if (!result.ok) return { error: result.error };

  return {
    lookup: {
      businessName: result.business.name,
      plan: result.subscription?.plan ?? null,
      status: result.subscription?.status ?? null,
    },
  };
}
