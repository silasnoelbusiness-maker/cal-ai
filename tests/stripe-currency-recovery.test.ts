import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Stripe locks a Customer to the currency it was first billed in. After the
 * EUR -> USD switch, a stored customer from the old currency made every
 * checkout fail with:
 *
 *   "The price specified only supports `usd`. This doesn't match the
 *    expected currency: `eur`."
 *
 * createCheckoutSession must recover by retrying once without the stale
 * customer, so Stripe creates a fresh one in the price's currency.
 */

const mockSessionsCreate = vi.fn();
const mockSubscriptionsUpdate = vi.fn();
const mockSubscriptionsRetrieve = vi.fn();

vi.mock("@/lib/stripe/client", () => ({
  getStripeClient: () => ({
    checkout: { sessions: { create: mockSessionsCreate } },
    subscriptions: { update: mockSubscriptionsUpdate, retrieve: mockSubscriptionsRetrieve },
  }),
  BillingUnavailableError: class extends Error {},
}));

const mockPrisma = { subscription: { findUnique: vi.fn() } };
vi.mock("@/lib/db/prisma", () => ({ prisma: mockPrisma }));

const { createCheckoutSession } = await import("@/lib/stripe/checkout");

const BUSINESS = { id: "biz_1", email: "owner@example.com" } as never;

function currencyError() {
  return new Error(
    "The price specified only supports `usd`. This doesn't match the expected currency: `eur`."
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.STRIPE_PRICE_STARTER = "price_usd_starter";
});

describe("checkout recovers from a currency-locked Stripe customer", () => {
  it("retries without the stale customer and succeeds", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      businessId: "biz_1",
      stripeCustomerId: "cus_old_eur",
      stripeSubscriptionId: null,
      status: "CANCELED",
    });
    mockSessionsCreate
      .mockRejectedValueOnce(currencyError())
      .mockResolvedValueOnce({ id: "cs_new", url: "https://checkout.stripe.com/new" });

    const session = await createCheckoutSession(BUSINESS, "STARTER", "https://converana.com");

    expect(session.id).toBe("cs_new");
    expect(mockSessionsCreate).toHaveBeenCalledTimes(2);

    // First attempt reused the old customer...
    expect(mockSessionsCreate.mock.calls[0][0].customer).toBe("cus_old_eur");
    // ...the retry dropped it so Stripe mints a fresh USD customer.
    expect(mockSessionsCreate.mock.calls[1][0].customer).toBeUndefined();
    expect(mockSessionsCreate.mock.calls[1][0].customer_email).toBe("owner@example.com");
  });

  it("still bills the configured USD price on the retry", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeCustomerId: "cus_old_eur",
      stripeSubscriptionId: null,
      status: "CANCELED",
    });
    mockSessionsCreate.mockRejectedValueOnce(currencyError()).mockResolvedValueOnce({ id: "cs_new" });

    await createCheckoutSession(BUSINESS, "STARTER", "https://converana.com");

    expect(mockSessionsCreate.mock.calls[1][0].line_items).toEqual([
      { price: "price_usd_starter", quantity: 1 },
    ]);
    // businessId metadata must survive the retry or the webhook can't link it back.
    expect(mockSessionsCreate.mock.calls[1][0].metadata.businessId).toBe("biz_1");
    expect(mockSessionsCreate.mock.calls[1][0].subscription_data.metadata.businessId).toBe("biz_1");
  });

  it("does NOT retry on unrelated Stripe errors", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeCustomerId: "cus_old_eur",
      stripeSubscriptionId: null,
      status: "CANCELED",
    });
    mockSessionsCreate.mockRejectedValueOnce(new Error("Your card was declined."));

    await expect(createCheckoutSession(BUSINESS, "STARTER", "https://converana.com")).rejects.toThrow(
      "Your card was declined."
    );
    expect(mockSessionsCreate).toHaveBeenCalledTimes(1);
  });

  it("does not retry when there was no stored customer to blame", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue(null);
    mockSessionsCreate.mockRejectedValueOnce(currencyError());

    await expect(createCheckoutSession(BUSINESS, "STARTER", "https://converana.com")).rejects.toThrow();
    expect(mockSessionsCreate).toHaveBeenCalledTimes(1);
  });

  it("normal checkout is unaffected — one call, customer reused", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeCustomerId: "cus_usd",
      stripeSubscriptionId: null,
      status: "CANCELED",
    });
    mockSessionsCreate.mockResolvedValueOnce({ id: "cs_ok" });

    await createCheckoutSession(BUSINESS, "STARTER", "https://converana.com");

    expect(mockSessionsCreate).toHaveBeenCalledTimes(1);
    expect(mockSessionsCreate.mock.calls[0][0].customer).toBe("cus_usd");
  });

  it("still refuses to double-subscribe an actively billed business", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeCustomerId: "cus_live",
      stripeSubscriptionId: "sub_live",
      status: "ACTIVE",
    });

    await expect(createCheckoutSession(BUSINESS, "STARTER", "https://converana.com")).rejects.toThrow(
      /already has an active subscription/i
    );
    expect(mockSessionsCreate).not.toHaveBeenCalled();
  });
});

describe("Checkout branding", () => {
  it("shows the Converana brand name on Checkout", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue(null);
    mockSessionsCreate.mockResolvedValueOnce({ id: "cs_ok" });

    await createCheckoutSession(BUSINESS, "STARTER", "https://converana.com");

    expect(mockSessionsCreate.mock.calls[0][0].branding_settings).toEqual({
      display_name: "Converana",
    });
  });

  it("keeps the branding on the currency-mismatch retry", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue({
      stripeCustomerId: "cus_old_eur",
      stripeSubscriptionId: null,
      status: "CANCELED",
    });
    mockSessionsCreate.mockRejectedValueOnce(currencyError()).mockResolvedValueOnce({ id: "cs_new" });

    await createCheckoutSession(BUSINESS, "STARTER", "https://converana.com");

    expect(mockSessionsCreate.mock.calls[1][0].branding_settings).toEqual({
      display_name: "Converana",
    });
  });

  it("does not touch any other Checkout option", async () => {
    mockPrisma.subscription.findUnique.mockResolvedValue(null);
    mockSessionsCreate.mockResolvedValueOnce({ id: "cs_ok" });

    await createCheckoutSession(BUSINESS, "STARTER", "https://converana.com");
    const params = mockSessionsCreate.mock.calls[0][0];

    expect(params.mode).toBe("subscription");
    expect(params.allow_promotion_codes).toBe(true);
    expect(params.client_reference_id).toBe("biz_1");
    expect(params.line_items).toEqual([{ price: "price_usd_starter", quantity: 1 }]);
    expect(params.success_url).toBe("https://converana.com/dashboard/billing?checkout=success");
    expect(params.cancel_url).toBe("https://converana.com/dashboard/billing?checkout=cancelled");
  });
});
