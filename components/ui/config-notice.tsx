import { AlertTriangle } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Standard "this feature needs configuration" banner. Used whenever an
 * external service (Supabase, Anthropic, Stripe, Twilio, Resend) has no
 * credentials configured — the app should degrade gracefully, never crash.
 */
export function ConfigNotice({
  title,
  description,
  className,
}: {
  title: string;
  description: string;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex items-start gap-3 rounded-lg border border-warning/30 bg-warning-surface px-4 py-3 text-sm",
        className
      )}
      role="status"
    >
      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
      <div>
        <p className="font-medium text-foreground">{title}</p>
        <p className="mt-0.5 text-muted">{description}</p>
      </div>
    </div>
  );
}
