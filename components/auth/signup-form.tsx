"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2 } from "lucide-react";
import { signUpAction, type AuthFormState } from "@/app/(auth)/actions";
import { trackWhopRegistrationWhenReady } from "@/lib/analytics/whop";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Plan } from "@prisma/client";

const initialState: AuthFormState = {};

const MIN_PASSWORD_LENGTH = 8;

export function SignupForm({ plan }: { plan?: Plan | null }) {
  const [state, formAction, pending] = useActionState(signUpAction, initialState);
  const [password, setPassword] = useState("");
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
      <p
        role="status"
        className="flex items-center justify-center gap-2 rounded-lg border border-border bg-muted-surface/50 px-4 py-3 text-center text-sm text-muted"
      >
        <CheckCircle2 className="h-4 w-4 text-success" aria-hidden />
        Account created — taking you to setup…
      </p>
    );
  }

  if (state.success) {
    return (
      <div
        role="status"
        className="rounded-lg border border-success/30 bg-success-surface px-4 py-3 text-sm text-foreground"
      >
        {state.success}
      </div>
    );
  }

  const passwordTooShort = password.length > 0 && password.length < MIN_PASSWORD_LENGTH;

  return (
    <form action={formAction} className="space-y-4">
      {/* Re-validated server-side against the real plan list before it reaches
          a redirect — see signUpAction. */}
      {plan && <input type="hidden" name="plan" value={plan} />}

      <div className="space-y-1.5">
        <Label htmlFor="email">Work email</Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          autoCapitalize="none"
          spellCheck={false}
          required
          placeholder="you@company.com"
          aria-describedby={state.error ? "signup-error" : undefined}
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          required
          minLength={MIN_PASSWORD_LENGTH}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          aria-describedby="password-hint"
          aria-invalid={passwordTooShort || undefined}
        />
        <p
          id="password-hint"
          className={passwordTooShort ? "text-xs text-danger" : "text-xs text-muted"}
        >
          {passwordTooShort
            ? `${MIN_PASSWORD_LENGTH - password.length} more character${
                MIN_PASSWORD_LENGTH - password.length === 1 ? "" : "s"
              } needed.`
            : `At least ${MIN_PASSWORD_LENGTH} characters.`}
        </p>
      </div>

      {state.error && (
        <p id="signup-error" role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      )}

      <Button type="submit" className="w-full" loading={pending}>
        {pending ? "Creating your account…" : "Create Account"}
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
