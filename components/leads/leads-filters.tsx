"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { cn } from "@/lib/utils";
import { LEAD_FILTERS, type LeadFilter } from "@/lib/leads/query";

const LABELS: Record<LeadFilter, string> = {
  all: "All",
  new: "New",
  hot: "Hot",
  warm: "Warm",
  cold: "Cold",
  qualified: "Qualified",
  appointment: "Appointment",
  converted: "Converted",
  lost: "Lost",
};

export function LeadsFilters({ counts }: { counts: Partial<Record<LeadFilter, number>> }) {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const current = (searchParams.get("filter") || "all").toLowerCase();

  return (
    <div className="flex gap-1.5 overflow-x-auto scrollbar-thin pb-1">
      {LEAD_FILTERS.map((filter) => {
        const params = new URLSearchParams(searchParams.toString());
        if (filter === "all") params.delete("filter");
        else params.set("filter", filter);
        params.delete("page");
        const href = `${pathname}${params.toString() ? `?${params.toString()}` : ""}`;
        const active = current === filter;
        const count = counts[filter];

        return (
          <Link
            key={filter}
            href={href}
            className={cn(
              "shrink-0 whitespace-nowrap rounded-full border px-3 py-1.5 text-sm font-medium transition-colors",
              active
                ? "border-brand bg-brand text-brand-foreground"
                : "border-border bg-surface text-muted hover:bg-muted-surface"
            )}
          >
            {LABELS[filter]}
            {typeof count === "number" && <span className="ml-1.5 opacity-70">{count}</span>}
          </Link>
        );
      })}
    </div>
  );
}
