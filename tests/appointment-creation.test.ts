import { beforeEach, describe, expect, it, vi } from "vitest";

const mockBusiness = { id: "biz_1", name: "PeakFlow HVAC" };
const mockLead = { id: "lead_1", businessId: "biz_1", firstName: "John", lastName: "Smith" };

const mockPrisma = {
  lead: { findFirst: vi.fn(), update: vi.fn() },
  appointment: { create: vi.fn() },
  leadEvent: { create: vi.fn() },
  $transaction: vi.fn(),
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));
vi.mock("@/lib/auth/session", () => ({
  requireBusiness: vi.fn(() => Promise.resolve({ user: { id: "user_1" }, business: mockBusiness })),
}));
vi.mock("@/lib/notifications", () => ({ notifyBusiness: vi.fn(() => Promise.resolve()) }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const { createAppointmentAction } = await import("@/app/dashboard/appointments/actions");
const { notifyBusiness } = await import("@/lib/notifications");

function formData(entries: Record<string, string>) {
  const fd = new FormData();
  for (const [key, value] of Object.entries(entries)) fd.set(key, value);
  return fd;
}

describe("createAppointmentAction", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.lead.findFirst.mockResolvedValue(mockLead);
    mockPrisma.$transaction.mockImplementation((ops: unknown[]) => Promise.all(ops));
    mockPrisma.appointment.create.mockResolvedValue({ id: "appt_1" });
    mockPrisma.leadEvent.create.mockResolvedValue({ id: "event_1" });
    mockPrisma.lead.update.mockResolvedValue({ id: "lead_1", status: "APPOINTMENT" });
  });

  it("rejects a request with no scheduled time", async () => {
    const result = await createAppointmentAction(
      {},
      formData({ leadId: "lead_1", scheduledAt: "" })
    );
    expect(result.error).toBeTruthy();
    expect(mockPrisma.appointment.create).not.toHaveBeenCalled();
  });

  it("rejects an unparsable date", async () => {
    const result = await createAppointmentAction(
      {},
      formData({ leadId: "lead_1", scheduledAt: "not-a-date" })
    );
    expect(result.error).toMatch(/valid date/i);
  });

  it("404s (via error) when the lead doesn't belong to the caller's business", async () => {
    mockPrisma.lead.findFirst.mockResolvedValue(null);
    const result = await createAppointmentAction(
      {},
      formData({ leadId: "lead_from_other_biz", scheduledAt: "2026-01-01T10:00" })
    );
    expect(result.error).toMatch(/not found/i);
    // Confirms the lookup was scoped to the authenticated business, not a
    // client-supplied businessId.
    expect(mockPrisma.lead.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: "lead_from_other_biz", businessId: "biz_1" } })
    );
  });

  it("creates a PENDING appointment and moves the lead to APPOINTMENT status", async () => {
    await createAppointmentAction({}, formData({ leadId: "lead_1", scheduledAt: "2026-06-01T10:00" }));

    expect(mockPrisma.$transaction).toHaveBeenCalled();
    const ops = mockPrisma.appointment.create.mock.calls[0][0];
    expect(ops.data.status).toBe("PENDING");
    expect(ops.data.leadId).toBe("lead_1");
    expect(ops.data.businessId).toBe("biz_1");
  });

  it("notifies the business when an appointment is booked", async () => {
    await createAppointmentAction({}, formData({ leadId: "lead_1", scheduledAt: "2026-06-01T10:00" }));
    expect(notifyBusiness).toHaveBeenCalledWith(
      expect.objectContaining({ businessId: "biz_1", type: "APPOINTMENT_BOOKED", leadId: "lead_1" })
    );
  });
});
