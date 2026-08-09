"use client";

import { useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";

export function ManageBillingButton() {
  const [pending, startTransition] = useTransition();

  function handleClick() {
    startTransition(async () => {
      try {
        const res = await fetch("/api/stripe/portal", { method: "POST" });
        const data = await res.json();
        if (!res.ok || !data.url) {
          toast.error(data.error || "Couldn't open the billing portal.");
          return;
        }
        window.location.href = data.url;
      } catch {
        toast.error("Billing is temporarily unavailable.");
      }
    });
  }

  return (
    <Button variant="outline" loading={pending} onClick={handleClick}>
      Manage subscription
    </Button>
  );
}
