import Link from "next/link";
import { Logo } from "@/components/marketing/logo";
import { WhopPixel } from "@/components/analytics/whop-pixel";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <header className="px-6 py-6">
        <Link href="/" className="inline-flex">
          <Logo />
        </Link>
      </header>
      <main className="flex flex-1 items-center justify-center px-4 pb-16">
        <div className="w-full max-w-sm">{children}</div>
      </main>
      <WhopPixel />
    </div>
  );
}
