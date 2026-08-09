"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, RotateCw } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * Root-level error boundary — catches unhandled errors anywhere outside the
 * dashboard (marketing site, auth pages, onboarding, embed form) that isn't
 * already covered by a more specific boundary. Next.js has no built-in
 * fallback here beyond a blank/unstyled crash screen in production, so
 * every top-level route needs at least this much.
 */
export default function RootError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const router = useRouter();

  useEffect(() => {
    console.error("[app] unhandled error", error);
  }, [error]);

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background px-6 text-center">
      <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-danger-surface text-danger">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h1 className="text-lg font-semibold text-foreground">Something went wrong</h1>
      <p className="mt-2 max-w-sm text-sm text-muted">
        We hit an unexpected error loading this page. This is usually temporary — please try again in a moment.
      </p>
      <div className="mt-6 flex items-center gap-3">
        <Button onClick={() => reset()}>
          <RotateCw className="h-4 w-4" />
          Try again
        </Button>
        <Button variant="outline" onClick={() => router.push("/")}>
          Go home
        </Button>
      </div>
    </div>
  );
}
