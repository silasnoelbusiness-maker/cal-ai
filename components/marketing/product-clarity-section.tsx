import { ShieldCheck } from "lucide-react";
import { Card } from "@/components/ui/card";
import { AI_GUARDRAILS, PRODUCT_ANSWERS } from "@/lib/marketing/product-facts";

/**
 * The plain-language answers to what a home-service owner actually wants to
 * know before signing up, plus the AI's stated limits.
 *
 * The limits are the credible half: anyone can promise capabilities, but
 * "it will never invent a price" is a rule someone can hold us to, and it is
 * a real line in lib/ai/prompt.ts rather than a marketing sentiment.
 */
export function ProductClaritySection() {
  return (
    <section
      id="how-it-works"
      className="scroll-mt-20 border-t border-border bg-surface py-20 sm:py-24"
    >
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            Exactly what Converana does
          </h2>
          <p className="mt-4 text-lg text-muted">
            No jargon. Here&apos;s how it behaves on a real job.
          </p>
        </div>

        <div className="mt-12 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
          {PRODUCT_ANSWERS.map((answer) => (
            <Card key={answer.title} className="min-w-0 p-5">
              <h3 className="text-sm font-semibold text-foreground">{answer.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted">{answer.body}</p>
            </Card>
          ))}
        </div>

        <div className="mt-14 rounded-xl border border-border bg-background p-6 sm:p-8">
          <div className="flex items-center gap-2">
            <ShieldCheck className="h-5 w-5 text-brand" aria-hidden />
            <h3 className="text-lg font-semibold text-foreground">What the AI will never do</h3>
          </div>
          <p className="mt-2 max-w-2xl text-sm text-muted">
            These aren&apos;t guidelines we hope it follows — they&apos;re instructions built into
            every conversation it has on your behalf.
          </p>
          <div className="mt-6 grid gap-5 sm:grid-cols-2">
            {AI_GUARDRAILS.map((rule) => (
              <div key={rule.title} className="min-w-0">
                <p className="text-sm font-semibold text-foreground">{rule.title}</p>
                <p className="mt-1 text-sm text-muted">{rule.body}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
