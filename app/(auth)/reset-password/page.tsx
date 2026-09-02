import type { Metadata } from "next";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";

export const metadata: Metadata = { title: "Choose a new password" };

export default function ResetPasswordPage() {
  return (
    // Constrained here rather than in the layout: the signup page needs the
    // full width for its two-column design.
    <div className="mx-auto w-full max-w-sm space-y-6">
      <div className="space-y-1.5 text-center">
        <h1 className="text-xl font-semibold text-foreground">Choose a new password</h1>
      </div>
      <ResetPasswordForm />
    </div>
  );
}
