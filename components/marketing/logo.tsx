import { cn } from "@/lib/utils";

export function Logo({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2 select-none", className)}>
      <svg width="26" height="26" viewBox="0 0 32 32" fill="none" aria-hidden="true">
        <rect width="32" height="32" rx="8" fill="#2451E8" />
        {/* A "C" for Converana. The previous mark drew an "L", left over from
            the LeadLoop name — a wordmark reading "Converana" beside an "L"
            is the kind of detail that costs trust on a paid landing page. */}
        <path
          d="M21.2 11.4a7 7 0 1 0 0 9.2"
          stroke="white"
          strokeWidth="3.4"
          strokeLinecap="round"
          fill="none"
        />
      </svg>
      <span className="text-lg font-semibold tracking-tight text-foreground">Converana</span>
    </span>
  );
}
