"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/auth/supabase-server";
import { isSupabaseConfigured } from "@/lib/auth/config";

export interface AuthFormState {
  error?: string;
  success?: string;
}

const emailSchema = z.email("Enter a valid email address.");
const passwordSchema = z.string().min(8, "Password must be at least 8 characters.");

function notConfiguredState(): AuthFormState {
  return {
    error:
      "Authentication isn't configured yet. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY to enable sign-up and login.",
  };
}

export async function signUpAction(
  _prevState: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  if (!isSupabaseConfigured) return notConfiguredState();

  const email = String(formData.get("email") || "").trim();
  const password = String(formData.get("password") || "");

  const emailResult = emailSchema.safeParse(email);
  if (!emailResult.success) return { error: emailResult.error.issues[0].message };
  const passwordResult = passwordSchema.safeParse(password);
  if (!passwordResult.success) return { error: passwordResult.error.issues[0].message };

  const supabase = await createSupabaseServerClient();
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";

  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: `${appUrl}/auth/callback?next=/onboarding` },
  });

  if (error) return { error: error.message };

  if (data.session) {
    redirect("/onboarding");
  }

  return {
    success:
      "Account created. Check your email to confirm your address, then log in to get started.",
  };
}

export async function loginAction(
  _prevState: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  if (!isSupabaseConfigured) return notConfiguredState();

  const email = String(formData.get("email") || "").trim();
  const password = String(formData.get("password") || "");
  const next = String(formData.get("next") || "/dashboard");

  if (!email || !password) return { error: "Enter your email and password." };

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) return { error: "Incorrect email or password." };

  redirect(next.startsWith("/") ? next : "/dashboard");
}

export async function logoutAction() {
  if (isSupabaseConfigured) {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.signOut();
  }
  redirect("/");
}

export async function requestPasswordResetAction(
  _prevState: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  if (!isSupabaseConfigured) return notConfiguredState();

  const email = String(formData.get("email") || "").trim();
  const emailResult = emailSchema.safeParse(email);
  if (!emailResult.success) return { error: emailResult.error.issues[0].message };

  const supabase = await createSupabaseServerClient();
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";

  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${appUrl}/auth/callback?next=/reset-password`,
  });

  // Always return success (don't leak whether an email is registered).
  if (error) {
    return { success: "If an account exists for that email, a reset link is on its way." };
  }

  return { success: "Check your email for a link to reset your password." };
}

export async function updatePasswordAction(
  _prevState: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  if (!isSupabaseConfigured) return notConfiguredState();

  const password = String(formData.get("password") || "");
  const passwordResult = passwordSchema.safeParse(password);
  if (!passwordResult.success) return { error: passwordResult.error.issues[0].message };

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Your reset link has expired. Request a new one." };
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) return { error: error.message };

  redirect("/dashboard");
}
