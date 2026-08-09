import type { Metadata } from "next";
import { prisma } from "@/lib/db/prisma";
import { EmbedForm } from "@/components/embed/embed-form";
import { Logo } from "@/components/marketing/logo";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: PageProps<"/embed/[businessId]">): Promise<Metadata> {
  const { businessId } = await params;
  const business = await prisma.business.findUnique({ where: { id: businessId } });
  return { title: business ? `Request service — ${business.name}` : "Request service" };
}

export default async function EmbedPage({ params }: PageProps<"/embed/[businessId]">) {
  const { businessId } = await params;
  const business = await prisma.business.findUnique({ where: { id: businessId } });

  if (!business) {
    return (
      <div className="flex min-h-[240px] items-center justify-center p-6 text-center text-sm text-muted">
        This form is no longer available.
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-md p-5">
      <h1 className="text-lg font-semibold text-foreground">Request service from {business.name}</h1>
      <p className="mt-1 text-sm text-muted">We&apos;ll get back to you as quickly as possible.</p>
      <div className="mt-5">
        <EmbedForm businessId={business.id} businessName={business.name} />
      </div>
      <div className="mt-6 flex items-center justify-center gap-1.5 text-xs text-muted opacity-70">
        Powered by <Logo className="scale-90 [&_span]:text-xs" />
      </div>
    </div>
  );
}
