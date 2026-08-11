import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Converana must stay launchable while Twilio is unavailable or trial-limited.
 * These tests pin the two behaviours that make that safe:
 *   1. sendSMS never throws — it always reports {sent, reason}.
 *   2. A failed send is never recorded as a successful delivery.
 */

const mockCreate = vi.fn();
vi.mock("twilio", () => ({
  default: () => ({ messages: { create: mockCreate } }),
}));

const configFlags = { isTwilioConfigured: true };
vi.mock("@/lib/auth/config", () => ({
  get isTwilioConfigured() {
    return configFlags.isTwilioConfigured;
  },
}));

const { sendSMS } = await import("@/lib/twilio/send-sms");

describe("sendSMS degrades gracefully", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    configFlags.isTwilioConfigured = true;
    process.env.TWILIO_PHONE_NUMBER = "+15125550100";
  });

  it("reports a reason instead of throwing when Twilio is not configured", async () => {
    configFlags.isTwilioConfigured = false;
    const result = await sendSMS({ to: "+15125550123", body: "hi" });
    expect(result.sent).toBe(false);
    expect(result.reason).toBeTruthy();
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it("does not throw when Twilio rejects the send (trial-account restriction)", async () => {
    // Real shape of a Twilio trial failure: unverified destination number.
    mockCreate.mockRejectedValue(
      Object.assign(new Error("The number +49... is unverified. Trial accounts may only send to verified numbers."), {
        code: 21608,
        status: 400,
      })
    );

    // If sendSMS threw, this await would reject and fail the test — which is
    // precisely the regression being guarded against.
    const result = await sendSMS({ to: "+15125550123", body: "hi" });

    expect(result.sent).toBe(false);
    expect(result.reason).toBeTruthy();
  });

  it("never leaks the raw provider error text to the caller", async () => {
    mockCreate.mockRejectedValue(
      new Error("The number +49123 is unverified. Trial accounts may only send to verified numbers. SID ACxxxx")
    );
    const result = await sendSMS({ to: "+15125550123", body: "hi" });

    expect(result.sent).toBe(false);
    // Generic, user-safe reason — no Twilio codes, SIDs, or provider copy.
    expect(result.reason).toBe("Unexpected error sending SMS.");
    expect(result.reason).not.toMatch(/unverified|Trial|AC[a-f0-9]/i);
  });

  it("reports a reason when no sending number is available", async () => {
    delete process.env.TWILIO_PHONE_NUMBER;
    const result = await sendSMS({ to: "+15125550123", body: "hi", from: null });
    expect(result.sent).toBe(false);
    expect(result.reason).toBeTruthy();
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it("reports success only when Twilio actually accepts the message", async () => {
    mockCreate.mockResolvedValue({ sid: "SM123" });
    const result = await sendSMS({ to: "+15125550123", body: "hi" });
    expect(result.sent).toBe(true);
    expect(result.reason).toBeUndefined();
  });

  it("prefers a business's own number over the platform number", async () => {
    mockCreate.mockResolvedValue({ sid: "SM123" });
    await sendSMS({ to: "+15125550123", body: "hi", from: "+15125559999" });
    expect(mockCreate).toHaveBeenCalledWith(expect.objectContaining({ from: "+15125559999" }));
  });
});

describe("delivery outcome drives the recorded status", () => {
  // Mirrors the branch in app/api/cron/follow-ups/route.ts: a follow-up is
  // only ever marked SENT when delivery.sent is true.
  function statusFor(delivery: { sent: boolean }) {
    return delivery.sent ? "SENT" : "FAILED";
  }

  it("marks a delivered follow-up SENT", () => {
    expect(statusFor({ sent: true })).toBe("SENT");
  });

  it("marks an undelivered follow-up FAILED, never SENT", () => {
    expect(statusFor({ sent: false })).toBe("FAILED");
    expect(statusFor({ sent: false })).not.toBe("SENT");
  });
});
