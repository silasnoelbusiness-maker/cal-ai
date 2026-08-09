import { beforeEach, describe, expect, it, vi } from "vitest";

const mockBusinessA = { id: "biz_a" };

const mockPrisma = {
  conversation: { findFirst: vi.fn(), update: vi.fn() },
  message: { create: vi.fn() },
  lead: { update: vi.fn() },
  usage: { upsert: vi.fn() },
  $transaction: vi.fn((ops: unknown[]) => Promise.all(ops)),
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));
vi.mock("@/lib/auth/session", () => ({
  getApiAuthContext: vi.fn(() => Promise.resolve({ user: { id: "user_1" }, business: mockBusinessA })),
}));
vi.mock("@/lib/resend/send-email", () => ({ sendEmail: vi.fn() }));
vi.mock("@/lib/twilio/send-sms", () => ({ sendSMS: vi.fn() }));

const { POST } = await import("@/app/api/conversations/[id]/messages/route");

function jsonRequest(body: unknown) {
  return {
    headers: { get: () => null },
    json: () => Promise.resolve(body),
  } as never;
}

describe("POST /api/conversations/[id]/messages — isolation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.usage.upsert.mockResolvedValue({});
  });

  it("scopes the conversation lookup to the authenticated business", async () => {
    mockPrisma.conversation.findFirst.mockResolvedValue(null);
    await POST(jsonRequest({ content: "hi" }), { params: Promise.resolve({ id: "convo_from_biz_b" }) });
    expect(mockPrisma.conversation.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: "convo_from_biz_b", businessId: "biz_a" } })
    );
  });

  it("404s for a conversation belonging to another business", async () => {
    mockPrisma.conversation.findFirst.mockResolvedValue(null);
    const res = await POST(jsonRequest({ content: "hi" }), { params: Promise.resolve({ id: "convo_from_biz_b" }) });
    expect(res.status).toBe(404);
    expect(mockPrisma.message.create).not.toHaveBeenCalled();
  });

  it("creates a message when the conversation belongs to the caller's business", async () => {
    mockPrisma.conversation.findFirst.mockResolvedValue({
      id: "convo_1",
      leadId: "lead_1",
      channel: "WEB",
      lead: { id: "lead_1", status: "NEW", phone: null, email: null, smsConsent: false, emailConsent: false },
    });
    mockPrisma.message.create.mockResolvedValue({ id: "msg_1", content: "hi" });
    const res = await POST(jsonRequest({ content: "hi" }), { params: Promise.resolve({ id: "convo_1" }) });
    expect(res.status).toBe(201);
    expect(mockPrisma.message.create).toHaveBeenCalled();
  });

  it("rejects an empty message body", async () => {
    mockPrisma.conversation.findFirst.mockResolvedValue({
      id: "convo_1",
      leadId: "lead_1",
      channel: "WEB",
      lead: { id: "lead_1", status: "NEW" },
    });
    const res = await POST(jsonRequest({ content: "" }), { params: Promise.resolve({ id: "convo_1" }) });
    expect(res.status).toBe(400);
  });
});
