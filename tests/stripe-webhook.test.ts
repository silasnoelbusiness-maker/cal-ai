import { describe, expect, it } from "vitest";
import { mapStripeStatus } from "@/lib/stripe/status";

describe("mapStripeStatus", () => {
  it("maps active and trialing to their direct equivalents", () => {
    expect(mapStripeStatus("active")).toBe("ACTIVE");
    expect(mapStripeStatus("trialing")).toBe("TRIALING");
  });

  it("maps past_due and unpaid distinctly, so overdue accounts are flagged", () => {
    expect(mapStripeStatus("past_due")).toBe("PAST_DUE");
    expect(mapStripeStatus("unpaid")).toBe("UNPAID");
  });

  it("treats canceled and incomplete_expired the same way", () => {
    expect(mapStripeStatus("canceled")).toBe("CANCELED");
    expect(mapStripeStatus("incomplete_expired")).toBe("CANCELED");
  });

  it("maps incomplete to INCOMPLETE, not ACTIVE", () => {
    expect(mapStripeStatus("incomplete")).toBe("INCOMPLETE");
  });

  it("falls back to NONE for an unrecognized status", () => {
    // Cast because Stripe's type is a closed union — this exercises the
    // defensive default branch in case Stripe adds a new status value.
    expect(mapStripeStatus("some_future_status" as never)).toBe("NONE");
  });
});
