"use client";

import { useTransition } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { deleteLeadAction } from "@/app/dashboard/leads/actions";

export function DeleteLeadButton({ leadId, leadName }: { leadId: string; leadName: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="outline"
      size="sm"
      className="text-danger hover:bg-danger-surface"
      loading={pending}
      onClick={() => {
        if (!window.confirm(`Delete ${leadName}? This can't be undone.`)) return;
        startTransition(() => deleteLeadAction(leadId));
      }}
    >
      <Trash2 className="h-4 w-4" />
      Delete
    </Button>
  );
}
