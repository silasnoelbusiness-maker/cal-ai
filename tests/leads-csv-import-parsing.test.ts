import { describe, expect, it } from "vitest";
import { CsvParseError, escapeCsvCell, parseCsv, toCsv } from "@/lib/leads/import/csv";
import { suggestMapping } from "@/lib/leads/import/fields";
import {
  applyMapping,
  normalizePhone,
  parseEstimatedValue,
  validateRow,
} from "@/lib/leads/import/validate";

/**
 * The parsing/validation half of CSV import. Everything here is pure, so it
 * is tested directly rather than through the database.
 */

describe("parsing real-world CSV files", () => {
  it("reads the documented example", () => {
    const csv = [
      "First Name,Last Name,Email,Phone,Company,Service,Source,Message",
      "John,Smith,john@example.com,+12125550123,Smith Roofing,Roof Repair,Facebook Ads,Need a roof quote",
      "Sarah,Jones,sarah@example.com,+12125550124,Jones LLC,HVAC,Google Ads,AC stopped working",
    ].join("\n");

    const parsed = parseCsv(csv);

    expect(parsed.headers[0]).toBe("First Name");
    expect(parsed.rows).toHaveLength(2);
    expect(parsed.rows[1][2]).toBe("sarah@example.com");
  });

  it("handles semicolon-separated exports", () => {
    const parsed = parseCsv("first_name;email\nJohn;john@example.com");
    expect(parsed.delimiter).toBe(";");
    expect(parsed.rows[0]).toEqual(["John", "john@example.com"]);
  });

  it("handles quoted values containing the delimiter, quotes and newlines", () => {
    const csv = 'name,message\nJohn,"Hello, ""friend""\nsecond line"';
    const parsed = parseCsv(csv);
    expect(parsed.rows[0][1]).toBe('Hello, "friend"\nsecond line');
  });

  it("strips the UTF-8 BOM Excel writes, so the first header isn't corrupted", () => {
    const parsed = parseCsv("﻿email\njohn@example.com");
    expect(parsed.headers).toEqual(["email"]);
  });

  it("handles CRLF line endings and ignores blank lines", () => {
    const parsed = parseCsv("email\r\njohn@example.com\r\n\r\nsarah@example.com\r\n");
    expect(parsed.rows).toHaveLength(2);
  });

  it("pads ragged rows so column indexes are always safe", () => {
    const parsed = parseCsv("a,b,c\n1\n1,2,3");
    expect(parsed.rows[0]).toEqual(["1", "", ""]);
  });

  it("rejects malformed and unusable files with a readable message", () => {
    expect(() => parseCsv("")).toThrow(CsvParseError);
    expect(() => parseCsv("   ")).toThrow(CsvParseError);
    // Header row only — nothing to import.
    expect(() => parseCsv("first_name,email")).toThrow(/no data rows/i);
    // A stray quote would otherwise swallow the rest of the file silently.
    expect(() => parseCsv('name\n"unterminated')).toThrow(/never closed/i);
  });

  it("refuses files above the row cap instead of importing a truncated slice", () => {
    const rows = Array.from({ length: 12 }, (_, i) => `user${i}@example.com`);
    expect(() => parseCsv(`email\n${rows.join("\n")}`, { maxRows: 10 })).toThrow(/more than 10 rows/i);
  });
});

describe("CSV injection is neutralized on export", () => {
  it("prefixes formula-leading cells so spreadsheets treat them as text", () => {
    expect(escapeCsvCell("=cmd|'/c calc'!A1")).toBe("'=cmd|'/c calc'!A1");
    expect(escapeCsvCell("+1+1")).toBe("'+1+1");
    expect(escapeCsvCell("@SUM(A1)")).toBe("'@SUM(A1)");
    expect(escapeCsvCell("-2+3")).toBe("'-2+3");
  });

  it("still quotes cells containing commas, quotes or newlines", () => {
    expect(escapeCsvCell('a,b')).toBe('"a,b"');
    expect(escapeCsvCell('say "hi"')).toBe('"say ""hi"""');
  });

  it("leaves ordinary values untouched", () => {
    expect(escapeCsvCell("john@example.com")).toBe("john@example.com");
    expect(escapeCsvCell("Roof Repair")).toBe("Roof Repair");
  });

  it("guards every cell of a generated report", () => {
    const csv = toCsv(["email", "error_reason"], [["=HYPERLINK(1)", "Invalid email"]]);
    expect(csv).toContain("'=HYPERLINK(1)");
  });

  it("a hostile value survives a parse/export round trip as inert text", () => {
    const parsed = parseCsv('email,note\njohn@example.com,"=1+1"');
    expect(parsed.rows[0][1]).toBe("=1+1");
    expect(toCsv(parsed.headers, parsed.rows)).toContain("'=1+1");
  });
});

describe("guessing the column mapping", () => {
  it("matches the documented header spellings", () => {
    const mapping = suggestMapping([
      "firstname",
      "last_name",
      "email_address",
      "mobile",
      "service",
      "campaign",
    ]);
    expect(mapping).toEqual(["firstName", "lastName", "email", "phone", "serviceRequested", "source"]);
  });

  it("matches alternative spellings for the same fields", () => {
    expect(suggestMapping(["First Name"])[0]).toBe("firstName");
    expect(suggestMapping(["telephone"])[0]).toBe("phone");
    expect(suggestMapping(["Mobile Number"])[0]).toBe("phone");
    expect(suggestMapping(["Lead Source"])[0]).toBe("source");
    expect(suggestMapping(["Deal Value"])[0]).toBe("estimatedValue");
  });

  it("never suggests the same field twice", () => {
    const mapping = suggestMapping(["email", "email_address", "work email"]);
    expect(mapping.filter((f) => f === "email")).toHaveLength(1);
  });

  it("leaves unrecognised columns for the user to decide", () => {
    expect(suggestMapping(["Company", "Internal Ref"])).toEqual([null, null]);
  });
});

describe("row validation", () => {
  const map = (values: Record<string, string>) => values as Parameters<typeof validateRow>[0];

  it("accepts a row with an email only, or a phone only", () => {
    expect(validateRow(map({ firstName: "John", email: "john@example.com" })).ok).toBe(true);
    expect(validateRow(map({ firstName: "John", phone: "+12125550123" })).ok).toBe(true);
  });

  it("rejects a row with neither email nor phone", () => {
    const result = validateRow(map({ firstName: "John" }));
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/at least one/i);
  });

  it("rejects a row with no first name", () => {
    const result = validateRow(map({ email: "john@example.com" }));
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/first name/i);
  });

  it("rejects an invalid email when it's the only identifier", () => {
    for (const bad of ["not-an-email", "john@", "@example.com", "john example.com", "john@example"]) {
      const result = validateRow(map({ firstName: "John", email: bad }));
      expect(result.ok, bad).toBe(false);
    }
  });

  it("keeps the row when one identifier is bad but the other is usable", () => {
    const result = validateRow(map({ firstName: "John", email: "nope", phone: "+12125550123" }));
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.lead.email).toBeNull();
      expect(result.warnings.join(" ")).toMatch(/email/i);
    }
  });

  it("lowercases the email so duplicate matching is case-insensitive", () => {
    const result = validateRow(map({ firstName: "John", email: "John@Example.COM" }));
    if (result.ok) expect(result.lead.email).toBe("john@example.com");
  });

  it("never writes an enum value the schema doesn't define", () => {
    const result = validateRow(
      map({ firstName: "John", email: "john@example.com", status: "DROPPED", temperature: "LUKEWARM" })
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      // Falls back to the schema defaults rather than losing the whole lead.
      expect(result.lead.status).toBe("NEW");
      expect(result.lead.temperature).toBe("COLD");
      expect(result.warnings).toHaveLength(2);
    }
  });

  it("accepts valid enum values in any casing", () => {
    const result = validateRow(
      map({ firstName: "John", email: "john@example.com", status: "qualified", temperature: "hot" })
    );
    if (result.ok) {
      expect(result.lead.status).toBe("QUALIFIED");
      expect(result.lead.temperature).toBe("HOT");
    }
  });

  it("warns instead of failing when the estimated value isn't a number", () => {
    const result = validateRow(
      map({ firstName: "John", email: "john@example.com", estimatedValue: "call me" })
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.lead.estimatedValue).toBeNull();
      expect(result.warnings.join(" ")).toMatch(/estimated value/i);
    }
  });

  it("defaults the source when the file has no source column", () => {
    const result = validateRow(map({ firstName: "John", email: "john@example.com" }));
    if (result.ok) expect(result.lead.source).toBe("csv_import");
  });

  it("truncates over-long values rather than letting Postgres reject the insert", () => {
    const result = validateRow(map({ firstName: "J".repeat(500), email: "john@example.com" }));
    if (result.ok) expect(result.lead.firstName.length).toBe(100);
  });
});

describe("value normalization", () => {
  it("parses money in the formats spreadsheets produce", () => {
    expect(parseEstimatedValue("1200")).toBe(1200);
    expect(parseEstimatedValue("$1,200.50")).toBe(1200.5);
    expect(parseEstimatedValue("1.200,50")).toBe(1200.5);
    expect(parseEstimatedValue("1234,56")).toBe(1234.56);
  });

  it("rejects money the Decimal(10,2) column can't hold", () => {
    expect(parseEstimatedValue("-5")).toBeNull();
    expect(parseEstimatedValue("999999999999")).toBeNull();
    expect(parseEstimatedValue("abc")).toBeNull();
  });

  it("treats the same number in different formats as one person", () => {
    const a = normalizePhone("+1 (212) 555-0123");
    const b = normalizePhone("212-555-0123");
    const c = normalizePhone("0012125550123");
    expect(a?.key).toBe(b?.key);
    expect(a?.key).toBe(c?.key);
  });

  it("never invents a country code for a bare number", () => {
    expect(normalizePhone("2125550123")?.display).toBe("2125550123");
    expect(normalizePhone("+12125550123")?.display).toBe("+12125550123");
  });

  it("survives a formula-guarded export from another tool", () => {
    // A CSV that came out of a product applying the same guard we do.
    expect(normalizePhone("'+12125550123")?.display).toBe("+12125550123");
  });

  it("rejects values that aren't dialable numbers", () => {
    expect(normalizePhone("12345")).toBeNull();
    expect(normalizePhone("n/a")).toBeNull();
    expect(normalizePhone("1234567890123456789")).toBeNull();
  });
});

describe("applying a mapping", () => {
  it("pulls only mapped columns and ignores the rest", () => {
    const values = applyMapping(["John", "Acme Inc", "john@example.com"], ["firstName", null, "email"]);
    expect(values).toEqual({ firstName: "John", email: "john@example.com" });
  });

  it("skips blank cells so they fall back to defaults", () => {
    expect(applyMapping(["John", "   "], ["firstName", "email"])).toEqual({ firstName: "John" });
  });
});
