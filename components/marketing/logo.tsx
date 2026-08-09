import { cn } from "@/lib/utils";

export function Logo({ className }: { className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2 select-none", className)}>
      <svg width="26" height="26" viewBox="0 0 32 32" fill="none" aria-hidden="true">
        <rect width="32" height="32" rx="8" fill="#2451E8" />
        <path d="M9 21.5V10h3.2v8.7h6.4v2.8H9Z" fill="white" />
        <path d="M22.6 12.3a3 3 0 1 1-4.9-2.4 3 3 0 0 1 4.9 2.4Z" fill="white" fillOpacity="0.55" />
      </svg>
      <span className="text-lg font-semibold tracking-tight text-foreground">LeadLoop</span>
    </span>
  );
}
