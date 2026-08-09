import { PlugZap, BrainCircuit, CalendarCheck } from "lucide-react";

const STEPS = [
  {
    number: "01",
    icon: PlugZap,
    title: "Capture",
    description: "Connect your lead sources — your website form, embed widget, or API.",
  },
  {
    number: "02",
    icon: BrainCircuit,
    title: "Qualify",
    description: "AI communicates with the lead and identifies intent, urgency, and fit.",
  },
  {
    number: "03",
    icon: CalendarCheck,
    title: "Convert",
    description: "Your team receives qualified leads and books the appointment.",
  },
];

export function HowItWorksSection() {
  return (
    <section id="how-it-works" className="scroll-mt-16 border-t border-border bg-surface py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">How it works</h2>
          <p className="mt-4 text-lg text-muted">
            Three steps between a missed lead and a booked customer.
          </p>
        </div>

        <div className="mx-auto mt-14 grid max-w-4xl gap-8 sm:grid-cols-3">
          {STEPS.map((step) => (
            <div key={step.number} className="relative rounded-xl border border-border bg-background p-6">
              <span className="text-xs font-semibold text-brand">{step.number}</span>
              <div className="mt-3 mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-brand/10 text-brand">
                <step.icon className="h-5 w-5" />
              </div>
              <h3 className="font-semibold text-foreground">{step.title}</h3>
              <p className="mt-1.5 text-sm leading-relaxed text-muted">{step.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
