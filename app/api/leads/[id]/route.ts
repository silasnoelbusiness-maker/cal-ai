import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { resolveRequestAuth } from "@/lib/api/auth";
import { apiError, apiNotFound, apiUnauthorized } from "@/lib/api/response";
import type { LeadStatus, LeadTemperature } from "@prisma/client";

const PatchSchema = z.object({
  status: z.enum(["NEW", "CONTACTED", "QUALIFIED", "APPOINTMENT", "CONVERTED", "LOST", "CLOSED"]).optional(),
  temperature: z.enum(["HOT", "WARM", "COLD"]).optional(),
  estimatedValue: z.number().nonnegative().optional(),
  serviceRequested: z.string().trim().optional(),
  smsConsent: z.boolean().optional(),
  emailConsent: z.boolean().optional(),
  optedOut: z.boolean().optional(),
});

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await resolveRequestAuth(request);
  if (!auth) return apiUnauthorized("Invalid or missing API key.");

  const { id } = await params;
  const lead = await prisma.lead.findFirst({ where: { id, businessId: auth.business.id } });
  if (!lead) return apiNotFound("Lead not found.");

  return NextResponse.json({ lead });
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await resolveRequestAuth(request);
  if (!auth) return apiUnauthorized("Invalid or missing API key.");

  const { id } = await params;
  const existing = await prisma.lead.findFirst({ where: { id, businessId: auth.business.id } });
  if (!existing) return apiNotFound("Lead not found.");

  const json = await request.json().catch(() => null);
  const parsed = PatchSchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const data: Record<string, unknown> = { ...parsed.data };
  if (parsed.data.status) data.status = parsed.data.status as LeadStatus;
  if (parsed.data.temperature) data.temperature = parsed.data.temperature as LeadTemperature;
  if (parsed.data.status === "CONVERTED") data.convertedAt = new Date();

  const lead = await prisma.lead.update({ where: { id }, data });
  return NextResponse.json({ lead });
}

export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await resolveRequestAuth(request);
  if (!auth) return apiUnauthorized("Invalid or missing API key.");

  const { id } = await params;
  const result = await prisma.lead.deleteMany({ where: { id, businessId: auth.business.id } });
  if (result.count === 0) return apiNotFound("Lead not found.");

  return NextResponse.json({ ok: true });
}
