import * as React from "react";
import { cn } from "@/lib/utils";

export function Textarea({
  className,
  ref,
  ...props
}: React.ComponentProps<"textarea"> & { ref?: React.Ref<HTMLTextAreaElement> }) {
  return (
    <textarea
      ref={ref}
      className={cn(
        "flex min-h-[80px] w-full rounded-md border border-border bg-surface px-3 py-2 text-sm shadow-sm transition-colors placeholder:text-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-1 disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  );
}
