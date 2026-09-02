import { Card } from "@/components/ui/card";
import { Avatar } from "@/components/ui/avatar";

/**
 * ─────────────────────────────────────────────────────────────────────────
 *  DISABLED — DO NOT RENDER UNTIL REAL CUSTOMER MATERIAL EXISTS
 *
 *  Built ready so that adding genuine social proof later is a data change,
 *  not a design job. It is deliberately NOT mounted on any page: rendering
 *  invented testimonials would be lying to prospects, and a fabricated
 *  quote attributed to a named business is the kind of thing that gets an
 *  ad account pulled.
 *
 *  TO ACTIVATE:
 *   1. Collect real, attributable quotes with the customer's written
 *      permission to publish their name and business.
 *   2. Put them in TESTIMONIALS below.
 *   3. Import <TestimonialsSection /> into app/(marketing)/page.tsx.
 *
 *  The component renders nothing while the list is empty, so a mistaken
 *  import can't produce an empty section either.
 * ─────────────────────────────────────────────────────────────────────────
 */

export interface Testimonial {
  /** Exact words the customer approved. Never paraphrased, never generated. */
  quote: string;
  name: string;
  business: string;
  /** e.g. "HVAC · Austin, TX" */
  detail?: string;
}

/** Intentionally empty. See the note above before adding anything. */
export const TESTIMONIALS: Testimonial[] = [];

export function TestimonialsSection() {
  if (TESTIMONIALS.length === 0) return null;

  return (
    <section className="border-t border-border bg-background py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <h2 className="text-center text-3xl font-semibold tracking-tight text-foreground">
          What operators say
        </h2>
        <div className="mt-12 grid gap-5 md:grid-cols-3">
          {TESTIMONIALS.map((t) => (
            <Card key={`${t.name}-${t.business}`} className="flex min-w-0 flex-col p-6">
              <blockquote className="flex-1 text-sm leading-relaxed text-foreground">
                “{t.quote}”
              </blockquote>
              <figcaption className="mt-5 flex items-center gap-3">
                <Avatar name={t.name} className="h-9 w-9 text-xs" />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-foreground">{t.name}</p>
                  <p className="truncate text-xs text-muted">
                    {t.business}
                    {t.detail ? ` · ${t.detail}` : ""}
                  </p>
                </div>
              </figcaption>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
}

/**
 * Same rules as above: a case study goes live only when a real customer has
 * agreed to the numbers being published. Empty until then.
 */
export interface CaseStudy {
  business: string;
  trade: string;
  summary: string;
  /** Figures the customer confirmed. Never estimated on their behalf. */
  metrics: { label: string; value: string }[];
}

export const CASE_STUDIES: CaseStudy[] = [];
