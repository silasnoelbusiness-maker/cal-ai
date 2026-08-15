import Link from "next/link";
import { ArrowRight, PlayCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { ProductPreview } from "./product-preview";

export function HeroSection() {
  return (
    <section className="relative overflow-hidden bg-background">
      <div className="mx-auto grid max-w-6xl gap-12 px-4 py-16 sm:px-6 sm:py-24 lg:grid-cols-2 lg:items-center lg:py-28">
        <div>
          <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-border bg-surface px-3 py-1 text-xs font-medium text-muted">
            Built for home service businesses
          </div>
          {/* text-balance only — same font sizes and spacing as before. The
              longer headline would otherwise leave a one-word last line on a
              narrow phone. */}
          <h1 className="text-balance text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">
            Stop Losing Money on Leads You Already Paid For.
          </h1>
          <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted">
            Converana automatically follows up with new and missed leads, qualifies them with AI,
            and helps turn more conversations into booked customers.
          </p>
          <p className="mt-3 max-w-xl leading-relaxed text-muted">
            Already have a lead list? Import your CSV and start working those opportunities in
            minutes.
          </p>
          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <Button size="lg" asChild>
              <Link href="/signup">
                Start Free
                <ArrowRight className="h-4 w-4" />
              </Link>
            </Button>
            <Button size="lg" variant="outline" asChild>
              <Link href="#how-it-works">
                <PlayCircle className="h-4 w-4" />
                See How It Works
              </Link>
            </Button>
          </div>
          <p className="mt-4 text-sm text-muted">No credit card required.</p>
        </div>

        <div>
          <ProductPreview />
        </div>
      </div>
    </section>
  );
}
