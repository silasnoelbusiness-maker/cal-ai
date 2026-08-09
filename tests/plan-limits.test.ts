import { describe, expect, it } from "vitest";
import { checkPlanLimit, currentMonthKey, planFromPriceId, PLAN_LIMITS } from "@/lib/plans";

describe("checkPlanLimit", () => {
  it("allows usage below the plan's lead limit", () => {
    const result = checkPlanLimit("STARTER", "leads", { leadsCount: 50, aiMessagesCount: 0 });
    expect(result.allowed).toBe(true);
    expect(result.remaining).toBe(PLAN_LIMITS.STARTER.leadsPerMonth - 50);
    expect(result.message).toBeUndefined();
  });

  it("blocks usage at or above the plan's lead limit", () => {
    const result = checkPlanLimit("STARTER", "leads", { leadsCount: 100, aiMessagesCount: 0 });
    expect(result.allowed).toBe(false);
    expect(result.remaining).toBe(0);
    expect(result.message).toMatch(/upgrade/i);
  });

  it("checks AI message limits independently of lead limits", () => {
    const result = checkPlanLimit("GROWTH", "aiMessages", { leadsCount: 0, aiMessagesCount: 2500 });
    expect(result.allowed).toBe(false);
    expect(result.limit).toBe(PLAN_LIMITS.GROWTH.aiMessagesPerMonth);
  });

  it("checks team member limits against current user count", () => {
    const allowed = checkPlanLimit("STARTER", "users", { leadsCount: 0, aiMessagesCount: 0 }, 0);
    expect(allowed.allowed).toBe(true);

    const blocked = checkPlanLimit("STARTER", "users", { leadsCount: 0, aiMessagesCount: 0 }, 1);
    expect(blocked.allowed).toBe(false);
    expect(blocked.message).toMatch(/1 team member/);
  });

  it("scales limits up across plan tiers", () => {
    expect(PLAN_LIMITS.STARTER.leadsPerMonth).toBeLessThan(PLAN_LIMITS.GROWTH.leadsPerMonth);
    expect(PLAN_LIMITS.GROWTH.leadsPerMonth).toBeLessThan(PLAN_LIMITS.PRO.leadsPerMonth);
  });
});

describe("currentMonthKey", () => {
  it("formats as YYYY-MM", () => {
    const key = currentMonthKey(new Date(2026, 0, 15));
    expect(key).toBe("2026-01");
  });

  it("pads single-digit months", () => {
    const key = currentMonthKey(new Date(2026, 8, 1));
    expect(key).toBe("2026-09");
  });
});

describe("planFromPriceId", () => {
  it("returns null for an unrecognized price id", () => {
    expect(planFromPriceId("price_unknown")).toBeNull();
  });

  it("returns null for a missing price id", () => {
    expect(planFromPriceId(undefined)).toBeNull();
    expect(planFromPriceId(null)).toBeNull();
  });
});
