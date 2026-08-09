import { beforeEach, describe, expect, it, vi } from "vitest";

const mockBusiness = { id: "biz_1", email: "owner@test.com" };

const mockPrisma = { subscription: { findUnique: vi.fn() } };
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const mockStripeClient = {
  checkout: { sessions: { create: vi.fn() } },
  subscriptions: { retrieve: vi.fn(), update: vi.fn() },
};
vi.mock("@/lib/stripe/client", () => ({
  getStripeClient: () => mockStripeClient,
  BillingUnavailableError: class BillingUnavailableError extends Error {},
}));

process.env.STRIPE_PRICE_STARTER = "price_starter";
process.env.STRIPE_PRICE_GROWTH = "price_growth";
process.env.STRIPE_PRICE_PRO = "price_pro";

const { createCheckoutSession, changeSubscriptionPlan, hasBillableSubscription } = await import(
  "@/lib/stripe/checkout"
);

describe("hasBillableSubscription", () => {
  it("is true for an active subscription with a Stripe subscription id", () => {
    expect(hasBillableSubscription({ status: "ACTIVE", stripeSubscriptionId: "sub_1" })).toBe(true);
  });

  it("is true while trialing or past_due (still billing)", () => {
    expect(hasBillableSubscription({ status: "TRIALING", stripeSubscriptionId: "sub_1" })).toBe(true);
    expect(hasBillableSubscription({ status: "PAST_DUE", stripeSubscriptionId: "sub_1" })).toBe(true);
  });

  it("is false once canceled, even if a stripeSubscriptionId is still on file", () => {
    expect(hasBillableSubscription({ status: "CANCELED", stripeSubscriptionId: "sub_1" })).toBe(false);
  });

  it("is false with no subscription at all", () => {
    expect(hasBillableSubscription(null)).toBe(false);
  });

  it("is false for an active-looking status with no actual Stripe subscription id", () => {
    expect(hasBillableSubscription({ status: "ACTIVE", stripeSubscriptionId: null })).toBe(false);
  });
});

describe("createCheckoutSession — never double-subscribes", () => {
  beforeEach(() => vi.clearAllMocks());

  it("refuses to start a new Checkout Session for a business that's already billable", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeCustomerId: "cus_1",
      stripeSubscriptionId: "sub_1",
      status: "ACTIVE",
    });

    await expect(createCheckoutSession(mockBusiness as never, "PRO", "https://app.example.com")).rejects.toThrow(
      /already has an active subscription/i
    );
    expect(mockStripeClient.checkout.sessions.create).not.toHaveBeenCalled();
  });

  it("starts Checkout normally for a business with no existing subscription", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue(null);
    mockStripeClient.checkout.sessions.create.mockResolvedValue({ url: "https://checkout.stripe.com/xyz" });

    const session = await createCheckoutSession(mockBusiness as never, "PRO", "https://app.example.com");

    expect(session.url).toBe("https://checkout.stripe.com/xyz");
    expect(mockStripeClient.checkout.sessions.create).toHaveBeenCalledTimes(1);
  });
});

describe("changeSubscriptionPlan — updates in place instead of creating a second subscription", () => {
  beforeEach(() => vi.clearAllMocks());

  it("updates the existing subscription's price rather than creating a new one", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({ stripeSubscriptionId: "sub_1" });
    mockStripeClient.subscriptions.retrieve.mockResolvedValue({ items: { data: [{ id: "si_1" }] } });
    mockStripeClient.subscriptions.update.mockResolvedValue({});

    await changeSubscriptionPlan(mockBusiness as never, "PRO");

    expect(mockStripeClient.subscriptions.update).toHaveBeenCalledWith(
      "sub_1",
      expect.objectContaining({ items: [{ id: "si_1", price: "price_pro" }] })
    );
    expect(mockStripeClient.checkout.sessions.create).not.toHaveBeenCalled();
  });

  it("throws instead of silently no-op-ing when there's no subscription to change", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue(null);
    await expect(changeSubscriptionPlan(mockBusiness as never, "PRO")).rejects.toThrow(/no active subscription/i);
  });
});
