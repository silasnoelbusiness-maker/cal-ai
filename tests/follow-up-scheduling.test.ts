import { describe, expect, it } from "vitest";
import { isLeadEligibleForFollowUp } from "@/lib/follow-ups/schedule";

describe("isLeadEligibleForFollowUp", () => {
  it("is eligible for a fresh, non-opted-out lead", () => {
    expect(isLeadEligibleForFollowUp({ status: "NEW", optedOut: false })).toBe(true);
    expect(isLeadEligibleForFollowUp({ status: "CONTACTED", optedOut: false })).toBe(true);
    expect(isLeadEligibleForFollowUp({ status: "QUALIFIED", optedOut: false })).toBe(true);
  });

  it("never sends follow-ups to converted leads", () => {
    expect(isLeadEligibleForFollowUp({ status: "CONVERTED", optedOut: false })).toBe(false);
  });

  it("never sends follow-ups to lost leads", () => {
    expect(isLeadEligibleForFollowUp({ status: "LOST", optedOut: false })).toBe(false);
  });

  it("never sends follow-ups to closed leads", () => {
    expect(isLeadEligibleForFollowUp({ status: "CLOSED", optedOut: false })).toBe(false);
  });

  it("never sends follow-ups to a lead who opted out, regardless of status", () => {
    expect(isLeadEligibleForFollowUp({ status: "NEW", optedOut: true })).toBe(false);
    expect(isLeadEligibleForFollowUp({ status: "QUALIFIED", optedOut: true })).toBe(false);
  });
});
