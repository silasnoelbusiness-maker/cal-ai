import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { isAdminEmail, adminEmails, hasAdminsConfigured } from "@/lib/admin/config";

const ORIGINAL = process.env.ADMIN_EMAILS;

afterEach(() => {
  if (ORIGINAL === undefined) delete process.env.ADMIN_EMAILS;
  else process.env.ADMIN_EMAILS = ORIGINAL;
});

describe("admin allowlist", () => {
  it("fails shut when ADMIN_EMAILS is unset — nobody is an admin", () => {
    delete process.env.ADMIN_EMAILS;
    expect(hasAdminsConfigured()).toBe(false);
    expect(isAdminEmail("anyone@example.com")).toBe(false);
    expect(isAdminEmail("")).toBe(false);
    expect(isAdminEmail(null)).toBe(false);
  });

  it("fails shut when ADMIN_EMAILS is empty or only separators", () => {
    process.env.ADMIN_EMAILS = "  , ,";
    expect(adminEmails()).toEqual([]);
    expect(isAdminEmail("anyone@example.com")).toBe(false);
  });

  it("recognises a configured admin, case- and whitespace-insensitively", () => {
    process.env.ADMIN_EMAILS = " You@Converana.com , ops@converana.com ";
    expect(isAdminEmail("you@converana.com")).toBe(true);
    expect(isAdminEmail("YOU@CONVERANA.COM")).toBe(true);
    expect(isAdminEmail("  ops@converana.com ")).toBe(true);
  });

  it("rejects a normal user — they cannot activate themselves", () => {
    process.env.ADMIN_EMAILS = "you@converana.com";
    expect(isAdminEmail("customer@example.com")).toBe(false);
  });

  it("does not match on substrings or lookalike domains", () => {
    process.env.ADMIN_EMAILS = "you@converana.com";
    expect(isAdminEmail("you@converana.com.evil.com")).toBe(false);
    expect(isAdminEmail("notyou@converana.com")).toBe(false);
    expect(isAdminEmail("you@converana.co")).toBe(false);
  });
});

// --- access mutations -------------------------------------------------------

const mockPrisma = {
  user: { findUnique: vi.fn() },
  businessMember: { findFirst: vi.fn() },
  subscription: { upsert: vi.fn(), update: vi.fn(), findUnique: vi.fn() },
};
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { grantPaidAccess, revokePaidAccess } = await import("@/lib/admin/access");

const BUSINESS = { id: "biz_1", name: "PeakFlow HVAC" };

describe("grantPaidAccess", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.user.findUnique.mockResolvedValue({ id: "user_1", email: "owner@example.com" });
    mockPrisma.businessMember.findFirst.mockResolvedValue({ business: BUSINESS });
  });

  it("writes the existing Subscription row with ACTIVE status and the chosen plan", async () => {
    const result = await grantPaidAccess("owner@example.com", "GROWTH");

    expect(result.ok).toBe(true);
    expect(mockPrisma.subscription.upsert).toHaveBeenCalledWith({
      where: { businessId: "biz_1" },
      create: { businessId: "biz_1", plan: "GROWTH", status: "ACTIVE" },
      update: { plan: "GROWTH", status: "ACTIVE" },
    });
  });

  it("normalises the email before lookup", async () => {
    await grantPaidAccess("  Owner@Example.COM ", "PRO");
    expect(mockPrisma.user.findUnique).toHaveBeenCalledWith({ where: { email: "owner@example.com" } });
  });

  it("is idempotent — repeating a grant produces the same terminal state", async () => {
    await grantPaidAccess("owner@example.com", "PRO");
    await grantPaidAccess("owner@example.com", "PRO");
    const calls = mockPrisma.subscription.upsert.mock.calls;
    expect(calls[0][0].update).toEqual(calls[1][0].update);
  });

  it("refuses when no Converana account exists for that email", async () => {
    mockPrisma.user.findUnique.mockResolvedValue(null);
    const result = await grantPaidAccess("nobody@example.com", "STARTER");
    expect(result.ok).toBe(false);
    expect(mockPrisma.subscription.upsert).not.toHaveBeenCalled();
  });

  it("refuses when the account has no business yet", async () => {
    mockPrisma.businessMember.findFirst.mockResolvedValue(null);
    const result = await grantPaidAccess("owner@example.com", "STARTER");
    expect(result.ok).toBe(false);
    expect(mockPrisma.subscription.upsert).not.toHaveBeenCalled();
  });
});

describe("revokePaidAccess", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.user.findUnique.mockResolvedValue({ id: "user_1", email: "owner@example.com" });
    mockPrisma.businessMember.findFirst.mockResolvedValue({ business: BUSINESS });
    mockPrisma.subscription.findUnique.mockResolvedValue({ businessId: "biz_1", plan: "PRO", status: "ACTIVE" });
  });

  it("cancels rather than deleting, so the row and last plan survive", async () => {
    const result = await revokePaidAccess("owner@example.com");

    expect(result.ok).toBe(true);
    expect(mockPrisma.subscription.update).toHaveBeenCalledWith({
      where: { businessId: "biz_1" },
      data: { status: "CANCELED" },
    });
  });

  it("does nothing when there is no subscription to revoke", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue(null);
    const result = await revokePaidAccess("owner@example.com");
    expect(result.ok).toBe(false);
    expect(mockPrisma.subscription.update).not.toHaveBeenCalled();
  });
});

// --- the revoked plan must actually stop granting limits --------------------

describe("revocation actually removes paid access", () => {
  it("effectivePlan drops a CANCELED Pro subscription back to Starter", async () => {
    const { effectivePlan } = await import("@/lib/plans");
    expect(effectivePlan({ plan: "PRO", status: "ACTIVE" })).toBe("PRO");
    expect(effectivePlan({ plan: "PRO", status: "CANCELED" })).toBe("STARTER");
  });
});
