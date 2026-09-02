import Link from "next/link";
import type { Metadata } from "next";
import { FileSpreadsheet, LayoutTemplate, Sparkles, BellRing } from "lucide-react";
import { SignupForm } from "@/components/auth/signup-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { isSupabaseConfigured } from "@/lib/auth/config";
import { PlanSummary, NoPlanSelectedNote, parsePlanParam } from "@/components/auth/plan-summary";

export const metadata: Metadata = {
  title: "Start free",
  description:
    "Create your Converana account. No credit card required — set up your business and connect a lead source before choosing a plan.",
};

/**
 * Benefits shown beside the form. Each is something the product does today:
 * CSV import (lib/leads/import), the embeddable form (app/embed), AI
 * qualification (lib/ai/qualify.ts) and notifications (lib/notifications).
 */
const BENEFITS = [
  {
    icon: FileSpreadsheet,
    title: "Import the leads you already have",
    body: "Upload a CSV from your old CRM. Duplicates are skipped, and nothing is messaged until you say so.",
  },
  {
    icon: LayoutTemplate,
    title: "Connect your website form",
    body: "One line of HTML and every enquiry lands in Converana automatically.",
  },
  {
    icon: Sparkles,
    title: "Let AI qualify what comes in",
    body: "It replies straight away, asks the questions you'd ask, and scores intent and urgency.",
  },
  {
    icon: BellRing,
    title: "Get told when a lead is ready",
    body: "A notification when someone is hot or needs a person — not a feed you have to watch.",
  },
];

export default async function SignupPage({ searchParams }: PageProps<"/signup">) {
  const params = await searchParams;
  const plan = parsePlanParam(params.plan);

  return (
    <div className="grid w-full gap-10 lg:grid-cols-2 lg:gap-16">
      {/* Left: context. Hidden from the tab order on mobile is wrong, so it
          simply stacks below the form instead. */}
      <div className="order-2 lg:order-1">
        <h2 className="text-2xl font-semibold tracking-tight text-foreground">
          Set up in minutes, not a weekend.
        </h2>
        <p className="mt-2 text-sm leading-relaxed text-muted">
          After you create your account you&apos;ll tell Converana about your business and services,
          then connect a lead source. You can import an existing list straight away.
        </p>

        <ul className="mt-7 space-y-5">
          {BENEFITS.map((benefit) => {
            const Icon = benefit.icon;
            return (
              <li key={benefit.title} className="flex min-w-0 gap-3">
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-brand/10 text-brand">
                  <Icon className="h-4 w-4" aria-hidden />
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-medium text-foreground">{benefit.title}</p>
                  <p className="mt-0.5 text-sm text-muted">{benefit.body}</p>
                </div>
              </li>
            );
          })}
        </ul>

        <div className="mt-8">{plan ? <PlanSummary plan={plan} /> : <NoPlanSelectedNote />}</div>
      </div>

      {/* Right: the form. First in source order so it's first on mobile and
          first for a keyboard or screen reader user. */}
      <div className="order-1 lg:order-2">
        <div className="mx-auto w-full max-w-sm lg:mx-0">
          <div className="space-y-1.5 text-center lg:text-left">
            <h1 className="text-xl font-semibold text-foreground">Start recovering leads</h1>
            <p className="text-sm text-muted">No credit card required.</p>
          </div>

          {!isSupabaseConfigured && (
            <ConfigNotice
              className="mt-6"
              title="Authentication isn't configured"
              description="Set NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY to enable sign-up."
            />
          )}

          <div className="mt-6">
            <SignupForm plan={plan} />
          </div>

          <p className="mt-6 text-center text-sm text-muted lg:text-left">
            Already have an account?{" "}
            <Link href="/login" className="font-medium text-brand hover:underline">
              Log in
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
