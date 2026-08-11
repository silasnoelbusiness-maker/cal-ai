import Link from "next/link";
import type { Metadata } from "next";
import { LoginForm } from "@/components/auth/login-form";
import { ConfigNotice } from "@/components/ui/config-notice";
import { isSupabaseConfigured } from "@/lib/auth/config";

export const metadata: Metadata = { title: "Log in" };

export default async function LoginPage({
  searchParams,
}: PageProps<"/login">) {
  const params = await searchParams;
  const next = typeof params.next === "string" ? params.next : undefined;

  return (
    <div className="space-y-6">
      <div className="space-y-1.5 text-center">
        <h1 className="text-xl font-semibold text-foreground">Welcome back</h1>
        <p className="text-sm text-muted">Log in to your Converana dashboard.</p>
      </div>
      {!isSupabaseConfigured && (
        <ConfigNotice
          title="Authentication isn't configured"
          description="Set NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY to enable login."
        />
      )}
      <LoginForm next={next} />
      <p className="text-center text-sm text-muted">
        Don&apos;t have an account?{" "}
        <Link href="/signup" className="font-medium text-brand hover:underline">
          Start free
        </Link>
      </p>
    </div>
  );
}
