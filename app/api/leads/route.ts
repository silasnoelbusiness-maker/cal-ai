import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { resolveRequestAuth } from "@/lib/api/auth";
import { apiError, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { createLead } from "@/lib/leads/create-lead";
import { buildLeadsWhere, buildLeadsOrderBy, LEADS_PAGE_SIZE } from "@/lib/leads/query";

const CreateLeadSchema = z.object({
  firstName: z.string().trim().min(1, "firstName is required."),
  lastName: z.string().trim().optional(),
  email: z.union([z.email(), z.literal("")]).optional(),
  phone: z.string().trim().optional(),
  service: z.string().trim().optional(),
  serviceRequested: z.string().trim().optional(),
  message: z.string().trim().optional(),
  source: z.string().trim().optional(),
  smsConsent: z.boolean().optional(),
  emailConsent: z.boolean().optional(),
});

/**
 * Public lead capture API (Section 29). Authenticate with a business API
 * key: `Authorization: Bearer ll_live_...`. Also usable from the dashboard's
 * own session for the leads list.
 */
export async function POST(request: NextRequest) {
  const auth = await resolveRequestAuth(request);
  if (!auth) return apiUnauthorized("Invalid or missing API key.");

  const { allowed, retryAfterMs } = rateLimit(`leads-create:${auth.business.id}`, 120, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const json = await request.json().catch(() => null);
  const parsed = CreateLeadSchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const result = await createLead(auth.business, {
    firstName: parsed.data.firstName,
    lastName: parsed.data.lastName,
    email: parsed.data.email || undefined,
    phone: parsed.data.phone,
    serviceRequested: parsed.data.serviceRequested || parsed.data.service,
    message: parsed.data.message,
    source: parsed.data.source || (auth.apiKeyId ? "api" : "manual"),
    smsConsent: parsed.data.smsConsent,
    emailConsent: parsed.data.emailConsent,
  });

  if (!result.ok) return apiError(result.error || "Couldn't create lead.", 402);

  const lead = await prisma.lead.findUnique({ where: { id: result.leadId } });
  return NextResponse.json({ lead }, { status: 201 });
}

export async function GET(request: NextRequest) {
  const auth = await resolveRequestAuth(request);
  if (!auth) return apiUnauthorized("Invalid or missing API key.");

  const { allowed, retryAfterMs } = rateLimit(`leads-list:${auth.business.id}`, 120, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const params = request.nextUrl.searchParams;
  const page = Math.max(Number(params.get("page")) || 1, 1);

  const where = buildLeadsWhere({
    businessId: auth.business.id,
    filter: params.get("filter") || undefined,
    q: params.get("q") || undefined,
  });
  const orderBy = buildLeadsOrderBy({
    businessId: auth.business.id,
    sort: params.get("sort") || undefined,
    dir: params.get("dir") || undefined,
  });

  const [leads, total] = await Promise.all([
    prisma.lead.findMany({ where, orderBy, skip: (page - 1) * LEADS_PAGE_SIZE, take: LEADS_PAGE_SIZE }),
    prisma.lead.count({ where }),
  ]);

  return NextResponse.json({ leads, total, page, pageSize: LEADS_PAGE_SIZE });
}
