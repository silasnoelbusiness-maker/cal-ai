import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db/prisma";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiNotFound, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { notifyBusiness } from "@/lib/notifications";

const CreateSchema = z.object({
  leadId: z.string().min(1),
  scheduledAt: z.string().min(1),
  notes: z.string().trim().optional(),
});

export async function GET(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`appointments-list:${auth.business.id}`, 120, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const page = Math.max(Number(request.nextUrl.searchParams.get("page")) || 1, 1);
  const pageSize = 25;

  const [appointments, total] = await Promise.all([
    prisma.appointment.findMany({
      where: { businessId: auth.business.id },
      orderBy: { scheduledAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: { lead: true },
    }),
    prisma.appointment.count({ where: { businessId: auth.business.id } }),
  ]);

  return NextResponse.json({ appointments, total, page, pageSize });
}

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`appointments-create:${auth.business.id}`, 60, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const json = await request.json().catch(() => null);
  const parsed = CreateSchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const scheduledAt = new Date(parsed.data.scheduledAt);
  if (Number.isNaN(scheduledAt.getTime())) return apiError("Invalid scheduledAt date.");

  const lead = await prisma.lead.findFirst({ where: { id: parsed.data.leadId, businessId: auth.business.id } });
  if (!lead) return apiNotFound("Lead not found.");

  const appointment = await prisma.appointment.create({
    data: {
      businessId: auth.business.id,
      leadId: lead.id,
      scheduledAt,
      notes: parsed.data.notes || null,
      status: "PENDING",
    },
  });

  await prisma.lead.update({ where: { id: lead.id }, data: { status: "APPOINTMENT" } });
  await prisma.leadEvent.create({
    data: {
      leadId: lead.id,
      businessId: auth.business.id,
      type: "APPOINTMENT_BOOKED",
      description: `Appointment scheduled for ${scheduledAt.toLocaleString()}.`,
    },
  });
  await notifyBusiness({
    businessId: auth.business.id,
    type: "APPOINTMENT_BOOKED",
    title: `Appointment booked: ${lead.firstName} ${lead.lastName || ""}`.trim(),
    body: `Scheduled for ${scheduledAt.toLocaleString()}.`,
    leadId: lead.id,
  });

  return NextResponse.json({ appointment }, { status: 201 });
}
