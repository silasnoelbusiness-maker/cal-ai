import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * The HTTP surface of CSV import: who may call it, what files it accepts,
 * and the fact that the browser can't talk it into importing more than the
 * plan allows.
 */

const mockAuth = vi.fn();
vi.mock("@/lib/auth/session", () => ({ getApiAuthContext: mockAuth }));

const mockRateLimit = vi.fn(() => ({ allowed: true, retryAfterMs: 0 }));
vi.mock("@/lib/api/rate-limit", () => ({ rateLimit: mockRateLimit }));

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const mockPrisma = {
  lead: { findMany: vi.fn(), createMany: vi.fn() },
  leadEvent: { createMany: vi.fn() },
  usage: { findUnique: vi.fn(), upsert: vi.fn(), update: vi.fn() },
  subscription: { findUnique: vi.fn() },
  $transaction: vi.fn(async (ops: unknown[]) => ops),
};
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { POST: importRoute } = await import("@/app/api/leads/import/route");
const { POST: previewRoute } = await import("@/app/api/leads/import/preview/route");
const { GET: sampleRoute } = await import("@/app/api/leads/import/sample/route");
const { CSV_MAX_BYTES } = await import("@/lib/leads/import/csv");

const VALID_CSV = "first_name,email\nJohn,john@example.com\nSarah,sarah@example.com\n";

function request(file: File | null, mapping?: unknown) {
  const formData = new FormData();
  if (file) formData.set("file", file);
  if (mapping !== undefined) formData.set("mapping", JSON.stringify(mapping));
  return { formData: async () => formData } as never;
}

function csvFile(content = VALID_CSV, name = "leads.csv") {
  return new File([content], name, { type: "text/csv" });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockRateLimit.mockReturnValue({ allowed: true, retryAfterMs: 0 });
  mockAuth.mockResolvedValue({ user: { id: "user_1" }, business: { id: "biz_1" } });
  mockPrisma.lead.findMany.mockResolvedValue([]);
  mockPrisma.usage.findUnique.mockResolvedValue({ leadsCount: 0 });
  mockPrisma.usage.upsert.mockResolvedValue({ leadsCount: 0 });
  mockPrisma.subscription.findUnique.mockResolvedValue({ plan: "GROWTH", status: "ACTIVE" });
});

describe("authentication", () => {
  it("refuses an unauthenticated import", async () => {
    mockAuth.mockResolvedValue(null);

    const res = await importRoute(request(csvFile()));

    expect(res.status).toBe(401);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
  });

  it("refuses an unauthenticated preview, so the file is never even parsed", async () => {
    mockAuth.mockResolvedValue(null);
    expect((await previewRoute(request(csvFile()))).status).toBe(401);
    expect(mockPrisma.lead.findMany).not.toHaveBeenCalled();
  });

  it("refuses to hand out the sample file to a signed-out visitor", async () => {
    mockAuth.mockResolvedValue(null);
    expect((await sampleRoute()).status).toBe(401);
  });

  it("rate limits imports per business", async () => {
    mockRateLimit.mockReturnValue({ allowed: false, retryAfterMs: 30_000 });

    const res = await importRoute(request(csvFile()));

    expect(res.status).toBe(429);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
  });
});

describe("file handling", () => {
  it("imports a well-formed CSV", async () => {
    const res = await importRoute(request(csvFile()));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.imported).toBe(2);
  });

  it("rejects a spreadsheet with instructions instead of a generic error", async () => {
    const res = await importRoute(request(new File(["binary"], "leads.xlsx")));
    const body = await res.json();

    expect(res.status).toBe(400);
    expect(body.error).toMatch(/CSV/);
    expect(body.error).toMatch(/Save as|Export/i);
  });

  it("rejects other unsupported file types", async () => {
    for (const name of ["leads.pdf", "leads.json", "photo.png", "script.js"]) {
      const res = await importRoute(request(new File(["x"], name)));
      expect(res.status, name).toBe(400);
    }
  });

  it("rejects a missing file", async () => {
    expect((await importRoute(request(null))).status).toBe(400);
  });

  it("rejects an empty file", async () => {
    expect((await importRoute(request(new File([], "leads.csv")))).status).toBe(400);
  });

  it("rejects an oversized file with 413 before parsing it", async () => {
    const huge = new File(["x".repeat(CSV_MAX_BYTES + 1)], "leads.csv");
    const res = await importRoute(request(huge));

    expect(res.status).toBe(413);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
  });

  it("turns a malformed CSV into a readable 400, never a 500", async () => {
    const res = await importRoute(request(csvFile('first_name,email\n"John,john@example.com')));
    const body = await res.json();

    expect(res.status).toBe(400);
    expect(body.error).toMatch(/quote/i);
  });
});

describe("the client cannot widen what gets imported", () => {
  it("refuses a mapping naming a field the importer doesn't expose", async () => {
    const res = await importRoute(request(csvFile(), ["firstName", "businessId"]));
    const body = await res.json();

    expect(res.status).toBe(400);
    expect(body.error).toMatch(/mapping/i);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
  });

  it("refuses a mapping that doesn't line up with the file's columns", async () => {
    expect((await importRoute(request(csvFile(), ["firstName"]))).status).toBe(400);
    expect((await importRoute(request(csvFile(), "firstName"))).status).toBe(400);
  });

  it("requires a first name column and at least one contact column", async () => {
    const noName = await importRoute(request(csvFile(), [null, "email"]));
    expect(await noName.json()).toMatchObject({ error: expect.stringMatching(/First Name/i) });

    const noContact = await importRoute(request(csvFile(), ["firstName", null]));
    expect(await noContact.json()).toMatchObject({ error: expect.stringMatching(/Email or Phone/i) });

    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
  });

  it("caps the import at the plan allowance no matter what the client asks for", async () => {
    mockPrisma.usage.findUnique.mockResolvedValue({ leadsCount: 499 });

    const res = await importRoute(request(csvFile()));
    const body = await res.json();

    // Two valid rows, one seat left on Growth.
    expect(body.imported).toBe(1);
    expect(body.skippedOverLimit).toBe(1);
  });

  it("scopes the import to the session's business, ignoring anything in the file", async () => {
    await importRoute(request(csvFile("first_name,email,business_id\nJohn,john@example.com,biz_999")));

    const written = mockPrisma.lead.createMany.mock.calls.flatMap((call) => call[0].data);
    expect(written.every((lead: { businessId: string }) => lead.businessId === "biz_1")).toBe(true);
  });
});

describe("preview", () => {
  it("returns headers, a suggested mapping and per-row validation without writing", async () => {
    const res = await previewRoute(request(csvFile()));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.headers).toEqual(["first_name", "email"]);
    expect(body.mapping).toEqual(["firstName", "email"]);
    expect(body.ready).toBe(2);
    expect(body.allowance.remaining).toBe(500);
    expect(mockPrisma.lead.createMany).not.toHaveBeenCalled();
  });
});

describe("sample file", () => {
  it("serves a CSV of clearly fictional contacts", async () => {
    const res = await sampleRoute();
    const text = await res.text();

    expect(res.headers.get("Content-Type")).toMatch(/text\/csv/);
    expect(res.headers.get("Content-Disposition")).toMatch(/converana-sample-leads\.csv/);
    // RFC 2606 reserved domain and the 555-01xx fiction range: importing
    // this file can never reach a real person.
    expect(text).toContain("@example.com");
    expect(text).toContain("+12125550123");
  });

  it("round-trips through the importer with its phone numbers intact", async () => {
    const text = await (await sampleRoute()).text();

    await importRoute(request(new File([text], "converana-sample-leads.csv")));

    const written = mockPrisma.lead.createMany.mock.calls.flatMap((call) => call[0].data);
    expect(written).toHaveLength(5);
    // The formula guard must not have mangled the E.164 numbers on the way
    // out — otherwise our own sample file imports broken phone numbers.
    expect(written[0].phone).toBe("+12125550123");
    expect(written[0].email).toBe("john.smith@example.com");
  });
});
