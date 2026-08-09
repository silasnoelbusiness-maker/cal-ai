import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { apiError, apiNotFound, apiRateLimited } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { createLead } from "@/lib/leads/create-lead";

const BodySchema = z.object({
  firstName: z.string().trim().min(1, "Name is required."),
  lastName: z.string().trim().optional(),
  email: z.union([z.email("Enter a valid email."), z.literal("")]).optional(),
  phone: z.string().trim().optional(),
  service: z.string().trim().optional(),
  message: z.string().trim().optional(),
  // Honeypot field — real visitors never fill this in.
  company_website: z.string().optional(),
});

function clientIp(request: NextRequest): string {
  // Most hosts (Vercel, Cloudflare, etc.) set one of these. Without a proxy
  // that sets any of them, every anonymous visitor falls into the same
  // "unknown" bucket and the per-IP limit degrades to one shared global
  // limit — fine as a fail-safe, but confirm your host forwards one of
  // these headers before relying on per-visitor limiting in production.
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip")?.trim() ||
    request.headers.get("cf-connecting-ip")?.trim() ||
    "unknown"
  );
}

/**
 * Public, unauthenticated endpoint backing the embeddable lead form
 * (Section 30). businessId is a non-secret identifier — this route only
 * ever creates a lead, and is aggressively rate-limited per IP.
 */
export async function POST(request: NextRequest, { params }: { params: Promise<{ businessId: string }> }) {
  const { businessId } = await params;

  const ipLimit = rateLimit(`public-leads-ip:${clientIp(request)}`, 10, 60_000);
  if (!ipLimit.allowed) return apiRateLimited(ipLimit.retryAfterMs);
  const businessLimit = rateLimit(`public-leads-biz:${businessId}`, 60, 60_000);
  if (!businessLimit.allowed) return apiRateLimited(businessLimit.retryAfterMs);

  const business = await prisma.business.findUnique({ where: { id: businessId } });
  if (!business) return apiNotFound("This form is no longer active.");

  const json = await request.json().catch(() => null);
  const parsed = BodySchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  if (parsed.data.company_website) {
    // Honeypot tripped — pretend success without creating anything.
    return NextResponse.json({ ok: true });
  }

  const result = await createLead(business, {
    firstName: parsed.data.firstName,
    lastName: parsed.data.lastName,
    email: parsed.data.email || undefined,
    phone: parsed.data.phone,
    serviceRequested: parsed.data.service,
    message: parsed.data.message,
    source: "embed",
    channel: "WEB",
    emailConsent: true,
  });

  if (!result.ok) return apiError(result.error || "Couldn't submit your request. Please try again.", 402);

  return NextResponse.json({ ok: true }, { status: 201 });
}
