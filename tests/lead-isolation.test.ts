import { beforeEach, describe, expect, it, vi } from "vitest";

const mockBusinessA = { id: "biz_a" };
const mockPrisma = {
  lead: { findFirst: vi.fn(), update: vi.fn(), deleteMany: vi.fn() },
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));
vi.mock("@/lib/api/auth", () => ({
  resolveRequestAuth: vi.fn(() => Promise.resolve({ business: mockBusinessA })),
}));

const { GET, DELETE } = await import("@/app/api/leads/[id]/route");

function jsonRequest() {
  return { headers: { get: () => null } } as never;
}

describe("GET /api/leads/[id] — lead isolation", () => {
  beforeEach(() => vi.clearAllMocks());

  it("scopes the lookup to the authenticated business", async () => {
    mockPrisma.lead.findFirst.mockResolvedValue({ id: "lead_1", businessId: "biz_a" });
    await GET(jsonRequest(), { params: Promise.resolve({ id: "lead_1" }) });
    expect(mockPrisma.lead.findFirst).toHaveBeenCalledWith({
      where: { id: "lead_1", businessId: "biz_a" },
    });
  });

  it("returns 404 for a lead that belongs to a different business, even with a valid id", async () => {
    // The lead exists, but findFirst is scoped by businessId so a lead
    // owned by another business never matches — simulated here by the mock
    // returning null, matching real Prisma behavior for a non-matching scope.
    mockPrisma.lead.findFirst.mockResolvedValue(null);
    const res = await GET(jsonRequest(), { params: Promise.resolve({ id: "lead_from_biz_b" }) });
    expect(res.status).toBe(404);
  });

  it("returns the lead when it belongs to the authenticated business", async () => {
    const lead = { id: "lead_1", businessId: "biz_a" };
    mockPrisma.lead.findFirst.mockResolvedValue(lead);
    const res = await GET(jsonRequest(), { params: Promise.resolve({ id: "lead_1" }) });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.lead).toEqual(lead);
  });
});

describe("DELETE /api/leads/[id] — lead isolation", () => {
  beforeEach(() => vi.clearAllMocks());

  it("only deletes leads matching both id and businessId", async () => {
    mockPrisma.lead.deleteMany.mockResolvedValue({ count: 0 });
    const res = await DELETE(jsonRequest(), { params: Promise.resolve({ id: "lead_from_biz_b" }) });
    expect(mockPrisma.lead.deleteMany).toHaveBeenCalledWith({
      where: { id: "lead_from_biz_b", businessId: "biz_a" },
    });
    expect(res.status).toBe(404);
  });
});
