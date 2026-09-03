import { Flame, Calendar, TrendingUp, Sparkles } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/ui/avatar";

/**
 * A real (non-screenshot) preview of the Converana dashboard, built from the
 * same UI primitives as the app itself. Illustrative data only.
 *
 * Labels stop at "Ready to book" and "Qualified" on purpose. Converana
 * qualifies a lead and notifies the business; it never writes to anyone's
 * calendar. A mock-up implying the calendar was filled automatically would
 * promise something the product deliberately does not do.
 */
export function ProductPreview() {
  return (
    <div className="relative rounded-xl border border-border bg-surface p-3 shadow-2xl shadow-slate-900/10 sm:p-4">
      <div className="mb-3 flex items-center gap-1.5 px-1">
        <span className="h-2.5 w-2.5 rounded-full bg-danger/40" />
        <span className="h-2.5 w-2.5 rounded-full bg-warning/40" />
        <span className="h-2.5 w-2.5 rounded-full bg-success/40" />
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <MiniMetric label="New leads" value="24" />
        <MiniMetric label="Qualified" value="11" />
        <MiniMetric label="Ready to book" value="7" />
        <MiniMetric label="Follow-ups" value="18" emphasize />
      </div>

      <div className="mt-3 grid gap-3 lg:grid-cols-5">
        <Card className="p-4 lg:col-span-3">
          <div className="mb-3 flex items-center justify-between">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">
              Lead pipeline
            </p>
            <Badge variant="hot" className="text-[10px]">
              <Flame className="h-3 w-3" />
              1 hot
            </Badge>
          </div>
          <div className="space-y-2.5">
            <LeadRow name="Marcus Yu" service="AC Repair" temp="hot" />
            <LeadRow name="Dana Price" service="Roof Inspection" temp="warm" />
            <LeadRow name="Chris Ibe" service="Water Heater" temp="cold" />
          </div>
        </Card>

        <Card className="flex flex-col p-4 lg:col-span-2">
          <div className="mb-2 flex items-center gap-1.5">
            <Sparkles className="h-3.5 w-3.5 text-brand" />
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">
              AI conversation
            </p>
          </div>
          <div className="flex-1 space-y-2 text-xs">
            <div className="ml-auto max-w-[85%] rounded-lg rounded-tr-sm bg-muted-surface px-2.5 py-1.5 text-foreground">
              My AC stopped working. Can someone come tomorrow?
            </div>
            <div className="mr-auto max-w-[90%] rounded-lg rounded-tl-sm bg-brand/10 px-2.5 py-1.5 text-foreground">
              Absolutely — what ZIP code is the property in?
            </div>
          </div>
          <div className="mt-3 flex items-center gap-2 rounded-md bg-hot-surface px-2.5 py-1.5 text-xs font-medium text-hot">
            <Flame className="h-3.5 w-3.5" /> HOT LEAD
          </div>
        </Card>
      </div>

      <Card className="mt-3 flex items-center justify-between p-3.5">
        <div className="flex items-center gap-2.5">
          <div className="flex h-8 w-8 items-center justify-center rounded-md bg-success-surface text-success">
            <Calendar className="h-4 w-4" />
          </div>
          <div>
            <p className="text-xs font-medium text-foreground">Ready to book</p>
            <p className="text-[11px] text-muted">Marcus Yu · Confirm a time</p>
          </div>
        </div>
        <div className="flex items-center gap-1 text-xs font-medium text-success">
          <TrendingUp className="h-3.5 w-3.5" aria-hidden />
          Qualified
        </div>
      </Card>
    </div>
  );
}

/**
 * A single counter in the preview's metric row.
 *
 * Counts only — no growth percentages. These numbers illustrate what the
 * product tracks; a "+31%" beside them would read as a result Converana
 * produced for a real customer, which is a claim we can't stand behind.
 */
function MiniMetric({
  label,
  value,
  emphasize,
}: {
  label: string;
  value: string;
  emphasize?: boolean;
}) {
  return (
    <div
      className={`rounded-lg border border-border px-3 py-2.5 ${emphasize ? "bg-brand/[0.05]" : "bg-surface"}`}
    >
      <p className="truncate text-[10px] font-medium uppercase tracking-wide text-muted">{label}</p>
      <p className="mt-0.5 text-base font-semibold text-foreground">{value}</p>
    </div>
  );
}

function LeadRow({
  name,
  service,
  temp,
}: {
  name: string;
  service: string;
  temp: "hot" | "warm" | "cold";
}) {
  const tempColor =
    temp === "hot" ? "bg-hot" : temp === "warm" ? "bg-warm" : "bg-cold";
  return (
    <div className="flex items-center gap-2.5">
      <Avatar name={name} className="h-7 w-7 text-[10px]" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-xs font-medium text-foreground">{name}</p>
        <p className="truncate text-[11px] text-muted">{service}</p>
      </div>
      <span className={`h-2 w-2 shrink-0 rounded-full ${tempColor}`} />
    </div>
  );
}
