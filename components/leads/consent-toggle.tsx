"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { setLeadConsentAction } from "@/app/dashboard/leads/actions";

const LABELS = { sms: "SMS", email: "Email" } as const;

/**
 * Records consent for one channel on one lead.
 *
 * Leads that arrive by CSV import carry no consent, by design — nothing can
 * be sent to them until a business confirms it has permission. This is how
 * that confirmation is given: explicitly, per lead, by a human.
 */
export function ConsentToggle({
  leadId,
  channel,
  granted,
}: {
  leadId: string;
  channel: "sms" | "email";
  granted: boolean;
}) {
  const [pending, startTransition] = useTransition();
  const router = useRouter();
  const label = LABELS[channel];

  return (
    <button
      type="button"
      disabled={pending}
      title={
        granted
          ? `Withdraw ${label.toLowerCase()} consent for this lead`
          : `Only record consent if this lead agreed to be contacted by ${label.toLowerCase()}`
      }
      onClick={() =>
        startTransition(async () => {
          await setLeadConsentAction(leadId, channel, !granted);
          toast.success(granted ? `${label} consent withdrawn` : `${label} consent recorded`);
          router.refresh();
        })
      }
      className="disabled:opacity-60"
    >
      <Badge variant={granted ? "success" : "outline"}>
        {label} consent {granted ? "granted" : "not on file"}
      </Badge>
    </button>
  );
}
