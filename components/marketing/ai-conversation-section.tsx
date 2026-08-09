import { Flame, Sparkles } from "lucide-react";
import { Card } from "@/components/ui/card";

export function AiConversationSection() {
  return (
    <section className="border-t border-border bg-surface py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="grid gap-12 lg:grid-cols-2 lg:items-center">
          <div>
            <h2 className="text-3xl font-semibold tracking-tight text-foreground">
              A professional first response, every time.
            </h2>
            <p className="mt-4 text-lg text-muted">
              LeadLoop&apos;s AI assistant asks one useful question at a time, collects the
              details your team needs, and flags the lead the moment it&apos;s ready to book —
              without ever inventing prices or pretending to be human.
            </p>
            <ul className="mt-6 space-y-3 text-sm text-muted">
              <li className="flex gap-2">
                <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
                Understands the customer&apos;s need and urgency
              </li>
              <li className="flex gap-2">
                <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
                Collects location, timing, and contact details
              </li>
              <li className="flex gap-2">
                <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-brand" />
                Flags urgent or sensitive conversations for a human
              </li>
            </ul>
          </div>

          <Card className="p-5 sm:p-6">
            <div className="mb-4 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-brand/10 text-brand">
                  <Sparkles className="h-4 w-4" />
                </span>
                <div>
                  <p className="text-sm font-medium text-foreground">LeadLoop AI</p>
                  <p className="text-xs text-muted">Web chat · PeakFlow HVAC</p>
                </div>
              </div>
            </div>

            <div className="space-y-3">
              <Bubble from="customer">
                My AC stopped working. Can someone come tomorrow?
              </Bubble>
              <Bubble from="ai">
                Absolutely. We can help with AC repairs. What ZIP code is the property in?
              </Bubble>
              <Bubble from="customer">75201</Bubble>
              <Bubble from="ai">Thanks. Are you available in the morning or afternoon?</Bubble>
            </div>

            <div className="mt-5 flex items-center gap-2 rounded-lg bg-hot-surface px-3 py-2.5 text-sm font-semibold text-hot">
              <Flame className="h-4 w-4" />
              HOT LEAD
              <span className="ml-auto text-xs font-normal text-hot/80">Score: 91</span>
            </div>
          </Card>
        </div>
      </div>
    </section>
  );
}

function Bubble({ from, children }: { from: "customer" | "ai"; children: React.ReactNode }) {
  const isCustomer = from === "customer";
  return (
    <div className={`flex ${isCustomer ? "justify-start" : "justify-end"}`}>
      <div
        className={`max-w-[80%] rounded-lg px-3.5 py-2 text-sm leading-relaxed ${
          isCustomer
            ? "rounded-tl-sm bg-muted-surface text-foreground"
            : "rounded-tr-sm bg-brand/10 text-foreground"
        }`}
      >
        {children}
      </div>
    </div>
  );
}
