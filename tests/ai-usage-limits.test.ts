import { beforeEach, describe, expect, it, vi } from "vitest";

const mockBusiness = {
  id: "biz_1",
  name: "PeakFlow HVAC",
  aiEnabled: true,
};

const mockLead = {
  id: "lead_1",
  businessId: "biz_1",
  firstName: "John",
  lastName: "Smith",
  message: "My AC broke",
  status: "NEW",
  createdAt: new Date(),
};

const mockPrisma = {
  usage: { upsert: vi.fn(), update: vi.fn() },
  subscription: { findUnique: vi.fn() },
  lead: { create: vi.fn(), findUnique: vi.fn(), update: vi.fn() },
  leadEvent: { create: vi.fn() },
  conversation: { create: vi.fn() },
  message: { create: vi.fn() },
  followUpSettings: { findUnique: vi.fn() },
  followUp: { count: vi.fn() },
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));
vi.mock("@/lib/notifications", () => ({ notifyBusiness: vi.fn(() => Promise.resolve()) }));

const mockGenerateBusinessReply = vi.fn();
const mockQualifyLead = vi.fn();
vi.mock("@/lib/ai", async () => {
  const actual = await vi.importActual<typeof import("@/lib/ai")>("@/lib/ai");
  return {
    ...actual,
    generateBusinessReply: mockGenerateBusinessReply,
    qualifyLead: mockQualifyLead,
  };
});

const { createLead } = await import("@/lib/leads/create-lead");

describe("createLead — AI usage accounting", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.usage.upsert.mockResolvedValue({ leadsCount: 0, aiMessagesCount: 0 });
    mockPrisma.usage.update.mockResolvedValue({});
    mockPrisma.subscription.findUnique.mockResolvedValue({ plan: "STARTER" });
    mockPrisma.lead.create.mockResolvedValue(mockLead);
    mockPrisma.lead.findUnique.mockResolvedValue(mockLead);
    mockPrisma.lead.update.mockResolvedValue(mockLead);
    mockPrisma.leadEvent.create.mockResolvedValue({});
    mockPrisma.conversation.create.mockResolvedValue({ id: "convo_1" });
    mockPrisma.message.create.mockResolvedValue({});
    mockPrisma.followUpSettings.findUnique.mockResolvedValue({
      immediateResponse: true,
      enabled: true,
      delay30MinEnabled: true,
      maxFollowUps: 4,
      defaultChannel: "EMAIL",
    });
    mockPrisma.followUp.count.mockResolvedValue(0);
    mockGenerateBusinessReply.mockResolvedValue({ content: "Thanks, what's your ZIP?" });
    mockQualifyLead.mockResolvedValue({
      qualification_score: 80,
      temperature: "HOT",
      intent: "high",
      urgency: "high",
      service: "AC repair",
      location: "Austin",
      budget: "Unknown",
      availability: "Unknown",
      summary: "Needs AC repair.",
      recommended_action: "Call now.",
      needs_human: false,
    });
  });

  it("records usage once per real AI call — two calls (reply + qualify) means two increments", async () => {
    await createLead(mockBusiness as never, { firstName: "John" });

    expect(mockGenerateBusinessReply).toHaveBeenCalledTimes(1);
    expect(mockQualifyLead).toHaveBeenCalledTimes(1);

    const aiIncrementCalls = mockPrisma.usage.update.mock.calls.filter(
      (call) => call[0]?.data?.aiMessagesCount?.increment
    );
    expect(aiIncrementCalls).toHaveLength(2);
  });

  it("skips the qualification call once the running usage total reaches the plan's AI limit", async () => {
    // STARTER allows 500 AI messages/month; start one below the ceiling so
    // the first call (reply) pushes it exactly to the limit.
    mockPrisma.usage.upsert.mockResolvedValue({ leadsCount: 0, aiMessagesCount: 499 });

    await createLead(mockBusiness as never, { firstName: "John" });

    expect(mockGenerateBusinessReply).toHaveBeenCalledTimes(1);
    expect(mockQualifyLead).not.toHaveBeenCalled();
  });

  it("makes no AI calls at all once already at the plan's AI limit", async () => {
    mockPrisma.usage.upsert.mockResolvedValue({ leadsCount: 0, aiMessagesCount: 500 });

    await createLead(mockBusiness as never, { firstName: "John" });

    expect(mockGenerateBusinessReply).not.toHaveBeenCalled();
    expect(mockQualifyLead).not.toHaveBeenCalled();
  });
});
