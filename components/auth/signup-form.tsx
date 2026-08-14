"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { signUpAction, type AuthFormState } from "@/app/(auth)/actions";
import { trackWhopRegistrationWhenReady } from "@/lib/analytics/whop";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const initialState: AuthFormState = {};

export function SignupForm() {
  const [state, formAction, pending] = useActionState(signUpAction, initialState);
  const router = useRouter();

  // Reports the Whop conversion, then navigates. `state.registered` is set
  // by the server only for a genuinely new account, and the tracker itself
  // is idempotent per user id, so a refresh or a double-invoked effect
  // cannot produce a second conversion.
  useEffect(() => {
    if (state.registered) trackWhopRegistrationWhenReady(state.registered);
    // Navigation is not conditional on tracking succeeding — an ad blocker
    // must never strand someone on the signup page.
    if (state.redirectTo) router.push(state.redirectTo);
  }, [state.registered, state.redirectTo, router]);

  // The account exists and the session is live; the router push is already
  // in flight. Showing the empty form again in the meantime would look like
  // the submission failed.
  if (state.redirectTo) {
    return (
      <p className="rounded-lg border border-border bg-muted-surface/50 px-4 py-3 text-center text-sm text-muted">
        Account created — taking you to setup…
      </p>
    );
  }

  if (state.success) {
    return (
      <div className="rounded-lg border border-success/30 bg-success-surface px-4 py-3 text-sm text-foreground">
        {state.success}
      </div>
    );
  }

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-1.5">
        <Label htmlFor="email">Work email</Label>
        <Input id="email" name="email" type="email" autoComplete="email" required placeholder="you@company.com" />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          required
          minLength={8}
        />
        <p className="text-xs text-muted">At least 8 characters.</p>
      </div>
      {state.error && (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      )}
      <Button type="submit" className="w-full" loading={pending}>
        Create account
      </Button>
      <p className="text-center text-xs text-muted">
        By continuing you agree to Converana&apos;s{" "}
        <a href="/terms" className="underline hover:text-foreground">
          Terms
        </a>{" "}
        and{" "}
        <a href="/privacy" className="underline hover:text-foreground">
          Privacy Policy
        </a>
        .
      </p>
    </form>
  );
}
