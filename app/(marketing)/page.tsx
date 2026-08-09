import type { Metadata } from "next";
import { HeroSection } from "@/components/marketing/hero-section";
import { ProblemSection } from "@/components/marketing/problem-section";
import { SolutionSection } from "@/components/marketing/solution-section";
import { HowItWorksSection } from "@/components/marketing/how-it-works-section";
import { DashboardPreviewSection } from "@/components/marketing/dashboard-preview-section";
import { AiConversationSection } from "@/components/marketing/ai-conversation-section";
import { RoiSection } from "@/components/marketing/roi-section";
import { PricingSection } from "@/components/marketing/pricing-section";
import { FinalCtaSection } from "@/components/marketing/final-cta-section";

export const metadata: Metadata = {
  title: "LeadLoop — Turn Missed Leads Into Booked Customers",
  description:
    "AI-powered lead follow-up for local businesses. Automatically respond to new leads, qualify prospects, and help turn more conversations into booked customers.",
};

export default function HomePage() {
  return (
    <>
      <HeroSection />
      <ProblemSection />
      <SolutionSection />
      <HowItWorksSection />
      <DashboardPreviewSection />
      <AiConversationSection />
      <RoiSection />
      <PricingSection />
      <FinalCtaSection />
    </>
  );
}
