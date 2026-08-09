import { describe, expect, it } from "vitest";
import { QualificationResultSchema, scoreToTemperature, TEMPERATURE_THRESHOLDS } from "@/lib/ai/types";

const validPayload = {
  qualification_score: 91,
  intent: "high",
  urgency: "high",
  service: "AC repair",
  location: "Dallas, TX",
  budget: "Unknown",
  availability: "tomorrow morning",
  summary: "Customer needs emergency AC repair.",
  recommended_action: "Call customer immediately.",
  needs_human: false,
};

describe("QualificationResultSchema", () => {
  it("accepts a well-formed AI qualification result", () => {
    const result = QualificationResultSchema.safeParse(validPayload);
    expect(result.success).toBe(true);
  });

  it("rejects a score outside 0-100", () => {
    const result = QualificationResultSchema.safeParse({ ...validPayload, qualification_score: 150 });
    expect(result.success).toBe(false);
  });

  it("rejects a non-integer score", () => {
    const result = QualificationResultSchema.safeParse({ ...validPayload, qualification_score: 91.5 });
    expect(result.success).toBe(false);
  });

  it("rejects an intent value outside the allowed enum", () => {
    const result = QualificationResultSchema.safeParse({ ...validPayload, intent: "extremely-high" });
    expect(result.success).toBe(false);
  });

  it("rejects a missing required field", () => {
    const { summary, ...withoutSummary } = validPayload;
    void summary;
    const result = QualificationResultSchema.safeParse(withoutSummary);
    expect(result.success).toBe(false);
  });

  it("rejects an empty string for a text field (must be 'Unknown', not blank)", () => {
    const result = QualificationResultSchema.safeParse({ ...validPayload, location: "" });
    expect(result.success).toBe(false);
  });

  it("accepts the literal 'Unknown' for fields the AI couldn't determine", () => {
    const result = QualificationResultSchema.safeParse({
      ...validPayload,
      location: "Unknown",
      budget: "Unknown",
      intent: "unknown",
      urgency: "unknown",
    });
    expect(result.success).toBe(true);
  });
});

describe("scoreToTemperature", () => {
  it("classifies scores below the WARM threshold as COLD", () => {
    expect(scoreToTemperature(0)).toBe("COLD");
    expect(scoreToTemperature(TEMPERATURE_THRESHOLDS.WARM - 1)).toBe("COLD");
  });

  it("classifies scores between thresholds as WARM", () => {
    expect(scoreToTemperature(TEMPERATURE_THRESHOLDS.WARM)).toBe("WARM");
    expect(scoreToTemperature(TEMPERATURE_THRESHOLDS.HOT - 1)).toBe("WARM");
  });

  it("classifies scores at or above the HOT threshold as HOT", () => {
    expect(scoreToTemperature(TEMPERATURE_THRESHOLDS.HOT)).toBe("HOT");
    expect(scoreToTemperature(100)).toBe("HOT");
  });
});
