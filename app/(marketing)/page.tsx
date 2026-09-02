import type { Metadata } from "next";
import { HeroSection } from "@/components/marketing/hero-section";
import { ProblemSection } from "@/components/marketing/problem-section";
import { ProductDemoSection } from "@/components/marketing/product-demo-section";
import { LeadSourcesSection } from "@/components/marketing/lead-sources-section";
import { SolutionSection } from "@/components/marketing/solution-section";
import { ProductClaritySection } from "@/components/marketing/product-clarity-section";
import { DashboardPreviewSection } from "@/components/marketing/dashboard-preview-section";
import { AiConversationSection } from "@/components/marketing/ai-conversation-section";
import { TrustSection } from "@/components/marketing/trust-section";
import { RoiSection } from "@/components/marketing/roi-section";
import { PricingSection } from "@/components/marketing/pricing-section";
import { FaqSection, FAQ_PLAIN } from "@/components/marketing/faq-section";
import { FinalCtaSection } from "@/components/marketing/final-cta-section";

// Testimonials/case studies are deliberately NOT imported: the component
// exists but stays unmounted until real, attributable customer material is
// available. See components/marketing/testimonials-section.tsx.

export const metadata: Metadata = {
  // No `title` here on purpose: the root layout's `title.default` already
  // supplies the full homepage title. Setting one here would instead run
  // through `title.template` ("%s — Converana") and duplicate the brand
  // name in the browser tab and search results.
  description:
    "Converana answers new and missed leads for home-service businesses, qualifies them with AI, and alerts your team when a lead is ready to book. No credit card required.",
  alternates: { canonical: "/" },
};

/**
 * Structured data. Only facts stated elsewhere on the page — no aggregate
 * rating, no review count, no customer numbers. Google penalises invented
 * review markup, and we have no reviews to mark up.
 */
function StructuredData() {
  const faq = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: FAQ_PLAIN.map((f) => ({
      "@type": "Question",
      name: f.question,
      acceptedAnswer: { "@type": "Answer", text: f.answer },
    })),
  };

  return (
    <script
      type="application/ld+json"
      // Serialized from a literal above; no user input reaches this.
      dangerouslySetInnerHTML={{ __html: JSON.stringify(faq) }}
    />
  );
}

export default function HomePage() {
  return (
    <>
      <StructuredData />
      <HeroSection />
      <ProblemSection />
      <ProductDemoSection />
      <LeadSourcesSection />
      <SolutionSection />
      <ProductClaritySection />
      <DashboardPreviewSection />
      <AiConversationSection />
      <TrustSection />
      <RoiSection />
      <PricingSection />
      <FaqSection />
      <FinalCtaSection />
    </>
  );
}
