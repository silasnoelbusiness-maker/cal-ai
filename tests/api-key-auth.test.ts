import { beforeEach, describe, expect, it, vi } from "vitest";

const mockApiKey = {
  create: vi.fn(),
  findFirst: vi.fn(),
  update: vi.fn(),
  updateMany: vi.fn(),
};

vi.mock("@/lib/db/prisma", () => ({
  prisma: { apiKey: mockApiKey },
}));

const { createApiKey, resolveApiKey, revokeApiKey } = await import("@/lib/api-keys");

describe("createApiKey", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockApiKey.create.mockImplementation(({ data }) =>
      Promise.resolve({ id: "key_1", ...data })
    );
  });

  it("generates a plaintext key with the ll_live_ prefix", async () => {
    const key = await createApiKey("biz_1", "Website form");
    expect(key.plaintext).toMatch(/^ll_live_/);
  });

  it("never persists the plaintext key — only a hash", async () => {
    await createApiKey("biz_1", "Website form");
    const persisted = mockApiKey.create.mock.calls[0][0].data;
    expect(persisted.hashedKey).toBeDefined();
    expect(persisted).not.toHaveProperty("plaintext");
    expect(persisted.hashedKey).not.toContain("ll_live_");
  });

  it("stores a display prefix that is a substring of the full key", async () => {
    const key = await createApiKey("biz_1", "Website form");
    expect(key.plaintext.startsWith(key.keyPrefix)).toBe(true);
    expect(key.keyPrefix.length).toBeLessThan(key.plaintext.length);
  });

  it("generates a different secret on every call", async () => {
    const first = await createApiKey("biz_1", "A");
    const second = await createApiKey("biz_1", "B");
    expect(first.plaintext).not.toBe(second.plaintext);
  });
});

describe("resolveApiKey", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("rejects a key that doesn't start with the expected prefix without querying the database", async () => {
    const result = await resolveApiKey("sk_not_a_converana_key");
    expect(result).toBeNull();
    expect(mockApiKey.findFirst).not.toHaveBeenCalled();
  });

  it("returns null when no matching, non-revoked key is found", async () => {
    mockApiKey.findFirst.mockResolvedValue(null);
    const result = await resolveApiKey("ll_live_somesecretvalue");
    expect(result).toBeNull();
    expect(mockApiKey.findFirst.mock.calls[0][0].where.revokedAt).toBeNull();
  });

  it("only looks up by hash, never by the raw plaintext key", async () => {
    mockApiKey.findFirst.mockResolvedValue(null);
    await resolveApiKey("ll_live_somesecretvalue");
    const where = mockApiKey.findFirst.mock.calls[0][0].where;
    expect(where.hashedKey).not.toBe("ll_live_somesecretvalue");
  });

  it("touches lastUsedAt when a key is successfully resolved", async () => {
    mockApiKey.findFirst.mockResolvedValue({ id: "key_1", business: { id: "biz_1" } });
    mockApiKey.update.mockResolvedValue({});
    await resolveApiKey("ll_live_somesecretvalue");
    expect(mockApiKey.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: "key_1" } })
    );
  });
});

describe("revokeApiKey", () => {
  it("scopes revocation to the requesting business, never a client-supplied id alone", async () => {
    mockApiKey.updateMany.mockResolvedValue({ count: 1 });
    await revokeApiKey("biz_1", "key_1");
    expect(mockApiKey.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ id: "key_1", businessId: "biz_1" }) })
    );
  });
});
