import Link from "next/link";
import type { Metadata } from "next";
import { Calendar } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { PageHeader } from "@/components/dashboard/page-header";
import { EmptyState } from "@/components/ui/empty-state";
import { AppointmentCard } from "@/components/appointments/appointment-card";
import { AppointmentActions } from "@/components/appointments/appointment-actions";
import { cn } from "@/lib/utils";
import type { AppointmentStatus, Prisma } from "@prisma/client";

export const metadata: Metadata = { title: "Appointments" };

const FILTERS = [
  { value: "upcoming", label: "Upcoming" },
  { value: "pending", label: "Pending" },
  { value: "confirmed", label: "Confirmed" },
  { value: "completed", label: "Completed" },
  { value: "cancelled", label: "Cancelled" },
  { value: "all", label: "All" },
] as const;

export default async function AppointmentsPage({ searchParams }: PageProps<"/dashboard/appointments">) {
  const { business } = await requireBusiness();
  const params = await searchParams;
  const filter = typeof params.filter === "string" ? params.filter : "upcoming";

  const where: Prisma.AppointmentWhereInput = { businessId: business.id };
  let orderDir: "asc" | "desc" = "asc";

  if (filter === "upcoming") {
    where.scheduledAt = { gte: new Date() };
    where.status = { in: ["PENDING", "CONFIRMED"] };
  } else if (filter === "pending") {
    where.status = "PENDING";
  } else if (filter === "confirmed") {
    where.status = "CONFIRMED";
  } else if (filter === "completed") {
    where.status = "COMPLETED";
    orderDir = "desc";
  } else if (filter === "cancelled") {
    where.status = "CANCELLED";
    orderDir = "desc";
  }

  const totalCount = await prisma.appointment.count({ where: { businessId: business.id } });
  const appointments = await prisma.appointment.findMany({
    where,
    orderBy: { scheduledAt: orderDir },
    include: { lead: true },
    take: 100,
  });

  return (
    <div>
      <PageHeader title="Appointments" description="Every appointment booked from a qualified lead." />

      {totalCount === 0 ? (
        <EmptyState
          icon={Calendar}
          title="No appointments yet"
          description="Appointments appear here once you schedule one from a lead's page."
          action={
            <Link href="/dashboard/leads" className="text-sm font-medium text-brand hover:underline">
              Go to leads
            </Link>
          }
        />
      ) : (
        <>
          <div className="mb-4 flex gap-1.5 overflow-x-auto scrollbar-thin pb-1">
            {FILTERS.map((f) => (
              <Link
                key={f.value}
                href={f.value === "upcoming" ? "/dashboard/appointments" : `/dashboard/appointments?filter=${f.value}`}
                className={cn(
                  "shrink-0 whitespace-nowrap rounded-full border px-3 py-1.5 text-sm font-medium transition-colors",
                  filter === f.value
                    ? "border-brand bg-brand text-brand-foreground"
                    : "border-border bg-surface text-muted hover:bg-muted-surface"
                )}
              >
                {f.label}
              </Link>
            ))}
          </div>

          {appointments.length === 0 ? (
            <EmptyState title="No appointments match this filter" />
          ) : (
            <div className="space-y-3">
              {appointments.map((appt) => (
                <AppointmentCard
                  key={appt.id}
                  leadName={`${appt.lead.firstName} ${appt.lead.lastName || ""}`.trim()}
                  leadHref={`/dashboard/leads/${appt.lead.id}`}
                  service={appt.lead.serviceRequested}
                  scheduledAt={appt.scheduledAt}
                  status={appt.status as AppointmentStatus}
                  actions={<AppointmentActions appointmentId={appt.id} status={appt.status} />}
                />
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
