import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { PLAN_LIMITS } from "@/lib/plans";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Avatar } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";

export const metadata: Metadata = { title: "Account" };

export default async function AccountSettingsPage() {
  const { user, business } = await requireBusiness();
  const [members, subscription] = await Promise.all([
    prisma.businessMember.findMany({ where: { businessId: business.id }, include: { user: true } }),
    prisma.subscription.findUnique({ where: { businessId: business.id } }),
  ]);
  const maxUsers = PLAN_LIMITS[subscription?.plan || "STARTER"].maxUsers;

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Account</CardTitle>
          <CardDescription>Your login and password.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          <div className="flex items-center gap-3">
            <Avatar name={user.email} />
            <p className="text-sm font-medium text-foreground">{user.email}</p>
          </div>
          <div className="max-w-sm border-t border-border pt-5">
            <p className="mb-3 text-sm font-medium text-foreground">Change password</p>
            <ResetPasswordForm />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Team</CardTitle>
          <CardDescription>
            {members.length} of {maxUsers} seats used on your {PLAN_LIMITS[subscription?.plan || "STARTER"].label}{" "}
            plan.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="divide-y divide-border">
            {members.map((member) => (
              <div key={member.id} className="flex items-center justify-between py-3">
                <div className="flex items-center gap-3">
                  <Avatar name={member.user.email} />
                  <p className="text-sm text-foreground">{member.user.email}</p>
                </div>
                <Badge variant="secondary">{member.role.charAt(0) + member.role.slice(1).toLowerCase()}</Badge>
              </div>
            ))}
          </div>
          <p className="mt-4 text-xs text-muted">
            Inviting additional team members is coming in a future update — upgrade your plan now to
            reserve seats.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
