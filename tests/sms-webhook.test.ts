import { beforeEach, describe, expect, it, vi } from "vitest";

const mockValidateRequest = vi.fn();
vi.mock("twilio", () => ({
  default: { validateRequest: mockValidateRequest },
}));

const mockBusiness = {
  id: "biz_1",
  name: "Test HVAC",
  aiEnabled: true,
  twilioPhoneNumber: "+15555550100",
};

const mockPrisma = {
  business: { findUnique: vi.fn() },
  lead: { findFirst: vi.fn(), update: vi.fn() },
  conversation: { findFirst: vi.fn(), create: vi.fn() },
  message: { create: vi.fn() },
  leadEvent: { create: vi.fn() },
  usage: { upsert: vi.fn(), update: vi.fn() },
  subscription: { findUnique: vi.fn() },
};

vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));
vi.mock("@/lib/notifications", () => ({ notifyBusiness: vi.fn(() => Promise.resolve()) }));
const mockCreateLead = vi.fn();
vi.mock("@/lib/leads/create-lead", () => ({ createLead: mockCreateLead }));
const mockGenerateBusinessReply = vi.fn();
vi.mock("@/lib/ai", async () => {
  const actual = await vi.importActual<typeof import("@/lib/ai")>("@/lib/ai");
  return { ...actual, generateBusinessReply: mockGenerateBusinessReply };
});

process.env.TWILIO_ACCOUNT_SID = "ACtest";
process.env.TWILIO_AUTH_TOKEN = "test_token";
process.env.TWILIO_PHONE_NUMBER = "+15555550100";
process.env.NEXT_PUBLIC_APP_URL = "https://app.example.com";

const { POST } = await import("@/app/api/webhooks/twilio/sms/route");

function formRequest(params: Record<string, string>, signature = "valid-sig") {
  const body = new URLSearchParams(params).toString();
  return {
    text: () => Promise.resolve(body),
    headers: { get: (key: string) => (key.toLowerCase() === "x-twilio-signature" ? signature : null) },
  } as never;
}

describe("POST /api/webhooks/twilio/sms — signature verification", () => {
  beforeEach(() => vi.clearAllMocks());

  it("rejects a request with an invalid Twilio signature", async () => {
    mockValidateRequest.mockReturnValue(false);
    const res = await POST(formRequest({ From: "+15125551111", To: "+15555550100", Body: "hi" }));
    expect(res.status).toBe(403);
  });

  it("rejects a request with no signature header at all", async () => {
    mockValidateRequest.mockReturnValue(false);
    const res = await POST(formRequest({ From: "+15125551111", To: "+15555550100", Body: "hi" }, ""));
    expect(res.status).toBe(403);
  });

  it("never touches the database when the signature is invalid", async () => {
    mockValidateRequest.mockReturnValue(false);
    await POST(formRequest({ From: "+15125551111", To: "+15555550100", Body: "hi" }));
    expect(mockPrisma.business.findUnique).not.toHaveBeenCalled();
  });
});

describe("POST /api/webhooks/twilio/sms — message handling", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockValidateRequest.mockReturnValue(true);
    mockPrisma.business.findUnique.mockResolvedValue(mockBusiness);
  });

  it("creates a new lead for an unrecognized inbound number", async () => {
    mockPrisma.lead.findFirst.mockResolvedValue(null);
    mockCreateLead.mockResolvedValue({ ok: true, leadId: "lead_new" });

    const res = await POST(formRequest({ From: "+15125552222", To: "+15555550100", Body: "Need a plumber" }));

    expect(res.status).toBe(200);
    expect(mockCreateLead).toHaveBeenCalledWith(
      mockBusiness,
      expect.objectContaining({ phone: "+15125552222", source: "sms", channel: "SMS" })
    );
  });

  it("appends to the existing lead's conversation instead of creating a duplicate", async () => {
    const existingLead = {
      id: "lead_1",
      businessId: "biz_1",
      firstName: "Jane",
      lastName: "Doe",
      status: "CONTACTED",
      optedOut: false,
      smsConsent: true,
    };
    mockPrisma.lead.findFirst.mockResolvedValue(existingLead);
    mockPrisma.conversation.findFirst.mockResolvedValue({ id: "convo_1", messages: [] });
    mockPrisma.usage.upsert.mockResolvedValue({ aiMessagesCount: 0 });
    mockPrisma.subscription.findUnique.mockResolvedValue({ plan: "STARTER" });
    mockGenerateBusinessReply.mockResolvedValue({ content: "Got it, when works for you?" });

    const res = await POST(formRequest({ From: "+15125552222", To: "+15555550100", Body: "Still leaking" }));

    expect(res.status).toBe(200);
    expect(mockCreateLead).not.toHaveBeenCalled();
    expect(mockPrisma.message.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ sender: "CUSTOMER", content: "Still leaking" }) })
    );
    const text = await res.text();
    expect(text).toContain("Got it, when works for you?");
  });

  it("marks the lead opted out on STOP and does not call the AI", async () => {
    const existingLead = { id: "lead_1", businessId: "biz_1", optedOut: false, smsConsent: true, status: "NEW" };
    mockPrisma.lead.findFirst.mockResolvedValue(existingLead);

    const res = await POST(formRequest({ From: "+15125552222", To: "+15555550100", Body: "STOP" }));

    expect(res.status).toBe(200);
    expect(mockPrisma.lead.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ optedOut: true }) })
    );
    expect(mockGenerateBusinessReply).not.toHaveBeenCalled();
    const text = await res.text();
    expect(text).toMatch(/unsubscribed/i);
  });

  it("re-subscribes on START", async () => {
    const existingLead = { id: "lead_1", businessId: "biz_1", optedOut: true, smsConsent: false, status: "NEW" };
    mockPrisma.lead.findFirst.mockResolvedValue(existingLead);

    const res = await POST(formRequest({ From: "+15125552222", To: "+15555550100", Body: "START" }));

    expect(mockPrisma.lead.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ optedOut: false, smsConsent: true }) })
    );
    const text = await res.text();
    expect(text).toMatch(/resubscribed/i);
  });

  it("silently ignores a message from a lead who is currently opted out", async () => {
    const existingLead = { id: "lead_1", businessId: "biz_1", optedOut: true, smsConsent: false, status: "NEW" };
    mockPrisma.lead.findFirst.mockResolvedValue(existingLead);

    const res = await POST(formRequest({ From: "+15125552222", To: "+15555550100", Body: "hello?" }));

    expect(res.status).toBe(200);
    expect(mockPrisma.message.create).not.toHaveBeenCalled();
    expect(mockGenerateBusinessReply).not.toHaveBeenCalled();
  });
});
