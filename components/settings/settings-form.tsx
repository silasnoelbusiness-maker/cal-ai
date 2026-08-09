"use client";

import { useActionState, useEffect, useRef } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export interface SettingsFormState {
  error?: string;
  success?: string;
}

/**
 * Shared wrapper for settings forms: submits via a server action, toasts
 * on success/error, and disables the save button while pending.
 */
export function SettingsForm({
  action,
  children,
  className,
  submitLabel = "Save changes",
}: {
  action: (prevState: SettingsFormState, formData: FormData) => Promise<SettingsFormState>;
  children: React.ReactNode;
  className?: string;
  submitLabel?: string;
}) {
  const [state, formAction, pending] = useActionState(action, {} as SettingsFormState);
  const lastHandled = useRef<SettingsFormState | null>(null);

  useEffect(() => {
    if (state === lastHandled.current) return;
    lastHandled.current = state;
    if (state.success) toast.success(state.success);
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <form action={formAction} className={cn("space-y-6", className)}>
      {children}
      <div className="flex justify-end border-t border-border pt-5">
        <Button type="submit" loading={pending}>
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}
