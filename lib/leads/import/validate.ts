import type { LeadStatus, LeadTemperature } from "@prisma/client";
import type { ColumnMapping, ImportField } from "./fields";

/**
 * Server-side validation and normalization for one CSV row.
 *
 * Nothing here trusts the file: every value is length-capped, stripped of
 * control characters, and — for the enum and money columns — either parsed
 * into a legal value or discarded. A CSV can therefore never write a status
 * or temperature the schema doesn't define, or a number the Decimal(10,2)
 * column can't hold.
 *
 * Pure — no server-only import — so it can be unit tested directly.
 */

/**
 * Type-checked against the Prisma enums: if a value is ever removed from
 * the schema, this file stops compiling rather than silently accepting it.
 */
const VALID_STATUSES: LeadStatus[] = [
  "NEW",
  "CONTACTED",
  "QUALIFIED",
  "APPOINTMENT",
  "CONVERTED",
  "LOST",
  "CLOSED",
];
const VALID_TEMPERATURES: LeadTemperature[] = ["HOT", "WARM", "COLD"];

/** Matches the columns' database limits, minus headroom. */
const MAX_LENGTHS: Record<ImportField, number> = {
  firstName: 100,
  lastName: 100,
  email: 254,
  phone: 32,
  serviceRequested: 200,
  source: 60,
  message: 5000,
  estimatedValue: 32,
  status: 32,
  temperature: 32,
};

/** Decimal(10, 2) — anything larger would be rejected by Postgres. */
const MAX_ESTIMATED_VALUE = 99_999_999.99;

/** Source recorded when the CSV has no Source column of its own. */
export const IMPORT_SOURCE = "csv_import";

export interface ImportableLead {
  firstName: string;
  lastName: string | null;
  email: string | null;
  phone: string | null;
  source: string;
  serviceRequested: string | null;
  message: string | null;
  status: LeadStatus;
  temperature: LeadTemperature;
  estimatedValue: number | null;
}

export type RowValidation =
  | {
      ok: true;
      lead: ImportableLead;
      /** Normalized duplicate-matching keys; null when absent. */
      emailKey: string | null;
      phoneKey: string | null;
      warnings: string[];
    }
  | { ok: false; reason: string };

/** Strips control characters that would corrupt display or a later export. */
function clean(value: string, max: number, { allowNewlines = false } = {}): string {
  const stripped = allowNewlines
    ? value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    : value.replace(/[\u0000-\u001F\u007F]/g, " ");
  return stripped.trim().slice(0, max);
}

export function normalizeEmail(raw: string): string | null {
  const value = raw.trim().toLowerCase();
  if (!value || value.length > MAX_LENGTHS.email) return null;
  // Deliberately not RFC 5322 — that grammar accepts addresses no mail
  // provider will deliver to. This is the practical shape of a real address.
  if (!/^[^\s@,;]+@[^\s@,;.]+(\.[^\s@,;.]+)+$/.test(value)) return null;
  return value;
}

/**
 * Normalizes a phone number and derives a duplicate-matching key.
 *
 * A country code is never invented: a bare 10-digit number stays as it is,
 * because guessing +1 for a number that turns out to be foreign would write
 * an undeliverable number into the customer's CRM. The matching key does
 * drop a leading US/Canada `1`, so "+1 212 555 0123" and "(212) 555-0123"
 * are recognised as the same person.
 */
export function normalizePhone(raw: string): { display: string; key: string } | null {
  // Tools that apply a formula guard on export (including this one) write
  // "+1…" as "'+1…". Drop that prefix so the country code survives a round
  // trip through another product's CSV export.
  const trimmed = raw.trim().replace(/^'/, "");
  if (!trimmed || trimmed.length > MAX_LENGTHS.phone * 2) return null;

  let digits = trimmed.replace(/\D/g, "");
  const international = trimmed.startsWith("+") || digits.startsWith("00");
  if (digits.startsWith("00")) digits = digits.slice(2);

  // E.164 allows 15 digits at most; fewer than 7 isn't a dialable number.
  if (digits.length < 7 || digits.length > 15) return null;

  const display = international ? `+${digits}` : digits;
  const key = digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : digits;
  return { display, key };
}

/**
 * Parses a money-ish string: "$1,200.50", "1200", "1 200,50" all work.
 * Returns null for anything that isn't a usable non-negative number.
 */
export function parseEstimatedValue(raw: string): number | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;

  let value = trimmed.replace(/[^\d.,-]/g, "");
  // "abc" strips down to "", and Number("") is 0 — which would silently turn
  // a junk cell into a real $0 estimate instead of flagging it.
  if (!/\d/.test(value)) return null;

  const hasComma = value.includes(",");
  const hasDot = value.includes(".");

  if (hasComma && hasDot) {
    // Whichever appears last is the decimal separator.
    value =
      value.lastIndexOf(",") > value.lastIndexOf(".")
        ? value.replace(/\./g, "").replace(",", ".")
        : value.replace(/,/g, "");
  } else if (hasComma) {
    // "1234,56" is a decimal comma; "1,234" is a thousands separator.
    value = /,\d{1,2}$/.test(value) ? value.replace(",", ".") : value.replace(/,/g, "");
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > MAX_ESTIMATED_VALUE) return null;
  return Math.round(parsed * 100) / 100;
}

export function parseStatus(raw: string): LeadStatus | null {
  const value = raw.trim().toUpperCase().replace(/[\s-]+/g, "_");
  return VALID_STATUSES.find((s) => s === value) ?? null;
}

export function parseTemperature(raw: string): LeadTemperature | null {
  const value = raw.trim().toUpperCase();
  return VALID_TEMPERATURES.find((t) => t === value) ?? null;
}

/** Pulls a row's cells into mapped field values. */
export function applyMapping(row: string[], mapping: ColumnMapping): Partial<Record<ImportField, string>> {
  const values: Partial<Record<ImportField, string>> = {};
  for (let i = 0; i < mapping.length; i++) {
    const field = mapping[i];
    if (!field) continue;
    const cell = row[i];
    if (cell === undefined || cell.trim() === "") continue;
    // A field mapped to two columns keeps the first non-empty one.
    if (values[field] === undefined) values[field] = cell;
  }
  return values;
}

/**
 * Validates one mapped row.
 *
 * A row is rejected outright only when it can't produce a usable lead: no
 * first name, or no valid email AND no valid phone. Everything else — an
 * unreadable estimated value, an unknown status — degrades to a warning and
 * falls back to the schema default, so a customer never loses a real lead
 * over a cosmetic column.
 */
export function validateRow(values: Partial<Record<ImportField, string>>): RowValidation {
  const warnings: string[] = [];

  const firstName = clean(values.firstName ?? "", MAX_LENGTHS.firstName);
  if (!firstName) {
    return { ok: false, reason: "Missing first name" };
  }

  const rawEmail = (values.email ?? "").trim();
  const email = rawEmail ? normalizeEmail(rawEmail) : null;

  const rawPhone = (values.phone ?? "").trim();
  const phone = rawPhone ? normalizePhone(rawPhone) : null;

  if (!email && !phone) {
    if (rawEmail && rawPhone) return { ok: false, reason: "Email and phone are both invalid" };
    if (rawEmail) return { ok: false, reason: `Invalid email "${rawEmail.slice(0, 60)}"` };
    if (rawPhone) return { ok: false, reason: `Invalid phone "${rawPhone.slice(0, 60)}"` };
    return { ok: false, reason: "No email or phone — a lead needs at least one" };
  }

  if (rawEmail && !email) warnings.push("Email was unreadable and left blank");
  if (rawPhone && !phone) warnings.push("Phone was unreadable and left blank");

  let estimatedValue: number | null = null;
  if (values.estimatedValue) {
    estimatedValue = parseEstimatedValue(values.estimatedValue);
    if (estimatedValue === null) warnings.push("Estimated value wasn't a number and was left blank");
  }

  let status: LeadStatus = "NEW";
  if (values.status) {
    const parsed = parseStatus(values.status);
    if (parsed) status = parsed;
    else warnings.push(`Unknown status "${clean(values.status, 30)}" — imported as New`);
  }

  let temperature: LeadTemperature = "COLD";
  if (values.temperature) {
    const parsed = parseTemperature(values.temperature);
    if (parsed) temperature = parsed;
    else warnings.push(`Unknown temperature "${clean(values.temperature, 30)}" — imported as Cold`);
  }

  const lead: ImportableLead = {
    firstName,
    lastName: clean(values.lastName ?? "", MAX_LENGTHS.lastName) || null,
    email,
    phone: phone?.display ?? null,
    source: clean(values.source ?? "", MAX_LENGTHS.source) || IMPORT_SOURCE,
    serviceRequested: clean(values.serviceRequested ?? "", MAX_LENGTHS.serviceRequested) || null,
    message: clean(values.message ?? "", MAX_LENGTHS.message, { allowNewlines: true }) || null,
    status,
    temperature,
    estimatedValue,
  };

  return { ok: true, lead, emailKey: email, phoneKey: phone?.key ?? null, warnings };
}
