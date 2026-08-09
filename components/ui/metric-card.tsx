import type { LucideIcon } from "lucide-react";
import { ArrowDown, ArrowUp } from "lucide-react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export function MetricCard({
  label,
  value,
  icon: Icon,
  change,
  changeLabel = "vs last month",
  emphasize = false,
}: {
  label: string;
  value: string;
  icon?: LucideIcon;
  /** Percentage change, e.g. 12.4 or -8.1. Omit when there's no prior-period baseline. */
  change?: number | null;
  changeLabel?: string;
  emphasize?: boolean;
}) {
  const hasChange = typeof change === "number" && Number.isFinite(change);
  const positive = hasChange && change! > 0;
  const negative = hasChange && change! < 0;

  return (
    <Card
      className={cn(
        "p-5",
        emphasize && "border-brand/20 bg-gradient-to-br from-brand/[0.04] to-transparent"
      )}
    >
      <div className="flex items-start justify-between">
        <p className="text-sm font-medium text-muted">{label}</p>
        {Icon && (
          <div className="flex h-8 w-8 items-center justify-center rounded-md bg-muted-surface text-muted">
            <Icon className="h-4 w-4" />
          </div>
        )}
      </div>
      <p className="mt-2 text-2xl font-semibold tracking-tight text-foreground">{value}</p>
      {hasChange && (
        <div className="mt-2 flex items-center gap-1 text-xs">
          <span
            className={cn(
              "inline-flex items-center gap-0.5 font-medium",
              positive && "text-success",
              negative && "text-danger",
              !positive && !negative && "text-muted"
            )}
          >
            {positive && <ArrowUp className="h-3 w-3" />}
            {negative && <ArrowDown className="h-3 w-3" />}
            {Math.abs(change!).toFixed(1)}%
          </span>
          <span className="text-muted">{changeLabel}</span>
        </div>
      )}
    </Card>
  );
}
