import { describe, expect, it } from "vitest";
import { safeCompare } from "@/lib/api/timing-safe-equal";

describe("safeCompare", () => {
  it("returns true for identical strings", () => {
    expect(safeCompare("my-secret-value", "my-secret-value")).toBe(true);
  });

  it("returns false for different strings of the same length", () => {
    expect(safeCompare("my-secret-value", "my-secret-valug")).toBe(false);
  });

  it("returns false for strings of different lengths without throwing", () => {
    expect(() => safeCompare("short", "a-much-longer-secret-value")).not.toThrow();
    expect(safeCompare("short", "a-much-longer-secret-value")).toBe(false);
  });

  it("returns false for an empty string against a real secret", () => {
    expect(safeCompare("", "my-secret-value")).toBe(false);
  });

  it("is case-sensitive", () => {
    expect(safeCompare("Secret", "secret")).toBe(false);
  });
});
