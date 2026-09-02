import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ProductPreview } from "./product-preview";
import { DemoModalTrigger } from "./demo-modal";

export function HeroSection() {
  return (
    <section className="relative overflow-hidden bg-background">
      <div className="mx-auto grid max-w-6xl gap-12 px-4 py-16 sm:px-6 sm:py-24 lg:grid-cols-2 lg:items-center lg:py-28">
        <div>
          <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-border bg-surface px-3 py-1 text-xs font-medium text-muted">
            Built for home-service businesses
          </div>
          {/* text-balance keeps the long headline from stranding a single word
              on its own line at 390px; font sizes are unchanged. */}
          <h1 className="text-balance text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">
            Turn Missed Leads Into Booked Jobs—Automatically.
          </h1>
          <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted">
            Converana responds to new and forgotten leads, qualifies them through AI-powered
            conversations, and alerts your team when they&apos;re ready to book.
          </p>
          <p className="mt-3 max-w-xl leading-relaxed text-muted">
            Already have a lead list? Import your CSV and start working those opportunities in
            minutes.
          </p>

          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            {/* Primary is the filled brand button at lg; the demo sits beside
                it as a quieter outline so the hierarchy is unambiguous. */}
            <Button size="lg" asChild className="shadow-sm">
              <Link href="/signup">
                Start Free
                <ArrowRight className="h-4 w-4" aria-hidden />
              </Link>
            </Button>
            <DemoModalTrigger />
          </div>

          <p className="mt-4 text-sm text-muted">
            No credit card required · Set up in minutes · Cancel anytime
          </p>
        </div>

        <div>
          <ProductPreview />
        </div>
      </div>
    </section>
  );
}
