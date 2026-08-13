import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Plan switching must never hand out a higher plan before Stripe has taken
 * the money, and must never remove a plan the customer has already paid for.
 */

const mockSessionsCreate = vi.fn();
const mockSubsUpdate = vi.fn();
const mockSubsRetrieve = vi.fn();
const mockSchedCreate = vi.fn();
const mockSchedRetrieve = vi.fn();
const mockSchedUpdate = vi.fn();
const mockSchedRelease = vi.fn();

vi.mock("@/lib/stripe/client", () => ({
  getStripeClient: () => ({
    checkout: { sessions: { create: mockSessionsCreate } },
    subscriptions: { update: mockSubsUpdate, retrieve: mockSubsRetrieve },
    subscriptionSchedules: {
      create: mockSchedCreate,
      retrieve: mockSchedRetrieve,
      update: mockSchedUpdate,
      release: mockSchedRelease,
    },
  }),
  BillingUnavailableError: class extends Error {},
}));

const mockPrisma = { subscription: { findUnique: vi.fn() } };
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { changeSubscriptionPlan } = await import("@/lib/stripe/checkout");

const BUSINESS = { id: "biz_1", email: "owner@example.com" } as never;
const PERIOD_END = 1_800_000_000;

const PRICES = { STARTER: "price_starter", GROWTH: "price_growth", PRO: "price_pro" };

/** A live Stripe subscription currently on `plan`. */
function stripeSubOn(plan: keyof typeof PRICES, extra: Record<string, unknown> = {}) {
  return {
    id: "sub_live",
    schedule: null,
    items: {
      data: [{ id: "si_1", price: { id: PRICES[plan] }, current_period_end: PERIOD_END }],
    },
    ...extra,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.STRIPE_PRICE_STARTER = PRICES.STARTER;
  process.env.STRIPE_PRICE_GROWTH = PRICES.GROWTH;
  process.env.STRIPE_PRICE_PRO = PRICES.PRO;
  mockPrisma.subscription.findUnique.mockResolvedValue({
    businessId: "biz_1",
    stripeSubscriptionId: "sub_live",
    plan: "STARTER",
    status: "ACTIVE",
  });
});

describe("upgrades are charged immediately and only granted on success", () => {
  it("Starter -> Growth invoices now and fails closed if payment can't complete", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("STARTER"));
    mockSubsUpdate.mockResolvedValue({});

    const result = await changeSubscriptionPlan(BUSINESS, "GROWTH");

    expect(result).toEqual({ kind: "upgraded" });
    const params = mockSubsUpdate.mock.calls[0][1];
    expect(params.items).toEqual([{ id: "si_1", price: PRICES.GROWTH }]);
    // Bill the proration now, not on the next invoice...
    expect(params.proration_behavior).toBe("always_invoice");
    // ...and refuse the change outright if that payment can't be taken.
    expect(params.payment_behavior).toBe("error_if_incomplete");
  });

  it("Starter -> Pro and Growth -> Pro use the same immediate-charge path", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("STARTER"));
    mockSubsUpdate.mockResolvedValue({});
    expect((await changeSubscriptionPlan(BUSINESS, "PRO")).kind).toBe("upgraded");

    vi.clearAllMocks();
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: "sub_live",
      plan: "GROWTH",
      status: "ACTIVE",
    });
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("GROWTH"));
    mockSubsUpdate.mockResolvedValue({});
    expect((await changeSubscriptionPlan(BUSINESS, "PRO")).kind).toBe("upgraded");
    expect(mockSubsUpdate.mock.calls[0][1].proration_behavior).toBe("always_invoice");
  });

  it("a declined upgrade payment propagates and never schedules anything", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("STARTER"));
    mockSubsUpdate.mockRejectedValue(new Error("Your card was declined."));

    await expect(changeSubscriptionPlan(BUSINESS, "PRO")).rejects.toThrow("Your card was declined.");

    // Nothing else was written; the customer stays on Starter until the
    // webhook says otherwise (and no webhook fires, because Stripe rejected).
    expect(mockSchedCreate).not.toHaveBeenCalled();
    expect(mockSchedUpdate).not.toHaveBeenCalled();
  });

  it("releases a pending downgrade schedule before upgrading", async () => {
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("GROWTH", { schedule: "sub_sched_1" }));
    mockSubsUpdate.mockResolvedValue({});
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: "sub_live",
      plan: "GROWTH",
      status: "ACTIVE",
    });

    await changeSubscriptionPlan(BUSINESS, "PRO");

    // Otherwise the old schedule would later revert the plan they just paid for.
    expect(mockSchedRelease).toHaveBeenCalledWith("sub_sched_1");
  });
});

describe("downgrades are scheduled, not applied immediately", () => {
  beforeEach(() => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: "sub_live",
      plan: "PRO",
      status: "ACTIVE",
    });
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO"));
    mockSchedCreate.mockResolvedValue({ id: "sub_sched_new" });
    mockSchedRetrieve.mockResolvedValue({
      id: "sub_sched_new",
      phases: [{ start_date: 1_700_000_000, end_date: PERIOD_END }],
    });
    mockSchedUpdate.mockResolvedValue({});
  });

  it("Pro -> Starter keeps Pro until period end and charges nothing now", async () => {
    const result = await changeSubscriptionPlan(BUSINESS, "STARTER");

    expect(result).toEqual({ kind: "downgrade_scheduled", effectiveAt: new Date(PERIOD_END * 1000) });
    // The subscription price is NOT changed now.
    expect(mockSubsUpdate).not.toHaveBeenCalled();

    const phases = mockSchedUpdate.mock.calls[0][1].phases;
    expect(phases).toHaveLength(2);
    // Phase 1 keeps the paid-for Pro price until the period ends...
    expect(phases[0].items[0].price).toBe(PRICES.PRO);
    expect(phases[0].end_date).toBe(PERIOD_END);
    // ...phase 2 switches to the cheaper plan afterwards.
    expect(phases[1].items[0].price).toBe(PRICES.STARTER);
  });

  it("Pro -> Growth schedules the same way", async () => {
    const result = await changeSubscriptionPlan(BUSINESS, "GROWTH");
    expect(result.kind).toBe("downgrade_scheduled");
    expect(mockSchedUpdate.mock.calls[0][1].phases[1].items[0].price).toBe(PRICES.GROWTH);
    expect(mockSubsUpdate).not.toHaveBeenCalled();
  });
});

describe("idempotency / repeated clicks", () => {
  it("switching to the plan already active is a no-op", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: "sub_live",
      plan: "GROWTH",
      status: "ACTIVE",
    });
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("GROWTH"));

    const result = await changeSubscriptionPlan(BUSINESS, "GROWTH");

    expect(result).toEqual({ kind: "unchanged" });
    expect(mockSubsUpdate).not.toHaveBeenCalled();
    expect(mockSchedCreate).not.toHaveBeenCalled();
  });

  it("current plan is read from Stripe, not our database, so a stale row can't cause a double charge", async () => {
    // DB still says STARTER but Stripe already moved to PRO (webhook lagging).
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: "sub_live",
      plan: "STARTER",
      status: "ACTIVE",
    });
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO"));

    const result = await changeSubscriptionPlan(BUSINESS, "PRO");

    expect(result).toEqual({ kind: "unchanged" });
    expect(mockSubsUpdate).not.toHaveBeenCalled();
  });

  it("a second downgrade click reuses the existing schedule instead of creating another", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeSubscriptionId: "sub_live",
      plan: "PRO",
      status: "ACTIVE",
    });
    mockSubsRetrieve.mockResolvedValue(stripeSubOn("PRO", { schedule: { id: "sub_sched_existing" } }));
    mockSchedRetrieve.mockResolvedValue({
      id: "sub_sched_existing",
      phases: [{ start_date: 1_700_000_000, end_date: PERIOD_END }],
    });
    mockSchedUpdate.mockResolvedValue({});

    await changeSubscriptionPlan(BUSINESS, "STARTER");

    // Stripe rejects a second schedule for the same subscription.
    expect(mockSchedCreate).not.toHaveBeenCalled();
    expect(mockSchedUpdate).toHaveBeenCalledWith("sub_sched_existing", expect.anything());
  });
});

describe("webhook remains the source of truth", () => {
  it("changeSubscriptionPlan never writes plan or status itself", async () => {
    const writeSpy = vi.fn();
    // Any write would have to go through prisma.subscription, which this
    // module only ever reads from.
    (mockPrisma.subscription as unknown as Record<string, unknown>).update = writeSpy;
    (mockPrisma.subscription as unknown as Record<string, unknown>).upsert = writeSpy;

    mockSubsRetrieve.mockResolvedValue(stripeSubOn("STARTER"));
    mockSubsUpdate.mockResolvedValue({});
    await changeSubscriptionPlan(BUSINESS, "GROWTH");

    expect(writeSpy).not.toHaveBeenCalled();
  });

  it("reconciles whatever Stripe reports: the webhook's price id decides the plan", async () => {
    const { planFromPriceId } = await import("@/lib/plans");
    const { mapStripeStatus } = await import("@/lib/stripe/status");

    // Upgrade landed and was paid.
    expect(planFromPriceId(PRICES.PRO)).toBe("PRO");
    expect(mapStripeStatus("active" as never)).toBe("ACTIVE");

    // Scheduled downgrade fires later with the cheaper price.
    expect(planFromPriceId(PRICES.STARTER)).toBe("STARTER");
  });
});
