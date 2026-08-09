import { Megaphone, PhoneMissed, UserX, TrendingDown } from "lucide-react";

const CHANNELS = ["Google Ads", "Facebook Ads", "SEO", "Website", "Referrals"];

export function ProblemSection() {
  return (
    <section className="border-t border-border bg-surface py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            You&apos;re already paying for the leads.
          </h2>
          <p className="mt-4 text-lg text-muted">
            Businesses spend real money generating leads through {CHANNELS.slice(0, -1).join(", ")}
            , and {CHANNELS[CHANNELS.length - 1]} — but many of those leads never receive a fast
            response.
          </p>
        </div>

        <div className="mx-auto mt-14 flex max-w-3xl flex-col items-center gap-3 sm:flex-row sm:justify-between">
          <ProblemStep icon={Megaphone} label="Lead comes in" />
          <Connector />
          <ProblemStep icon={PhoneMissed} label="Nobody responds" />
          <Connector />
          <ProblemStep icon={UserX} label="Customer contacts a competitor" />
          <Connector />
          <ProblemStep icon={TrendingDown} label="Revenue disappears" tone="danger" />
        </div>
      </div>
    </section>
  );
}

function Connector() {
  return (
    <div className="h-6 w-px bg-border sm:h-px sm:w-8" aria-hidden="true" />
  );
}

function ProblemStep({
  icon: Icon,
  label,
  tone = "default",
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  tone?: "default" | "danger";
}) {
  return (
    <div className="flex flex-col items-center gap-2 text-center">
      <div
        className={`flex h-11 w-11 items-center justify-center rounded-full ${
          tone === "danger" ? "bg-danger-surface text-danger" : "bg-muted-surface text-muted"
        }`}
      >
        <Icon className="h-5 w-5" />
      </div>
      <p className="max-w-[9rem] text-sm font-medium text-foreground">{label}</p>
    </div>
  );
}
