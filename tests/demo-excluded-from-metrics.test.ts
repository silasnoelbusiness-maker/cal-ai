import { beforeEach, describe, expect, it, vi } from "vitest";

const mockPrisma = {
  lead: { count: vi.fn(), aggregate: vi.fn(), findMany: vi.fn(), groupBy: vi.fn() },
  appointment: { count: vi.fn() },
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { getDashboardMetrics, getPipelineSnapshot } = await import("@/lib/dashboard/data");
const { getAnalytics } = await import("@/lib/analytics/data");

describe("demo leads never contaminate revenue/metrics", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.lead.count.mockResolvedValue(0);
    mockPrisma.lead.aggregate.mockResolvedValue({ _sum: { estimatedValue: 0 } });
    mockPrisma.appointment.count.mockResolvedValue(0);
    mockPrisma.lead.findMany.mockResolvedValue([]);
    mockPrisma.lead.groupBy.mockResolvedValue([]);
  });

  it("getDashboardMetrics scopes every lead query to isDemo: false", async () => {
    await getDashboardMetrics("biz_1");

    for (const call of mockPrisma.lead.count.mock.calls) {
      expect(call[0].where).toMatchObject({ businessId: "biz_1", isDemo: false });
    }
    for (const call of mockPrisma.lead.aggregate.mock.calls) {
      expect(call[0].where).toMatchObject({ businessId: "biz_1", isDemo: false, status: "CONVERTED" });
    }
  });

  it("getDashboardMetrics scopes appointment revenue/count queries to real (non-demo) leads only", async () => {
    await getDashboardMetrics("biz_1");

    for (const call of mockPrisma.appointment.count.mock.calls) {
      expect(call[0].where).toMatchObject({ businessId: "biz_1", lead: { isDemo: false } });
    }
  });

  it("getPipelineSnapshot excludes demo leads from the pipeline counts", async () => {
    await getPipelineSnapshot("biz_1");

    expect(mockPrisma.lead.groupBy).toHaveBeenCalledWith(
      expect.objectContaining({ where: { businessId: "biz_1", isDemo: false } })
    );
  });

  it("getAnalytics (recovered revenue + every other metric) excludes demo leads", async () => {
    await getAnalytics("biz_1", 30);

    expect(mockPrisma.lead.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ businessId: "biz_1", isDemo: false }),
      })
    );
  });
});
