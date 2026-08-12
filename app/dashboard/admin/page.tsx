import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { isAdminEmail, hasAdminsConfigured } from "@/lib/admin/config";
import { PageHeader } from "@/components/dashboard/page-header";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { ConfigNotice } from "@/components/ui/config-notice";
import { ManualAccessForm } from "@/components/admin/manual-access-form";

export const metadata: Metadata = { title: "Admin" };
export const dynamic = "force-dynamic";

/**
 * Emergency admin tool for subscription recovery.
 *
 * Customers are activated automatically by the Stripe webhook after checkout;
 * this page exists only for support cases where that didn't happen or needs
 * overriding.
 *
 * Not linked from the dashboard navigation — reachable only by typing the
 * URL. It returns a 404 for anyone whose email isn't in ADMIN_EMAILS, so its
 * existence isn't disclosed to normal users. The 404 is a convenience only:
 * the server actions independently re-check admin status, so the real
 * enforcement does not depend on this page.
 */
export default async function AdminPage() {
  const { user } = await requireBusiness();

  if (!isAdminEmail(user.email)) notFound();

  return (
    <div>
      <PageHeader
        title="Admin"
        description="Emergency subscription recovery. Not part of the normal customer flow."
      />

      {!hasAdminsConfigured() && (
        <ConfigNotice
          className="mb-6"
          title="No admins configured"
          description="Set ADMIN_EMAILS to a comma-separated list of admin email addresses."
        />
      )}

      <Card>
        <CardHeader>
          <CardTitle>Manual subscription access</CardTitle>
          <CardDescription>
            For support and recovery only — customers are normally activated automatically by the
            Stripe webhook after checkout. Use this when that didn&apos;t happen. Writes the same
            subscription record Stripe uses, so plan limits and the billing page behave exactly as
            normal. A manual grant has no Stripe subscription behind it, so it won&apos;t renew, and
            a later Stripe event for the same account will overwrite it.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <ManualAccessForm />
        </CardContent>
      </Card>
    </div>
  );
}
