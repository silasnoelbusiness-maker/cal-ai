"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, RotateCw } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * Catches unhandled errors from any dashboard page/layout below this
 * segment — most commonly a database or Prisma failure, since nearly every
 * dashboard page fetches data server-side with no per-page try/catch.
 * Without this boundary, Next.js falls back to its default unstyled crash
 * screen in production ("Application error: a client-side exception has
 * occurred") with no way to recover short of a full reload.
 */
export default function DashboardError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const router = useRouter();

  useEffect(() => {
    console.error("[dashboard] unhandled error", error);
  }, [error]);

  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center px-6 text-center">
      <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-danger-surface text-danger">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h1 className="text-lg font-semibold text-foreground">Something went wrong</h1>
      <p className="mt-2 max-w-sm text-sm text-muted">
        We hit an unexpected error loading this page. This is usually temporary — try again in a moment. If it
        keeps happening, our systems (like the database) may be experiencing an outage.
      </p>
      <div className="mt-6 flex items-center gap-3">
        <Button onClick={() => reset()}>
          <RotateCw className="h-4 w-4" />
          Try again
        </Button>
        <Button variant="outline" onClick={() => router.push("/dashboard")}>
          Back to dashboard
        </Button>
      </div>
    </div>
  );
}
