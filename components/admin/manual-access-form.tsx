"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  grantAccessAction,
  lookupAccessAction,
  resetStripeLinkAction,
  revokeAccessAction,
  type AdminAccessState,
} from "@/app/dashboard/admin/actions";

const EMPTY: AdminAccessState = {};

function useAdminAction(action: (p: AdminAccessState, f: FormData) => Promise<AdminAccessState>) {
  const [state, formAction, pending] = useActionState(action, EMPTY);
  const seen = useRef<AdminAccessState | null>(null);

  useEffect(() => {
    if (state === seen.current) return;
    seen.current = state;
    if (state.success) toast.success(state.success);
    if (state.error) toast.error(state.error);
  }, [state]);

  return { state, formAction, pending };
}

export function ManualAccessForm() {
  const [email, setEmail] = useState("");
  const grant = useAdminAction(grantAccessAction);
  const revoke = useAdminAction(revokeAccessAction);
  const lookup = useAdminAction(lookupAccessAction);
  const resetLink = useAdminAction(resetStripeLinkAction);

  const found = lookup.state.lookup;

  return (
    <div className="space-y-6">
      <div className="space-y-1.5">
        <Label htmlFor="admin-email">Customer email</Label>
        <Input
          id="admin-email"
          name="email"
          type="email"
          autoComplete="off"
          placeholder="customer@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <p className="text-xs text-muted">
          The email the customer signed up to Converana with.
        </p>
      </div>

      {/* Check current state before changing it. */}
      <form action={lookup.formAction} className="flex items-end gap-2">
        <input type="hidden" name="email" value={email} />
        <Button type="submit" variant="outline" size="sm" loading={lookup.pending}>
          Check current access
        </Button>
      </form>

      {found && (
        <div className="rounded-lg border border-border bg-muted-surface p-4 text-sm">
          <p className="font-medium text-foreground">{found.businessName}</p>
          <p className="mt-1 flex items-center gap-2 text-muted">
            {found.status ? (
              <>
                <Badge variant={found.status === "ACTIVE" ? "success" : "secondary"}>{found.status}</Badge>
                <span>{found.plan} plan</span>
              </>
            ) : (
              <span>No subscription record — currently on free/Starter limits.</span>
            )}
          </p>
        </div>
      )}

      <div className="grid gap-4 border-t border-border pt-6 sm:grid-cols-[1fr_auto] sm:items-end">
        <form action={grant.formAction} className="contents">
          <input type="hidden" name="email" value={email} />
          <div className="space-y-1.5">
            <Label htmlFor="admin-plan">Grant plan</Label>
            <Select name="plan" defaultValue="STARTER">
              <SelectTrigger id="admin-plan">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="STARTER">Starter</SelectItem>
                <SelectItem value="GROWTH">Growth</SelectItem>
                <SelectItem value="PRO">Pro</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button type="submit" loading={grant.pending}>
            Activate
          </Button>
        </form>
      </div>

      <form action={revoke.formAction} className="border-t border-border pt-6">
        <input type="hidden" name="email" value={email} />
        <div className="flex items-center justify-between gap-4">
          <p className="text-sm text-muted">
            Revoking sets the subscription to cancelled. Their data is kept and limits drop to Starter.
          </p>
          <Button type="submit" variant="outline" loading={revoke.pending}>
            Revoke access
          </Button>
        </div>
      </form>

      <form action={resetLink.formAction} className="border-t border-border pt-6">
        <input type="hidden" name="email" value={email} />
        <div className="flex items-center justify-between gap-4">
          <p className="text-sm text-muted">
            Clear the stored Stripe customer so the next checkout starts a fresh one. Only needed if a
            checkout fails because the customer is locked to an old currency — refused while Stripe is
            still billing them.
          </p>
          <Button type="submit" variant="outline" loading={resetLink.pending}>
            Reset Stripe link
          </Button>
        </div>
      </form>
    </div>
  );
}
