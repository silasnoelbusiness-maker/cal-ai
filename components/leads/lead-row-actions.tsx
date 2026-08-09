"use client";

import { useTransition } from "react";
import Link from "next/link";
import { MoreHorizontal, Eye, Trash2 } from "lucide-react";
import { toast } from "sonner";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { deleteLeadAction } from "@/app/dashboard/leads/actions";

export function LeadRowActions({ leadId, leadName }: { leadId: string; leadName: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          className="inline-flex h-8 w-8 items-center justify-center rounded-md text-muted hover:bg-muted-surface hover:text-foreground"
          aria-label={`Actions for ${leadName}`}
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-4 w-4" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" onClick={(e) => e.stopPropagation()}>
        <DropdownMenuItem asChild>
          <Link href={`/dashboard/leads/${leadId}`}>
            <Eye className="h-4 w-4" />
            View details
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem
          className="text-danger"
          disabled={pending}
          onSelect={() => {
            if (!window.confirm(`Delete ${leadName}? This can't be undone.`)) return;
            startTransition(async () => {
              await deleteLeadAction(leadId);
              toast.success("Lead deleted");
            });
          }}
        >
          <Trash2 className="h-4 w-4" />
          Delete lead
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
