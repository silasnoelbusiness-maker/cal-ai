import "server-only";
import { CSV_MAX_BYTES, CsvParseError, parseCsv, type ParsedCsv } from "./csv";

/**
 * Turns a multipart upload into parsed CSV, rejecting anything unsuitable
 * with a message that can be shown to the customer verbatim. Every failure
 * here is the user's file being wrong, never a server fault, so these are
 * always 4xx.
 */

export class UploadError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "UploadError";
    this.status = status;
  }
}

const ACCEPTED_EXTENSIONS = [".csv", ".txt", ".tsv"];

/** Spreadsheet formats we can name specifically instead of a generic error. */
const SPREADSHEET_EXTENSIONS = [".xlsx", ".xls", ".xlsm", ".numbers", ".ods"];

export interface CsvUpload {
  parsed: ParsedCsv;
  fileName: string;
}

export async function readCsvUpload(formData: FormData): Promise<CsvUpload> {
  const file = formData.get("file");
  if (!file || typeof file === "string") {
    throw new UploadError("Choose a CSV file to import.");
  }

  const fileName = file.name || "upload.csv";
  const lower = fileName.toLowerCase();

  if (SPREADSHEET_EXTENSIONS.some((ext) => lower.endsWith(ext))) {
    throw new UploadError(
      "Excel and Numbers files aren't supported yet. In your spreadsheet choose File → Save as / Export and pick CSV, then upload that."
    );
  }
  if (!ACCEPTED_EXTENSIONS.some((ext) => lower.endsWith(ext))) {
    throw new UploadError("That file type isn't supported. Upload a .csv file.");
  }
  if (file.size === 0) {
    throw new UploadError("That file is empty.");
  }
  if (file.size > CSV_MAX_BYTES) {
    throw new UploadError(
      `That file is ${(file.size / 1024 / 1024).toFixed(1)} MB. The limit is ${CSV_MAX_BYTES / 1024 / 1024} MB — split it into smaller files.`,
      413
    );
  }

  // Non-fatal decoding: a stray non-UTF-8 byte becomes a replacement
  // character rather than failing the whole upload.
  const text = new TextDecoder("utf-8").decode(await file.arrayBuffer());

  try {
    return { parsed: parseCsv(text), fileName };
  } catch (err) {
    if (err instanceof CsvParseError) throw new UploadError(err.message);
    throw new UploadError("That file couldn't be read as CSV.");
  }
}
