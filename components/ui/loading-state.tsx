import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

export function LoadingState({
  label = "Loading…",
  className,
}: {
  label?: string;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center gap-2 py-14 text-sm text-muted",
        className
      )}
    >
      <Loader2 className="h-5 w-5 animate-spin text-brand" />
      <span>{label}</span>
    </div>
  );
}

export function TableSkeleton({ rows = 6, cols = 5 }: { rows?: number; cols?: number }) {
  return (
    <div className="w-full space-y-3 p-4">
      {Array.from({ length: rows }).map((_, r) => (
        <div key={r} className="flex gap-4">
          {Array.from({ length: cols }).map((__, c) => (
            <div key={c} className="skeleton h-4 flex-1 rounded" />
          ))}
        </div>
      ))}
    </div>
  );
}
