"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { Pencil } from "lucide-react";
import { updateLeadDetailsAction, type LeadFormState } from "@/app/dashboard/leads/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
  DialogTrigger,
} from "@/components/ui/dialog";
import type { Lead } from "@prisma/client";

const initialState: LeadFormState = {};

// Server Components can't pass a Prisma `Decimal` across the RSC boundary
// (it isn't a plain object), so callers must serialize `estimatedValue` to
// a plain number/null before rendering this client component.
type EditableLead = Omit<Lead, "estimatedValue"> & { estimatedValue: number | null };

export function EditLeadDialog({ lead }: { lead: EditableLead }) {
  const [open, setOpen] = useState(false);
  const action = updateLeadDetailsAction.bind(null, lead.id);
  const [state, formAction, pending] = useActionState(action, initialState);
  const submitted = useRef(false);

  useEffect(() => {
    if (pending) submitted.current = true;
    else if (submitted.current && !state.error) {
      submitted.current = false;
      setOpen(false);
    }
  }, [pending, state.error]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Pencil className="h-3.5 w-3.5" />
          Edit
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit lead</DialogTitle>
        </DialogHeader>
        <form action={formAction} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="firstName">First name</Label>
              <Input id="firstName" name="firstName" defaultValue={lead.firstName} required />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="lastName">Last name</Label>
              <Input id="lastName" name="lastName" defaultValue={lead.lastName || ""} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="email">Email</Label>
              <Input id="email" name="email" type="email" defaultValue={lead.email || ""} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="phone">Phone</Label>
              <Input id="phone" name="phone" type="tel" defaultValue={lead.phone || ""} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="serviceRequested">Service requested</Label>
            <Input id="serviceRequested" name="serviceRequested" defaultValue={lead.serviceRequested || ""} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="estimatedValue">Estimated value ($)</Label>
            <Input
              id="estimatedValue"
              name="estimatedValue"
              type="number"
              min={0}
              step="0.01"
              defaultValue={lead.estimatedValue !== null ? String(lead.estimatedValue) : ""}
            />
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
              Save
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
