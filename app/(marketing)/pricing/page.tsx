import type { Metadata } from "next";
import Link from "next/link";
import { PricingSection } from "@/components/marketing/pricing-section";
import { FinalCtaSection } from "@/components/marketing/final-cta-section";

export const metadata: Metadata = {
  title: "Pricing",
  description:
    "Starter, Growth and Pro plans for Converana. Every plan includes every feature — only the monthly lead and AI message allowances differ. No credit card required to start.",
  alternates: { canonical: "/pricing" },
};

export default function PricingPage() {
  return (
    <>
      <div className="mx-auto max-w-3xl px-4 pb-4 pt-16 text-center sm:px-6 sm:pt-24">
        <h1 className="text-4xl font-semibold tracking-tight text-foreground">
          Simple, transparent pricing
        </h1>
        <p className="mt-4 text-lg text-muted">
          Every plan includes every feature. The only thing that changes is how much you can run
          through it each month. Billed monthly, cancel anytime — no long-term contracts.
        </p>
      </div>
      <div className="pb-8">
        <PricingSection compact />
      </div>
      <div className="mx-auto max-w-3xl px-4 pb-16 text-center text-sm text-muted sm:px-6">
        Need more leads, users, or AI messages than Pro allows?{" "}
        <Link href="mailto:hello@converana.com" className="text-brand hover:underline">
          Talk to us
        </Link>{" "}
        about a custom plan.
      </div>
      <FinalCtaSection />
    </>
  );
}
