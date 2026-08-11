import { Zap, MessageCircleQuestion, BellRing } from "lucide-react";

const POINTS = [
  {
    icon: Zap,
    title: "Responds quickly",
    description: "New leads get an immediate reply, day or night — before a competitor can.",
  },
  {
    icon: MessageCircleQuestion,
    title: "Asks the right questions",
    description: "AI gathers the details your team needs: service, location, timing, and urgency.",
  },
  {
    icon: BellRing,
    title: "Follows up automatically",
    description: "Quiet leads get context-aware follow-ups instead of falling through the cracks.",
  },
];

export function SolutionSection() {
  return (
    <section className="bg-background py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            Converana follows up automatically.
          </h2>
          <p className="mt-4 text-lg text-muted">
            Converana responds quickly, asks qualifying questions, follows up when customers go
            quiet, and alerts your business the moment a lead is ready.
          </p>
        </div>

        <div className="mx-auto mt-14 grid max-w-4xl gap-6 sm:grid-cols-3">
          {POINTS.map((point) => (
            <div key={point.title} className="rounded-xl border border-border bg-surface p-6">
              <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-brand/10 text-brand">
                <point.icon className="h-5 w-5" />
              </div>
              <h3 className="font-semibold text-foreground">{point.title}</h3>
              <p className="mt-1.5 text-sm leading-relaxed text-muted">{point.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
