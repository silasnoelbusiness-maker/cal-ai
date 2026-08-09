import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { requireUser, getCurrentBusiness } from "@/lib/auth/session";
import { OnboardingWizard } from "@/components/onboarding/onboarding-wizard";

export const metadata: Metadata = { title: "Set up your workspace" };
export const dynamic = "force-dynamic";

export default async function OnboardingPage() {
  await requireUser();
  const business = await getCurrentBusiness();

  if (business?.onboardingCompleted) {
    redirect("/dashboard");
  }

  return <OnboardingWizard business={business} />;
}
