"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const SECTIONS = [
  { href: "/dashboard/settings", label: "Business" },
  { href: "/dashboard/settings/ai", label: "AI Assistant" },
  { href: "/dashboard/settings/follow-up", label: "Follow-up" },
  { href: "/dashboard/settings/notifications", label: "Notifications" },
  { href: "/dashboard/settings/integrations", label: "Integrations" },
  { href: "/dashboard/settings/api-keys", label: "API Keys" },
  { href: "/dashboard/settings/account", label: "Account" },
  { href: "/dashboard/billing", label: "Billing" },
];

export function SettingsNav() {
  const pathname = usePathname();

  return (
    <nav className="flex gap-1.5 overflow-x-auto scrollbar-thin border-b border-border pb-3">
      {SECTIONS.map((section) => {
        const active = pathname === section.href;
        return (
          <Link
            key={section.href}
            href={section.href}
            className={cn(
              "shrink-0 whitespace-nowrap rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
              active ? "bg-brand/10 text-brand" : "text-muted hover:bg-muted-surface hover:text-foreground"
            )}
          >
            {section.label}
          </Link>
        );
      })}
    </nav>
  );
}
