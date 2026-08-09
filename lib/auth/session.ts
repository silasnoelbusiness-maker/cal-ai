import "server-only";
import { redirect } from "next/navigation";
import { prisma } from "@/lib/db/prisma";
import { createSupabaseServerClient } from "./supabase-server";
import { isSupabaseConfigured } from "./config";
import type { Business, User } from "@prisma/client";

/**
 * Returns the authenticated Supabase user for the current request, or null.
 * Never trust a user id supplied by the client — this is always derived
 * from the verified session cookie.
 */
export async function getSupabaseUser() {
  if (!isSupabaseConfigured) return null;
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
}

/**
 * Returns the current app-level User row, creating it on first sign-in if
 * it doesn't exist yet (mirrors the Supabase auth user).
 */
export async function getCurrentUser(): Promise<User | null> {
  const authUser = await getSupabaseUser();
  if (!authUser || !authUser.email) return null;

  return prisma.user.upsert({
    where: { id: authUser.id },
    update: { email: authUser.email },
    create: { id: authUser.id, email: authUser.email },
  });
}

/**
 * Returns the current user's business (V1 assumes one primary business per
 * account, sourced via BusinessMember — never via a client-supplied id).
 */
export async function getCurrentBusiness(): Promise<Business | null> {
  const user = await getCurrentUser();
  if (!user) return null;

  const membership = await prisma.businessMember.findFirst({
    where: { userId: user.id },
    orderBy: { createdAt: "asc" },
    include: { business: true },
  });

  return membership?.business ?? null;
}

/** For Server Components / layouts: redirect unauthenticated visitors to /login. */
export async function requireUser(): Promise<User> {
  const user = await getCurrentUser();
  if (!user) redirect("/login");
  return user;
}

/** For dashboard routes: redirect users without a completed business to onboarding. */
export async function requireBusiness(): Promise<{ user: User; business: Business }> {
  const user = await requireUser();
  const business = await getCurrentBusiness();
  if (!business) redirect("/onboarding");
  if (!business.onboardingCompleted) redirect("/onboarding");
  return { user, business };
}

/**
 * For API routes: returns the authenticated user + business without ever
 * redirecting. Callers should return 401/403 JSON responses when null.
 */
export async function getApiAuthContext(): Promise<{
  user: User;
  business: Business;
} | null> {
  const user = await getCurrentUser();
  if (!user) return null;
  const business = await getCurrentBusiness();
  if (!business) return null;
  return { user, business };
}
