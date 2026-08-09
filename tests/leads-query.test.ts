import { describe, expect, it } from "vitest";
import { buildLeadsOrderBy, buildLeadsWhere } from "@/lib/leads/query";

describe("buildLeadsWhere", () => {
  it("always scopes by businessId (lead isolation)", () => {
    const where = buildLeadsWhere({ businessId: "biz_1" });
    expect(where.businessId).toBe("biz_1");
  });

  it("never lets a filter or search override the businessId scope", () => {
    const where = buildLeadsWhere({ businessId: "biz_1", filter: "hot", q: "anything" });
    expect(where.businessId).toBe("biz_1");
  });

  it("maps a status filter to a status clause", () => {
    const where = buildLeadsWhere({ businessId: "biz_1", filter: "qualified" });
    expect(where.status).toBe("QUALIFIED");
    expect(where.temperature).toBeUndefined();
  });

  it("maps a temperature filter to a temperature clause", () => {
    const where = buildLeadsWhere({ businessId: "biz_1", filter: "hot" });
    expect(where.temperature).toBe("HOT");
    expect(where.status).toBeUndefined();
  });

  it("applies no extra filter for 'all'", () => {
    const where = buildLeadsWhere({ businessId: "biz_1", filter: "all" });
    expect(where.status).toBeUndefined();
    expect(where.temperature).toBeUndefined();
  });

  it("ignores an unrecognized filter value", () => {
    const where = buildLeadsWhere({ businessId: "biz_1", filter: "not-a-real-filter" });
    expect(where.status).toBeUndefined();
    expect(where.temperature).toBeUndefined();
  });

  it("builds a case-insensitive OR search across name/email/phone/service/message", () => {
    const where = buildLeadsWhere({ businessId: "biz_1", q: "smith" });
    expect(Array.isArray(where.OR)).toBe(true);
    expect(where.OR!.length).toBeGreaterThanOrEqual(6);
  });

  it("omits the OR clause when there's no search term", () => {
    const where = buildLeadsWhere({ businessId: "biz_1" });
    expect(where.OR).toBeUndefined();
  });
});

describe("buildLeadsOrderBy", () => {
  it("defaults to createdAt desc", () => {
    expect(buildLeadsOrderBy({ businessId: "biz_1" })).toEqual({ createdAt: "desc" });
  });

  it("honors a recognized sort field and direction", () => {
    expect(buildLeadsOrderBy({ businessId: "biz_1", sort: "lastContactedAt", dir: "asc" })).toEqual({
      lastContactedAt: "asc",
    });
  });

  it("falls back to createdAt for an unrecognized sort field", () => {
    expect(buildLeadsOrderBy({ businessId: "biz_1", sort: "notARealColumn" })).toEqual({ createdAt: "desc" });
  });
});
