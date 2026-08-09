"use client";

import { useTransition } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { revokeApiKeyAction } from "@/app/dashboard/settings/api-keys/actions";

export function RevokeApiKeyButton({ keyId, keyName }: { keyId: string; keyName: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="ghost"
      size="sm"
      className="text-danger hover:bg-danger-surface"
      disabled={pending}
      onClick={() => {
        if (!window.confirm(`Revoke "${keyName}"? Any integration using it will stop working.`)) return;
        startTransition(async () => {
          await revokeApiKeyAction(keyId);
          toast.success("API key revoked");
        });
      }}
    >
      <Trash2 className="h-3.5 w-3.5" />
      Revoke
    </Button>
  );
}
