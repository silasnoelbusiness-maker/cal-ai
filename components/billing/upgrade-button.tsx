"use client";

import { useTransition } from "react";
import { toast } from "sonner";
import { Button, type ButtonProps } from "@/components/ui/button";
import type { Plan } from "@prisma/client";

export function UpgradeButton({
  plan,
  children,
  variant,
}: {
  plan: Plan;
  children: React.ReactNode;
  variant?: ButtonProps["variant"];
}) {
  const [pending, startTransition] = useTransition();

  function handleClick() {
    startTransition(async () => {
      try {
        const res = await fetch("/api/stripe/checkout", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ plan }),
        });
        const data = await res.json();
        if (!res.ok || !data.url) {
          toast.error(data.error || "Couldn't start checkout.");
          return;
        }
        window.location.href = data.url;
      } catch {
        toast.error("Billing is temporarily unavailable.");
      }
    });
  }

  return (
    <Button variant={variant} loading={pending} onClick={handleClick} className="w-full">
      {children}
    </Button>
  );
}
