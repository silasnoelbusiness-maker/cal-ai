import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPrisma = {
  lead: { deleteMany: vi.fn(), count: vi.fn(), findMany: vi.fn(), aggregate: vi.fn(), groupBy: vi.fn() },
  usage: { findUnique: vi.fn(), update: vi.fn() },
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { removeDemoData, hasDemoData } = await import("@/lib/demo");
const { currentMonthKey } = await import("@/lib/plans");

describe("removeDemoData", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("deletes all demo leads for the business", async () => {
    mockPrisma.lead.deleteMany.mockResolvedValue({ count: 6 });
    mockPrisma.usage.findUnique.mockResolvedValue(null);

    await removeDemoData("biz_1");

    expect(mockPrisma.lead.deleteMany).toHaveBeenCalledWith({
      where: { businessId: "biz_1", isDemo: true },
    });
  });

  it("rolls back exactly the usage counters loadDemoData bumped, not below zero", async () => {
    mockPrisma.lead.deleteMany.mockResolvedValue({ count: 6 });
    mockPrisma.usage.findUnique.mockResolvedValue({
      businessId: "biz_1",
      month: currentMonthKey(),
      leadsCount: 6,
      messagesCount: 9,
      aiMessagesCount: 6,
      appointmentsCount: 2,
    });

    await removeDemoData("biz_1");

    expect(mockPrisma.usage.update).toHaveBeenCalledWith({
      where: { businessId_month: { businessId: "biz_1", month: currentMonthKey() } },
      data: { leadsCount: 0, messagesCount: 0, aiMessagesCount: 0, appointmentsCount: 0 },
    });
  });

  it("clamps at zero instead of going negative when real usage is lower than the demo bump", async () => {
    // A business could plausibly delete demo data before any real activity,
    // or after usage was already reset — the counters must never go negative.
    mockPrisma.lead.deleteMany.mockResolvedValue({ count: 6 });
    mockPrisma.usage.findUnique.mockResolvedValue({
      businessId: "biz_1",
      month: currentMonthKey(),
      leadsCount: 2,
      messagesCount: 3,
      aiMessagesCount: 1,
      appointmentsCount: 0,
    });

    await removeDemoData("biz_1");

    expect(mockPrisma.usage.update).toHaveBeenCalledWith({
      where: { businessId_month: { businessId: "biz_1", month: currentMonthKey() } },
      data: { leadsCount: 0, messagesCount: 0, aiMessagesCount: 0, appointmentsCount: 0 },
    });
  });

  it("does nothing to usage when no usage row exists yet for the current month", async () => {
    mockPrisma.lead.deleteMany.mockResolvedValue({ count: 6 });
    mockPrisma.usage.findUnique.mockResolvedValue(null);

    await removeDemoData("biz_1");

    expect(mockPrisma.usage.update).not.toHaveBeenCalled();
  });
});

describe("hasDemoData", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("is true when the business has at least one demo lead", async () => {
    mockPrisma.lead.count.mockResolvedValue(3);
    await expect(hasDemoData("biz_1")).resolves.toBe(true);
    expect(mockPrisma.lead.count).toHaveBeenCalledWith({ where: { businessId: "biz_1", isDemo: true } });
  });

  it("is false when the business has no demo leads", async () => {
    mockPrisma.lead.count.mockResolvedValue(0);
    await expect(hasDemoData("biz_1")).resolves.toBe(false);
  });
});
