"use client";

import { useEffect, useRef, useState } from "react";
import { Bell, Flame, MessageSquareText, Sparkles, Upload } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/ui/avatar";
import { cn } from "@/lib/utils";

/**
 * "See Converana Recover a Lead" — a step-through of the real workflow,
 * rendered with the same primitives the dashboard uses.
 *
 * Every step maps to code that runs: capture (lib/leads/create-lead.ts),
 * the AI reply (lib/ai/reply.ts), one-question-at-a-time (lib/ai/prompt.ts),
 * classification (lib/ai/qualify.ts), and the notification
 * (lib/notifications). The conversation shown is illustrative — it is not a
 * transcript from a customer account, and the caption says so.
 *
 * Advances on its own so the section demonstrates itself, but stops the
 * moment someone takes control, and never animates for visitors who asked
 * for reduced motion.
 */

interface Step {
  label: string;
  title: string;
  body: string;
  icon: typeof Sparkles;
}

const STEPS: Step[] = [
  {
    label: "Lead arrives",
    title: "A lead comes in — or you import one you already had",
    body: "From your website form, the lead capture API, an inbound text, or a CSV of leads sitting in your old system.",
    icon: Upload,
  },
  {
    label: "Converana replies",
    title: "It answers straight away",
    body: "Before anyone on your team has looked at it. No lead sits unanswered because you were on a roof or under a sink.",
    icon: MessageSquareText,
  },
  {
    label: "AI qualifies",
    title: "One useful question at a time",
    body: "It asks what the job involves, where it is, and how soon they need it — using the services and details you configured, never a generic script.",
    icon: Sparkles,
  },
  {
    label: "Intent scored",
    title: "The lead is classified by intent and urgency",
    body: "Hot, warm or cold, with a short summary of what the customer actually wants and what to do next.",
    icon: Flame,
  },
  {
    label: "You're notified",
    title: "You hear about it when it's worth your time",
    body: "A notification when a lead is hot or needs a person. You confirm the appointment — Converana never books your calendar for you.",
    icon: Bell,
  },
];

const AUTO_ADVANCE_MS = 4200;

export function ProductDemoSection() {
  const [active, setActive] = useState(0);
  const [paused, setPaused] = useState(false);
  const sectionRef = useRef<HTMLElement>(null);

  useEffect(() => {
    if (paused) return;
    if (typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }
    const timer = window.setInterval(
      () => setActive((i) => (i + 1) % STEPS.length),
      AUTO_ADVANCE_MS
    );
    return () => window.clearInterval(timer);
  }, [paused]);

  function select(index: number) {
    setActive(index);
    setPaused(true); // Someone is driving now; stop moving under them.
  }

  return (
    <section
      id="product"
      ref={sectionRef}
      className="scroll-mt-20 border-t border-border bg-surface py-20 sm:py-24"
    >
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            See Converana recover a lead
          </h2>
          <p className="mt-4 text-lg text-muted">
            The same five steps run on every lead you get, whether it came in this morning or has
            been sitting in a spreadsheet since last year.
          </p>
        </div>

        <div className="mt-12 grid gap-8 lg:grid-cols-5 lg:items-start">
          {/* Steps */}
          <ol className="lg:col-span-2" role="tablist" aria-label="How Converana recovers a lead">
            {STEPS.map((step, i) => {
              const Icon = step.icon;
              const current = i === active;
              return (
                <li key={step.label}>
                  <button
                    type="button"
                    role="tab"
                    aria-selected={current}
                    aria-controls="demo-panel"
                    id={`demo-tab-${i}`}
                    onClick={() => select(i)}
                    className={cn(
                      "flex w-full gap-3 rounded-lg border p-4 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2",
                      current
                        ? "border-brand bg-brand/[0.04]"
                        : "border-transparent hover:bg-muted-surface"
                    )}
                  >
                    <span
                      className={cn(
                        "flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-semibold",
                        current ? "bg-brand text-brand-foreground" : "bg-muted-surface text-muted"
                      )}
                      aria-hidden
                    >
                      {i + 1}
                    </span>
                    <span className="min-w-0">
                      <span className="flex items-center gap-1.5 text-sm font-semibold text-foreground">
                        <Icon className="h-3.5 w-3.5 text-brand" aria-hidden />
                        {step.title}
                      </span>
                      <span className="mt-1 block text-sm text-muted">{step.body}</span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ol>

          {/* Panel */}
          <div
            id="demo-panel"
            role="tabpanel"
            aria-labelledby={`demo-tab-${active}`}
            className="lg:col-span-3"
          >
            <Card className="overflow-hidden p-4 sm:p-5">
              <DemoStage active={active} />
            </Card>
            <p className="mt-3 text-xs text-muted">
              Illustrative conversation shown in the real Converana interface. Not a transcript from
              a customer account.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

/** The right-hand panel, built from the same pieces as the dashboard. */
function DemoStage({ active }: { active: number }) {
  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-3 border-b border-border pb-3">
        <div className="flex items-center gap-2.5">
          <Avatar name="Marcus Yu" className="h-8 w-8 text-[11px]" />
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-foreground">Marcus Yu</p>
            <p className="truncate text-xs text-muted">
              AC Repair · {active === 0 ? "Imported from CSV" : "Website form"}
            </p>
          </div>
        </div>
        {active >= 3 ? (
          <Badge variant="hot">
            <Flame className="h-3 w-3" aria-hidden /> Hot
          </Badge>
        ) : (
          <Badge variant="secondary">New</Badge>
        )}
      </div>

      <div className="min-h-56 space-y-2 text-sm">
        <Bubble side="customer" show={active >= 0}>
          My AC stopped working. Can someone come tomorrow?
        </Bubble>
        <Bubble side="ai" show={active >= 1}>
          Sorry to hear that — I can get someone on it. Is this for a home or a business?
        </Bubble>
        <Bubble side="customer" show={active >= 2}>
          Home. Single storey, unit&apos;s about 8 years old.
        </Bubble>
        <Bubble side="ai" show={active >= 2}>
          Thanks. What ZIP code is the property in?
        </Bubble>
        <Bubble side="customer" show={active >= 3}>
          78704. It&apos;s pretty hot in here, honestly.
        </Bubble>

        {active >= 3 && (
          <div className="rounded-lg border border-border bg-muted-surface/60 p-3">
            <p className="mb-2 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-muted">
              <Sparkles className="h-3.5 w-3.5 text-brand" aria-hidden /> AI qualification
            </p>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
              <Row label="Intent" value="AC repair — no cooling" />
              <Row label="Urgency" value="High" />
              <Row label="Location" value="78704" />
              <Row label="Temperature" value="Hot" />
            </dl>
          </div>
        )}

        {active >= 4 && (
          <div className="flex items-center gap-2.5 rounded-lg border border-brand/30 bg-brand/[0.05] p-3">
            <Bell className="h-4 w-4 shrink-0 text-brand" aria-hidden />
            <p className="text-xs text-foreground">
              <span className="font-medium">Hot lead — Marcus Yu.</span> Ready to book. Confirm a
              time to close it out.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

function Bubble({
  side,
  show,
  children,
}: {
  side: "customer" | "ai";
  show: boolean;
  children: React.ReactNode;
}) {
  if (!show) return null;
  return (
    <div
      className={cn(
        "max-w-[85%] rounded-lg px-3 py-2 text-foreground transition-opacity",
        side === "customer"
          ? "ml-auto rounded-tr-sm bg-muted-surface"
          : "mr-auto rounded-tl-sm bg-brand/10"
      )}
    >
      {children}
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-muted">{label}</dt>
      <dd className="font-medium text-foreground">{value}</dd>
    </>
  );
}
