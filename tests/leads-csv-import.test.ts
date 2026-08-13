import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Business } from "@prisma/client";

/**
 * The import itself: duplicate detection, business isolation, plan limits,
 * and — most importantly — the guarantee that importing a spreadsheet never
 * messages anybody.
 */

const mockPrisma = {
  lead: { findMany: vi.fn(), createMany: vi.fn(), create: vi.fn(), update: vi.fn() },
  leadEvent: { createMany: vi.fn(), create: vi.fn() },
  usage: { findUnique: vi.fn(), upsert: vi.fn(), update: vi.fn() },
  subscription: { findUnique: vi.fn() },
  conversation: { create: vi.fn() },
  message: { create: vi.fn() },
  followUp: { create: vi.fn(), count: vi.fn() },
  followUpSettings: { findUnique: vi.fn() },
  notification: { create: vi.fn() },
  $transaction: vi.fn(async (ops: unknown[]) => ops),
};
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

// Any of these firing during an import would mean a customer's spreadsheet
// just triggered outbound contact.
const mockSendSMS = vi.fn();
const mockSendEmail = vi.fn();
const mockGenerateReply = vi.fn();
const mockQualifyLead = vi.fn();
const mockNotifyBusiness = vi.fn();
const mockScheduleNextFollowUp = vi.fn();

vi.mock("@/lib/twilio/send-sms", () => ({ sendSMS: mockSendSMS }));
vi.mock("@/lib/resend/send-email", () => ({ sendEmail: mockSendEmail }));
vi.mock("@/lib/ai", () => ({
  generateBusinessReply: mockGenerateReply,
  qualifyLead: mockQualifyLead,
  AIUnavailableError: class extends Error {},
}));
vi.mock("@/lib/notifications", () => ({ notifyBusiness: mockNotifyBusiness }));
vi.mock("@/lib/follow-ups/schedule", () => ({
  scheduleNextFollowUp: mockScheduleNextFollowUp,
  isLeadEligibleForFollowUp: () => true,
}));

const { analyzeImport, runImport, parseMapping } = await import("@/lib/leads/import/run");
const { parseCsv } = await import("@/lib/leads/import/csv");
const { suggestMapping } = await import("@/lib/leads/import/fields");

const BUSINESS = { id: "biz_1", email: "owner@example.com" } as Business;
const OTHER_BUSINESS = { id: "biz_2", email: "other@example.com" } as Business;

function csv(...lines: string[]) {
  return parseCsv(lines.join("\n"));
}

const THREE_LEADS = [
  "first_name,last_name,email,phone",
  "John,Smith,john@example.com,+12125550123",
  "Sarah,Jones,sarah@example.com,+12125550124",
  "Miguel,Alvarez,miguel@example.com,+12125550125",
];

/** Sets the business's plan and how much of this month's allowance is used. */
function givenPlan(plan: "STARTER" | "GROWTH" | "PRO", leadsUsed = 0) {
  mockPrisma.subscription.findUnique.mockResolvedValue({ plan, status: "ACTIVE" });
  mockPrisma.usage.findUnique.mockResolvedValue({ leadsCount: leadsUsed });
}

/** The rows actually written by the last runImport. */
function insertedLeads() {
  return mockPrisma.lead.createMany.mock.calls.flatMap((call) => call[0].data);
}

beforeEach(() => {
  vi.clearAllMocks();
  mockPrisma.lead.findMany.mockResolvedValue([]);
  mockPrisma.lead.createMany.mockReturnValue({ __op: "createMany" });
  mockPrisma.leadEvent.createMany.mockReturnValue({ __op: "eventCreateMany" });
  mockPrisma.usage.update.mockReturnValue({ __op: "usageUpdate" });
  mockPrisma.usage.upsert.mockResolvedValue({ leadsCount: 0 });
  givenPlan("GROWTH", 0);
});

describe("a valid import", () => {
  it("writes every row into the existing leads table", async () => {
    const parsed = csv(...THREE_LEADS);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(3);
    expect(result.duplicatesSkipped).toBe(0);
    expect(result.invalidSkipped).toBe(0);

    const leads = insertedLeads();
    expect(leads).toHaveLength(3);
    expect(leads[0]).toMatchObject({
      businessId: "biz_1",
      firstName: "John",
      lastName: "Smith",
      email: "john@example.com",
      status: "NEW",
      temperature: "COLD",
      isDemo: false,
    });
  });

  it("counts imported leads against the same monthly usage counter", async () => {
    const parsed = csv(...THREE_LEADS);
    await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(mockPrisma.usage.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { leadsCount: { increment: 3 } } })
    );
  });

  it("writes the leads, their events and the usage counter in one transaction", async () => {
    const parsed = csv(...THREE_LEADS);
    await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    // Otherwise a partial failure could leave imported leads that don't
    // count against the plan.
    expect(mockPrisma.$transaction).toHaveBeenCalledTimes(1);
    const operations = mockPrisma.$transaction.mock.calls[0][0] as unknown[];
    expect(operations).toContainEqual({ __op: "usageUpdate" });
  });

  it("records a BULK_IMPORT audit event carrying the batch summary", async () => {
    const parsed = csv(...THREE_LEADS, "Dana,Lee,not-an-email,");
    await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "customers.csv");

    const events = mockPrisma.leadEvent.createMany.mock.calls.flatMap((call) => call[0].data);
    expect(events).toHaveLength(3);
    expect(events[0].type).toBe("BULK_IMPORT");
    expect(events[0].meta).toMatchObject({
      file_name: "customers.csv",
      rows_uploaded: 4,
      rows_imported: 3,
      duplicates_skipped: 0,
      invalid_rows: 1,
    });
  });

  it("reports partial results when some rows can't be used", async () => {
    const parsed = csv(
      "first_name,email",
      "John,john@example.com",
      "Sarah,broken-email",
      ",orphan@example.com",
      "Miguel,miguel@example.com"
    );
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(2);
    expect(result.invalidSkipped).toBe(2);
    expect(result.failedRows.map((r) => r.rowNumber)).toEqual([2, 3]);
    expect(result.failedRows[0].reason).toMatch(/email/i);
    expect(result.failedRows[1].reason).toMatch(/first name/i);
  });
});

describe("imported leads are never contacted", () => {
  it("sends nothing, generates nothing, and schedules no follow-up", async () => {
    const parsed = csv(...THREE_LEADS);
    await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(mockSendSMS).not.toHaveBeenCalled();
    expect(mockSendEmail).not.toHaveBeenCalled();
    expect(mockGenerateReply).not.toHaveBeenCalled();
    expect(mockQualifyLead).not.toHaveBeenCalled();
    expect(mockNotifyBusiness).not.toHaveBeenCalled();
    expect(mockScheduleNextFollowUp).not.toHaveBeenCalled();
    // No follow-up row means the cron has nothing to pick up either.
    expect(mockPrisma.followUp.create).not.toHaveBeenCalled();
    expect(mockPrisma.conversation.create).not.toHaveBeenCalled();
    expect(mockPrisma.message.create).not.toHaveBeenCalled();
  });

  it("stores no consent, so the send paths refuse them by default", async () => {
    const parsed = csv(...THREE_LEADS);
    await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    for (const lead of insertedLeads()) {
      expect(lead.smsConsent).toBe(false);
      expect(lead.emailConsent).toBe(false);
    }
  });
});

describe("duplicate detection", () => {
  it("skips a row whose email already exists for this business", async () => {
    mockPrisma.lead.findMany.mockResolvedValue([{ email: "John@Example.com", phone: null }]);

    const parsed = csv(...THREE_LEADS);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(2);
    expect(result.duplicatesSkipped).toBe(1);
    expect(insertedLeads().map((l) => l.email)).not.toContain("john@example.com");
  });

  it("skips a row whose phone already exists, however it was formatted", async () => {
    mockPrisma.lead.findMany.mockResolvedValue([{ email: null, phone: "(212) 555-0123" }]);

    const parsed = csv(...THREE_LEADS);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.duplicatesSkipped).toBe(1);
    expect(insertedLeads().map((l) => l.firstName)).toEqual(["Sarah", "Miguel"]);
  });

  it("skips duplicates inside the uploaded file itself, keeping the first", async () => {
    const parsed = csv(
      "first_name,email,phone",
      "John,john@example.com,+12125550123",
      "Johnny,JOHN@example.com,",
      "Jon,,212-555-0123",
      "Sarah,sarah@example.com,"
    );
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(2);
    expect(result.duplicatesSkipped).toBe(2);
    expect(insertedLeads().map((l) => l.firstName)).toEqual(["John", "Sarah"]);
  });

  it("explains each skipped duplicate in the error report", async () => {
    mockPrisma.lead.findMany.mockResolvedValue([{ email: "john@example.com", phone: null }]);

    const parsed = csv("first_name,email", "John,john@example.com", "Sarah,sarah@example.com");
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.failedRows[0].reason).toMatch(/already in your leads/i);
  });
});

describe("business data isolation", () => {
  it("only ever matches duplicates within the session's own business", async () => {
    const parsed = csv(...THREE_LEADS);
    await analyzeImport(BUSINESS, parsed, suggestMapping(parsed.headers));

    expect(mockPrisma.lead.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { businessId: "biz_1" } })
    );
  });

  it("stamps every imported lead with the session's business, not the file's", async () => {
    // A CSV column called "business_id" is not mappable at all, so even a
    // hostile file cannot redirect the import.
    const parsed = csv("first_name,email,business_id", "John,john@example.com,biz_2");
    const mapping = suggestMapping(parsed.headers);
    expect(mapping[2]).toBeNull();

    await runImport(OTHER_BUSINESS, parsed, mapping, "leads.csv");
    for (const lead of insertedLeads()) expect(lead.businessId).toBe("biz_2");
  });

  it("rejects a mapping that names a field the importer doesn't expose", async () => {
    expect(parseMapping(["firstName", "businessId"], 2)).toBeNull();
    expect(parseMapping(["firstName", "isDemo"], 2)).toBeNull();
    expect(parseMapping(["firstName", "qualificationScore"], 2)).toBeNull();
    // Wrong length, wrong types, and non-arrays are refused too.
    expect(parseMapping(["firstName"], 2)).toBeNull();
    expect(parseMapping([1, 2], 2)).toBeNull();
    expect(parseMapping("firstName", 1)).toBeNull();
    // A legitimate mapping still passes.
    expect(parseMapping(["firstName", null], 2)).toEqual(["firstName", null]);
  });
});

describe("plan limits are enforced server-side", () => {
  const fiveRows = [
    "first_name,email",
    "A,a@example.com",
    "B,b@example.com",
    "C,c@example.com",
    "D,d@example.com",
    "E,e@example.com",
  ];

  it("Starter stops at 100 leads a month", async () => {
    givenPlan("STARTER", 97);
    const parsed = csv(...fiveRows);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(3);
    expect(result.skippedOverLimit).toBe(2);
    expect(result.allowance.limit).toBe(100);
  });

  it("Growth stops at 500 leads a month", async () => {
    givenPlan("GROWTH", 498);
    const parsed = csv(...fiveRows);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(2);
    expect(result.allowance.limit).toBe(500);
  });

  it("Pro stops at 2,000 leads a month", async () => {
    givenPlan("PRO", 1999);
    const parsed = csv(...fiveRows);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(1);
    expect(result.allowance.limit).toBe(2000);
  });

  it("imports nothing once the allowance is used up", async () => {
    givenPlan("GROWTH", 500);
    const parsed = csv(...fiveRows);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.imported).toBe(0);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
    expect(mockPrisma.usage.update).not.toHaveBeenCalled();
  });

  it("tells the customer how much room is left before they confirm", async () => {
    givenPlan("GROWTH", 100);
    const parsed = csv(...fiveRows);
    const analysis = await analyzeImport(BUSINESS, parsed, suggestMapping(parsed.headers));

    expect(analysis.allowance).toMatchObject({
      planLabel: "Growth",
      limit: 500,
      used: 100,
      remaining: 400,
      willImport: 5,
      capped: false,
    });
  });

  it("enforces the Starter allowance for a lapsed subscription, not the stored plan", async () => {
    // A cancelled Pro subscriber must not keep importing at Pro volume.
    mockPrisma.subscription.findUnique.mockResolvedValue({ plan: "PRO", status: "CANCELED" });
    mockPrisma.usage.findUnique.mockResolvedValue({ leadsCount: 99 });

    const parsed = csv(...fiveRows);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "leads.csv");

    expect(result.allowance.limit).toBe(100);
    expect(result.imported).toBe(1);
  });
});

describe("preview", () => {
  it("classifies rows without writing anything", async () => {
    mockPrisma.lead.findMany.mockResolvedValue([{ email: "john@example.com", phone: null }]);

    const parsed = csv(
      "first_name,email",
      "John,john@example.com",
      "Sarah,sarah@example.com",
      "Bad,nope"
    );
    const analysis = await analyzeImport(BUSINESS, parsed, suggestMapping(parsed.headers));

    expect(analysis).toMatchObject({ totalRows: 3, ready: 1, duplicatesExisting: 1, invalid: 1 });
    expect(analysis.preview.map((r) => r.state)).toEqual(["duplicate", "ready", "invalid"]);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
    expect(mockPrisma.usage.update).not.toHaveBeenCalled();
  });

  it("shows at most ten rows while checking all of them", async () => {
    const rows = Array.from({ length: 40 }, (_, i) => `User${i},user${i}@example.com`);
    const parsed = csv("first_name,email", ...rows);
    const analysis = await analyzeImport(BUSINESS, parsed, suggestMapping(parsed.headers));

    expect(analysis.preview).toHaveLength(10);
    expect(analysis.totalRows).toBe(40);
    expect(analysis.ready).toBe(40);
  });
});

describe("volume", () => {
  it("imports 2,000 rows in batched inserts", async () => {
    givenPlan("PRO", 0);
    const rows = Array.from({ length: 2000 }, (_, i) => `User${i},user${i}@example.com`);
    const parsed = csv("first_name,email", ...rows);
    const result = await runImport(BUSINESS, parsed, suggestMapping(parsed.headers), "big.csv");

    expect(result.imported).toBe(2000);
    // 500 rows per statement, not 2,000 single inserts.
    expect(mockPrisma.lead.createMany).toHaveBeenCalledTimes(4);
    expect(mockPrisma.$transaction).toHaveBeenCalledTimes(1);
  });
});
