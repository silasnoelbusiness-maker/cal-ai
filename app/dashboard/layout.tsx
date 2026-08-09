import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { Sidebar } from "@/components/dashboard/sidebar";
import { MobileNav } from "@/components/dashboard/mobile-nav";
import { Topbar } from "@/components/dashboard/topbar";
import { DemoBanner } from "@/components/dashboard/demo-banner";

// Every route under /dashboard is per-user, authenticated data — never
// statically prerender or cache it across users/requests.
export const dynamic = "force-dynamic";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { user, business } = await requireBusiness();

  const subscription = await prisma.subscription.findUnique({ where: { businessId: business.id } });

  return (
    <div className="flex min-h-screen bg-background">
      <Sidebar businessName={business.name} plan={subscription?.plan || "STARTER"} />
      <div className="flex min-w-0 flex-1 flex-col pb-16 md:pb-0">
        <Topbar businessId={business.id} email={user.email} />
        <DemoBanner businessId={business.id} />
        <main className="flex-1 p-4 sm:p-6">{children}</main>
      </div>
      <MobileNav />
    </div>
  );
}
