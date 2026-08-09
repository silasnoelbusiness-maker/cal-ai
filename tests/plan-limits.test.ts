import { describe, expect, it } from "vitest";
import { checkPlanLimit, currentMonthKey, effectivePlan, planFromPriceId, PLAN_LIMITS } from "@/lib/plans";

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

describe("effectivePlan", () => {
  it("grants the subscribed plan while active", () => {
    expect(effectivePlan({ plan: "PRO", status: "ACTIVE" })).toBe("PRO");
  });

  it("grants the subscribed plan while trialing", () => {
    expect(effectivePlan({ plan: "GROWTH", status: "TRIALING" })).toBe("GROWTH");
  });

  it("still grants the plan during a payment retry (past_due) — a grace period, not an instant cutoff", () => {
    expect(effectivePlan({ plan: "PRO", status: "PAST_DUE" })).toBe("PRO");
  });

  it("falls back to STARTER once a subscription is canceled, regardless of what plan it was", () => {
    expect(effectivePlan({ plan: "PRO", status: "CANCELED" })).toBe("STARTER");
  });

  it("falls back to STARTER for unpaid or incomplete subscriptions", () => {
    expect(effectivePlan({ plan: "GROWTH", status: "UNPAID" })).toBe("STARTER");
    expect(effectivePlan({ plan: "GROWTH", status: "INCOMPLETE" })).toBe("STARTER");
  });

  it("falls back to STARTER when there's no subscription record at all", () => {
    expect(effectivePlan(null)).toBe("STARTER");
    expect(effectivePlan(undefined)).toBe("STARTER");
  });

  it("falls back to STARTER for a NONE status (never subscribed)", () => {
    expect(effectivePlan({ plan: "STARTER", status: "NONE" })).toBe("STARTER");
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
