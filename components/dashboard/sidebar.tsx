"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "@/components/marketing/logo";
import { ALL_NAV_ITEMS } from "./nav-items";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import type { Plan } from "@prisma/client";

export function Sidebar({ businessName, plan }: { businessName: string; plan: Plan }) {
  const pathname = usePathname();

  return (
    <aside className="hidden w-60 shrink-0 flex-col border-r border-border bg-surface md:flex">
      <div className="flex h-16 items-center border-b border-border px-5">
        <Link href="/dashboard">
          <Logo />
        </Link>
      </div>

      <div className="border-b border-border px-5 py-4">
        <p className="truncate text-sm font-medium text-foreground">{businessName}</p>
        <Badge variant="secondary" className="mt-1.5">
          {plan.charAt(0) + plan.slice(1).toLowerCase()} plan
        </Badge>
      </div>

      <nav className="flex-1 space-y-0.5 overflow-y-auto p-3">
        {ALL_NAV_ITEMS.map((item) => {
          const active =
            item.href === "/dashboard" ? pathname === "/dashboard" : pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                active
                  ? "bg-brand/10 text-brand"
                  : "text-muted hover:bg-muted-surface hover:text-foreground"
              )}
            >
              <item.icon className="h-4 w-4 shrink-0" />
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
