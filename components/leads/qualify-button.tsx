"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";

export function QualifyButton({ leadId }: { leadId: string }) {
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  function run() {
    startTransition(async () => {
      try {
        const res = await fetch("/api/ai/qualify", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ leadId }),
        });
        const data = await res.json();
        if (!res.ok) {
          toast.error(data.error || "AI is temporarily unavailable.");
          return;
        }
        toast.success("Lead re-qualified");
        router.refresh();
      } catch {
        toast.error("AI is temporarily unavailable. You can still qualify this lead manually.");
      }
    });
  }

  return (
    <Button variant="outline" size="sm" loading={pending} onClick={run}>
      <Sparkles className="h-4 w-4" />
      Qualify with AI
    </Button>
  );
}
