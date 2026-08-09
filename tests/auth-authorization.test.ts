import { beforeEach, describe, expect, it, vi } from "vitest";

const mockBusiness = { id: "biz_1", name: "PeakFlow HVAC" };

const mockResolveApiKey = vi.fn();
const mockGetApiAuthContext = vi.fn();

vi.mock("@/lib/api-keys", () => ({ resolveApiKey: mockResolveApiKey }));
vi.mock("@/lib/auth/session", () => ({ getApiAuthContext: mockGetApiAuthContext }));

const { resolveRequestAuth } = await import("@/lib/api/auth");

function requestWith(headers: Record<string, string>) {
  return { headers: { get: (key: string) => headers[key.toLowerCase()] ?? null } } as never;
}

describe("resolveRequestAuth", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns null when there is no API key and no session", async () => {
    mockGetApiAuthContext.mockResolvedValue(null);
    const result = await resolveRequestAuth(requestWith({}));
    expect(result).toBeNull();
  });

  it("authenticates via a valid Bearer API key without touching the session", async () => {
    mockResolveApiKey.mockResolvedValue({ id: "key_1", business: mockBusiness });
    const result = await resolveRequestAuth(requestWith({ authorization: "Bearer ll_live_abc123" }));
    expect(result).toEqual({ business: mockBusiness, apiKeyId: "key_1" });
    expect(mockGetApiAuthContext).not.toHaveBeenCalled();
  });

  it("rejects a request when the Bearer key is invalid", async () => {
    mockResolveApiKey.mockResolvedValue(null);
    const result = await resolveRequestAuth(requestWith({ authorization: "Bearer ll_live_wrong" }));
    expect(result).toBeNull();
  });

  it("falls back to the dashboard session when no API key header is present", async () => {
    mockGetApiAuthContext.mockResolvedValue({ user: { id: "user_1" }, business: mockBusiness });
    const result = await resolveRequestAuth(requestWith({}));
    expect(result).toEqual({ business: mockBusiness });
    expect(mockResolveApiKey).not.toHaveBeenCalled();
  });

  it("never derives the business from anything the client sends other than the verified key/session", async () => {
    mockResolveApiKey.mockResolvedValue({ id: "key_1", business: mockBusiness });
    // Even if a caller tries to smuggle a businessId header, it's ignored —
    // resolveRequestAuth only ever consults the verified key or session.
    const result = await resolveRequestAuth(
      requestWith({ authorization: "Bearer ll_live_abc123", "x-business-id": "someone-elses-business" })
    );
    expect(result?.business.id).toBe("biz_1");
  });
});
