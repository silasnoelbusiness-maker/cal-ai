"use client";

import { useRouter } from "next/navigation";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";

export function GlobalSearch() {
  const router = useRouter();

  return (
    <form
      className="relative hidden w-full max-w-xs sm:block"
      onSubmit={(e) => {
        e.preventDefault();
        const value = new FormData(e.currentTarget).get("q");
        const q = typeof value === "string" ? value.trim() : "";
        router.push(q ? `/dashboard/leads?q=${encodeURIComponent(q)}` : "/dashboard/leads");
      }}
    >
      <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
      <Input
        name="q"
        placeholder="Search leads, contacts, conversations…"
        className="pl-8"
        aria-label="Search"
      />
    </form>
  );
}
