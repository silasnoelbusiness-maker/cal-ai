import { prisma } from "@/lib/db/prisma";
import { GlobalSearch } from "./global-search";
import { NotificationBell, type NotificationItem } from "./notification-bell";
import { UserMenu } from "./user-menu";
import { Logo } from "@/components/marketing/logo";
import Link from "next/link";

export async function Topbar({ businessId, email }: { businessId: string; email: string }) {
  const notifications: NotificationItem[] = await prisma.notification.findMany({
    where: { businessId },
    orderBy: { createdAt: "desc" },
    take: 20,
  });

  return (
    <header className="sticky top-0 z-20 flex h-16 items-center gap-3 border-b border-border bg-surface/90 px-4 backdrop-blur sm:px-6">
      <Link href="/dashboard" className="md:hidden">
        <Logo className="[&_span]:hidden" />
      </Link>
      <div className="flex-1">
        <GlobalSearch />
      </div>
      <NotificationBell notifications={notifications} />
      <UserMenu email={email} />
    </header>
  );
}
