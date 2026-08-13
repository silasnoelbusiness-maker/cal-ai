/**
 * A small, dependency-free RFC 4180-style CSV reader/writer.
 *
 * Deliberately hand-written rather than pulled from npm: parsing untrusted
 * uploads is the one place a transitive dependency is least welcome, and the
 * behaviour we need (delimiter sniffing, BOM handling, a hard row cap, and
 * formula-injection-safe output) is small enough to own and test outright.
 *
 * Pure — no server-only import — so the parser can be unit tested directly.
 */

/** Upload ceiling. 2,000 rows of typical lead data is well under 1 MB. */
export const CSV_MAX_BYTES = 5 * 1024 * 1024;

/** Hard row cap per import, matching the largest plan's monthly allowance. */
export const CSV_MAX_ROWS = 2000;

const DELIMITERS = [",", ";", "\t", "|"] as const;

export class CsvParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CsvParseError";
  }
}

export interface ParsedCsv {
  headers: string[];
  rows: string[][];
  delimiter: string;
}

/** The header line, i.e. everything up to the first newline outside quotes. */
function firstLogicalLine(text: string): string {
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"') inQuotes = !inQuotes;
    else if (ch === "\n" && !inQuotes) return text.slice(0, i);
  }
  return text;
}

function countOutsideQuotes(line: string, delimiter: string): number {
  let inQuotes = false;
  let count = 0;
  for (const ch of line) {
    if (ch === '"') inQuotes = !inQuotes;
    else if (ch === delimiter && !inQuotes) count++;
  }
  return count;
}

/**
 * Picks the delimiter that splits the header row into the most columns.
 * Exports from European locales use `;`, and spreadsheet "tab-separated"
 * saves are common enough to be worth accepting too.
 */
function detectDelimiter(headerLine: string): string {
  let best = ",";
  let bestCount = 0;
  for (const candidate of DELIMITERS) {
    const count = countOutsideQuotes(headerLine, candidate);
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

/**
 * Parses CSV text into a header row plus data rows.
 *
 * Throws CsvParseError — never a raw exception — so callers can always turn
 * a bad upload into a clear message instead of a 500.
 */
export function parseCsv(input: string, options: { maxRows?: number } = {}): ParsedCsv {
  const maxRows = options.maxRows ?? CSV_MAX_ROWS;

  // Excel prefixes UTF-8 exports with a byte-order mark, which would
  // otherwise become part of the first header's name.
  const text = input.replace(/^\uFEFF/, "");
  if (!text.trim()) throw new CsvParseError("That file is empty.");

  const delimiter = detectDelimiter(firstLogicalLine(text));

  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let fieldQuoted = false;
  let inQuotes = false;

  const endField = () => {
    row.push(field);
    field = "";
    fieldQuoted = false;
  };

  const endRow = () => {
    endField();
    // Drop rows that are entirely blank — trailing newlines and the blank
    // separator lines some exports leave behind aren't real records.
    if (row.some((cell) => cell.trim() !== "")) rows.push(row);
    row = [];
    if (rows.length > maxRows + 1) {
      throw new CsvParseError(
        `That file has more than ${maxRows.toLocaleString()} rows. Split it into smaller files and import them one at a time.`
      );
    }
  };

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];

    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }

    if (ch === '"' && field === "") {
      inQuotes = true;
      fieldQuoted = true;
      continue;
    }
    if (ch === delimiter) {
      endField();
      continue;
    }
    if (ch === "\r") continue;
    if (ch === "\n") {
      endRow();
      continue;
    }
    field += ch;
  }

  if (inQuotes) {
    throw new CsvParseError(
      "That file has a quoted value that is never closed. Check for a stray double-quote character and try again."
    );
  }
  if (field !== "" || fieldQuoted || row.length > 0) endRow();

  const headerRow = rows.shift();
  if (!headerRow) throw new CsvParseError("That file has no rows.");

  const headers = headerRow.map((h) => h.trim());
  if (headers.every((h) => h === "")) {
    throw new CsvParseError("The first row must contain column names.");
  }
  if (rows.length === 0) {
    throw new CsvParseError("That file has column names but no data rows.");
  }
  if (rows.length > maxRows) {
    throw new CsvParseError(
      `That file has ${rows.length.toLocaleString()} rows, more than the ${maxRows.toLocaleString()} allowed per import. Split it into smaller files and import them one at a time.`
    );
  }

  // Ragged rows are common in hand-edited files; pad so column indexes are
  // always safe to read.
  for (const r of rows) {
    while (r.length < headers.length) r.push("");
  }

  return { headers, rows, delimiter };
}

/**
 * Neutralizes spreadsheet formula injection on the way OUT.
 *
 * A cell beginning with `=`, `+`, `-`, `@` or a control character is
 * interpreted as a formula by Excel, Sheets and LibreOffice, which is how a
 * hostile CSV turns into code execution on whoever opens the export.
 *
 * This is applied at export time rather than at import time on purpose:
 * `+` and `-` are perfectly legitimate leading characters for the phone
 * numbers and estimated values we store, so mangling them on the way in
 * would corrupt real data. Stored values are otherwise only ever rendered
 * through React, which escapes them.
 */
export function escapeCsvCell(value: string): string {
  const needsFormulaGuard = /^[=+\-@\t\r]/.test(value);
  const guarded = needsFormulaGuard ? `'${value}` : value;
  if (/[",\n\r]/.test(guarded)) return `"${guarded.replace(/"/g, '""')}"`;
  return guarded;
}

/** Quotes a cell without applying the formula guard. */
function quoteCsvCell(value: string): string {
  if (/[",\n\r]/.test(value)) return `"${value.replace(/"/g, '""')}"`;
  return value;
}

/**
 * Builds a CSV document, formula-guarding every cell by default.
 *
 * Pass `trusted: true` only for content this codebase authored itself. The
 * guard would otherwise rewrite a legitimate `+12125550123` as
 * `'+12125550123`, and a file we hand the customer to re-upload has to
 * survive that round trip intact.
 */
export function toCsv(headers: string[], rows: string[][], { trusted = false } = {}): string {
  const encode = trusted ? quoteCsvCell : escapeCsvCell;
  const lines = [headers, ...rows].map((row) => row.map((cell) => encode(cell ?? "")).join(","));
  return `${lines.join("\r\n")}\r\n`;
}
