"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { createTestLeadAction } from "@/app/dashboard/leads/actions";

export function AddTestLeadButton() {
  const [pending, startTransition] = useTransition();
  const router = useRouter();

  return (
    <Button
      loading={pending}
      onClick={() =>
        startTransition(async () => {
          const result = await createTestLeadAction();
          if (result.ok) {
            toast.success("Test lead added");
            router.refresh();
          } else {
            toast.error(result.error || "Couldn't add a test lead.");
          }
        })
      }
    >
      <Plus className="h-4 w-4" />
      Add Test Lead
    </Button>
  );
}
