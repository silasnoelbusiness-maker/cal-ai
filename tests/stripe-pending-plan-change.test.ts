import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/**
 * The billing page's pending-change notice must reflect Stripe exactly:
 * never invent a downgrade that isn't scheduled, never hide one that is,
 * and never take the page down when Stripe is unreachable.
 */

const mockSubsRetrieve = vi.fn();
const mockSchedRetrieve = vi.fn();
const mockSchedRelease = vi.fn();

vi.mock("@/lib/stripe/client", () => ({
  getStripeClient: () => ({
    checkout: { sessions: { create: vi.fn() } },
    subscriptions: { update: vi.fn(), retrieve: mockSubsRetrieve },
    subscriptionSchedules: {
      create: vi.fn(),
      retrieve: mockSchedRetrieve,
      update: vi.fn(),
      release: mockSchedRelease,
    },
  }),
  BillingUnavailableError: class extends Error {},
}));

const mockPrisma = {
  subscription: { findUnique: vi.fn(), update: vi.fn(), upsert: vi.fn() },
};
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { getPendingPlanChange, cancelScheduledPlanChange } = await import("@/lib/stripe/checkout");

const PRICES = { STARTER: "price_starter", GROWTH: "price_growth", PRO: "price_pro" };
const BUSINESS = { id: "biz_1", email: "owner@example.com" } as never;

const NOW = Math.floor(Date.now() / 1000);
const PERIOD_START = NOW - 10 * 24 * 3600;
const PERIOD_END = NOW + 20 * 24 * 3600;

/** A live Stripe subscription on `plan`, optionally carrying a schedule. */
function stripeSubOn(plan: keyof typeof PRICES, schedule: unknown = null) {
  return {
    id: "sub_live",
    schedule,
    items: { data: [{ id: "si_1", price: { id: PRICES[plan] }, current_period_end: PERIOD_END }] },
  };
}

/** A two-phase schedule: current plan until PERIOD_END, then `to`. */
function scheduleTo(to: keyof typeof PRICES, from: keyof typeof PRICES, extra: Record<string, unknown> = {}) {
  return {
    id: "sub_sched_1",
    status: "active",
    phases: [
      { start_date: PERIOD_START, end_date: PERIOD_END, items: [{ price: PRICES[from], quantity: 1 }] },
      { start_date: PERIOD_END, end_date: PERIOD_END + 30 * 24 * 3600, items: [{ price: PRICES[to], quantity: 1 }] },
    ],
    ...extra,
  };
}

const LIVE_SUB = { stripeSubscriptionId: "sub_live", plan: "PRO" as const, status: "ACTIVE" };

beforeEach(() => {
  vi.clearAllMocks();
  process.env.STRIPE_PRICE_STARTER = PRICES.STARTER;
  process.env.STRIPE_PRICE_GROWTH = PRICES.GROWTH;
  process.env.STRIPE_PRICE_PRO = PRICES.PRO;
  vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("reading the pending change from Stripe", () => {
  it("reports the destination plan and the date it takes effect", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));
    mockSchedRetrieve.mockResolvedValue(scheduleTo("STARTER", "PRO"));

    const pending = await getPendingPlanChange(LIVE_SUB);

    expect(pending).toEqual({
      fromPlan: "PRO",
      toPlan: "STARTER",
      effectiveAt: new Date(PERIOD_END * 1000),
    });
  });

  it("takes the current plan from Stripe, not the database row", async () => {
    // Webhook lagging: our row still says STARTER while Stripe bills Growth.
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("GROWTH", "sub_sched_1"));
    mockSchedRetrieve.mockResolvedValue(scheduleTo("STARTER", "GROWTH"));

    const pending = await getPendingPlanChange({ ...LIVE_SUB, plan: "STARTER" });

    expect(pending?.fromPlan).toBe("GROWTH");
    expect(pending?.toPlan).toBe("STARTER");
  });

  it("accepts a schedule whose phase prices are expanded objects", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", { id: "sub_sched_1" }));
    mockSchedRetrieve.mockResolvedValue({
      id: "sub_sched_1",
      status: "active",
      phases: [
        { start_date: PERIOD_START, end_date: PERIOD_END, items: [{ price: { id: PRICES.PRO } }] },
        { start_date: PERIOD_END, items: [{ price: { id: PRICES.GROWTH } }] },
      ],
    });

    expect((await getPendingPlanChange(LIVE_SUB))?.toPlan).toBe("GROWTH");
  });
});

describe("nothing is shown unless a change is really pending", () => {
  it("no schedule on the subscription", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO"));
    expect(await getPendingPlanChange(LIVE_SUB)).toBeNull();
    expect(mockSchedRetrieve).not.toHaveBeenCalled();
  });

  it("a released schedule is not a pending change", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));
    mockSchedRetrieve.mockResolvedValue(scheduleTo("STARTER", "PRO", { status: "released" }));

    expect(await getPendingPlanChange(LIVE_SUB)).toBeNull();
  });

  it("a schedule with no future phase is not a pending change", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));
    mockSchedRetrieve.mockResolvedValue({
      id: "sub_sched_1",
      status: "active",
      phases: [{ start_date: PERIOD_START, end_date: PERIOD_END, items: [{ price: PRICES.PRO }] }],
    });

    expect(await getPendingPlanChange(LIVE_SUB)).toBeNull();
  });

  it("a future phase on the same plan is not a change", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));
    mockSchedRetrieve.mockResolvedValue(scheduleTo("PRO", "PRO"));

    expect(await getPendingPlanChange(LIVE_SUB)).toBeNull();
  });

  it("an unrecognised price id is never guessed at", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));
    mockSchedRetrieve.mockResolvedValue({
      id: "sub_sched_1",
      status: "active",
      phases: [
        { start_date: PERIOD_START, end_date: PERIOD_END, items: [{ price: PRICES.PRO }] },
        { start_date: PERIOD_END, items: [{ price: "price_from_another_account" }] },
      ],
    });

    expect(await getPendingPlanChange(LIVE_SUB)).toBeNull();
  });

  it("businesses Stripe isn't billing are never queried at all", async () => {
    expect(await getPendingPlanChange(null)).toBeNull();
    expect(await getPendingPlanChange({ stripeSubscriptionId: null, plan: "PRO", status: "ACTIVE" })).toBeNull();
    expect(
      await getPendingPlanChange({ stripeSubscriptionId: "sub_live", plan: "PRO", status: "CANCELED" })
    ).toBeNull();
    expect(mockSubsRetrieve).not.toHaveBeenCalled();
  });

  it("a Stripe outage degrades to no notice instead of breaking the billing page", async () => {
    mockSubsRetrieve.mockRejectedValue(new Error("Stripe is down"));

    expect(await getPendingPlanChange(LIVE_SUB)).toBeNull();
  });
});

describe("keeping the current plan", () => {
  beforeEach(() => {
    mockPrisma.subscription.findUnique.mockResolvedValue(LIVE_SUB);
  });

  it("releases the schedule so the current plan simply keeps renewing", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));

    expect(await cancelScheduledPlanChange(BUSINESS)).toEqual({ released: true });
    expect(mockSchedRelease).toHaveBeenCalledWith("sub_sched_1");
  });

  it("resolves an expanded schedule object to its id", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", { id: "sub_sched_2" }));

    await cancelScheduledPlanChange(BUSINESS);

    expect(mockSchedRelease).toHaveBeenCalledWith("sub_sched_2");
  });

  it("is a no-op when there is nothing scheduled", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO"));

    expect(await cancelScheduledPlanChange(BUSINESS)).toEqual({ released: false });
    expect(mockSchedRelease).not.toHaveBeenCalled();
  });

  it("refuses when the business has no subscription Stripe is billing", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: null,
      plan: "PRO",
      status: "NONE",
    });

    await expect(cancelScheduledPlanChange(BUSINESS)).rejects.toThrow("No active subscription");
    expect(mockSubsRetrieve).not.toHaveBeenCalled();
  });

  it("never writes plan or status itself — the webhook stays the source of truth", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", "sub_sched_1"));

    await cancelScheduledPlanChange(BUSINESS);

    expect(mockPrisma.subscription.update).not.toHaveBeenCalled();
    expect(mockPrisma.subscription.upsert).not.toHaveBeenCalled();
  });
});
