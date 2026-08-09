import Link from "next/link";
import { Logo } from "@/components/marketing/logo";
import { logoutAction } from "@/app/(auth)/actions";
import { Button } from "@/components/ui/button";

export default function OnboardingLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <header className="flex items-center justify-between px-6 py-6">
        <Link href="/" className="inline-flex">
          <Logo />
        </Link>
        <form action={logoutAction}>
          <Button variant="ghost" size="sm" type="submit">
            Log out
          </Button>
        </form>
      </header>
      <main className="flex flex-1 items-start justify-center px-4 pb-16 pt-4 sm:pt-10">
        {children}
      </main>
    </div>
  );
}
