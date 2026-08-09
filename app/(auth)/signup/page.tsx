import Link from "next/link";
import type { Metadata } from "next";
import { SignupForm } from "@/components/auth/signup-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { isSupabaseConfigured } from "@/lib/auth/config";

export const metadata: Metadata = { title: "Start free" };

export default function SignupPage() {
  return (
    <div className="space-y-6">
      <div className="space-y-1.5 text-center">
        <h1 className="text-xl font-semibold text-foreground">Start recovering leads</h1>
        <p className="text-sm text-muted">No credit card required.</p>
      </div>
      {!isSupabaseConfigured && (
        <ConfigNotice
          title="Authentication isn't configured"
          description="Set NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY to enable sign-up."
        />
      )}
      <SignupForm />
      <p className="text-center text-sm text-muted">
        Already have an account?{" "}
        <Link href="/login" className="font-medium text-brand hover:underline">
          Log in
        </Link>
      </p>
    </div>
  );
}
