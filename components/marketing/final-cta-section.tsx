import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";

export function FinalCtaSection() {
  return (
    <section className="border-t border-border bg-foreground py-20 sm:py-24">
      <div className="mx-auto max-w-3xl px-4 text-center sm:px-6">
        <h2 className="text-balance text-3xl font-semibold tracking-tight text-white sm:text-4xl">
          Stop Letting Good Leads Go Cold.
        </h2>
        <p className="mt-4 text-lg text-white/70">
          Start responding to more leads and identify the opportunities that are ready to book.
        </p>
        <div className="mt-8 flex justify-center">
          <Button size="lg" asChild>
            <Link href="/signup">
              Start Recovering Leads
              <ArrowRight className="h-4 w-4" aria-hidden />
            </Link>
          </Button>
        </div>
        {/*
          The accurate version of "free": no card at signup and no trial clock,
          because lib/stripe/checkout.ts sets no trial_period_days and
          app/(auth)/actions.ts collects no payment details.
        */}
        <p className="mt-4 text-sm text-white/60">
          No credit card required to create your account. There&apos;s no time-limited trial —
          choose a plan when you&apos;re ready to go live.
        </p>
      </div>
    </section>
  );
}
