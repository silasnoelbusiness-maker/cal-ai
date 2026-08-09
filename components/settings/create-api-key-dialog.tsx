"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { Plus, TriangleAlert } from "lucide-react";
import { createApiKeyAction, type CreateApiKeyState } from "@/app/dashboard/settings/api-keys/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { CopyButton } from "@/components/ui/copy-button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
  DialogTrigger,
} from "@/components/ui/dialog";

const initialState: CreateApiKeyState = {};

export function CreateApiKeyDialog() {
  const [open, setOpen] = useState(false);
  const [state, formAction, pending] = useActionState(createApiKeyAction, initialState);
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.key) formRef.current?.reset();
  }, [state.key]);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
      }}
    >
      <DialogTrigger asChild>
        <Button>
          <Plus className="h-4 w-4" />
          New API key
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{state.key ? "API key created" : "Create API key"}</DialogTitle>
          {!state.key && (
            <DialogDescription>
              Use this key to send leads into LeadLoop from your website, CRM, or ad platform.
            </DialogDescription>
          )}
        </DialogHeader>

        {state.key ? (
          <div className="space-y-4">
            <div className="flex items-start gap-2 rounded-md bg-warning-surface px-3 py-2.5 text-sm text-foreground">
              <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
              <span>Copy this key now — you won&apos;t be able to see it again.</span>
            </div>
            <div className="flex items-center gap-2 rounded-md border border-border bg-muted-surface px-3 py-2.5 font-mono text-sm break-all">
              {state.key.plaintext}
            </div>
            <DialogFooter>
              <CopyButton value={state.key.plaintext} label="Copy key" variant="outline" />
              <Button onClick={() => setOpen(false)}>Done</Button>
            </DialogFooter>
          </div>
        ) : (
          <form ref={formRef} action={formAction} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="name">Key name</Label>
              <Input id="name" name="name" required placeholder="Website form" />
            </div>
            {state.error && (
              <p role="alert" className="text-sm text-danger">
                {state.error}
              </p>
            )}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" loading={pending}>
                Create key
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
