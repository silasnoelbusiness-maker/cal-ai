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
 * Internal admin page for manually granting paid access after a customer
 * buys through Whop.
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
        description="Manually grant or revoke paid access after confirming a Whop purchase."
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
            Writes the same subscription record Stripe uses, so plan limits and billing display work
            exactly as normal. Customers cannot reach this page or activate themselves.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <ManualAccessForm />
        </CardContent>
      </Card>
    </div>
  );
}
