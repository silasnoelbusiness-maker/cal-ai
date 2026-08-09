"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { toggleLeadOptOutAction } from "@/app/dashboard/leads/actions";

export function OptOutToggle({ leadId, optedOut }: { leadId: string; optedOut: boolean }) {
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        startTransition(async () => {
          await toggleLeadOptOutAction(leadId, !optedOut);
          toast.success(optedOut ? "Opt-out removed" : "Lead marked as opted out");
          router.refresh();
        })
      }
      className="disabled:opacity-60"
    >
      <Badge variant={optedOut ? "danger" : "outline"}>
        {optedOut ? "Opted out — click to re-enable" : "Mark as opted out"}
      </Badge>
    </button>
  );
}
