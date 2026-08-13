import { NextResponse, type NextRequest } from "next/server";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { readCsvUpload, UploadError } from "@/lib/leads/import/request";
import { analyzeImport, parseMapping } from "@/lib/leads/import/run";
import { suggestMapping } from "@/lib/leads/import/fields";

export const maxDuration = 60;

/**
 * Parses an uploaded CSV and reports what would happen if it were imported:
 * detected headers, a suggested mapping, per-row validation, duplicates and
 * the business's remaining plan allowance.
 *
 * Read-only — this endpoint never creates a lead. The business is taken from
 * the authenticated session, so the duplicate check runs against that
 * business's leads and no other.
 */
export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`leads-import-preview:${auth.business.id}`, 30, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  try {
    const formData = await request.formData();
    const { parsed } = await readCsvUpload(formData);

    const rawMapping = formData.get("mapping");
    let mapping = suggestMapping(parsed.headers);

    if (typeof rawMapping === "string" && rawMapping.trim() !== "") {
      let decoded: unknown;
      try {
        decoded = JSON.parse(rawMapping);
      } catch {
        return apiError("That column mapping couldn't be read.");
      }
      const validated = parseMapping(decoded, parsed.headers.length);
      if (!validated) return apiError("That column mapping doesn't match the file's columns.");
      mapping = validated;
    }

    const analysis = await analyzeImport(auth.business, parsed, mapping);

    return NextResponse.json({
      headers: parsed.headers,
      delimiter: parsed.delimiter,
      mapping,
      totalRows: analysis.totalRows,
      ready: analysis.ready,
      duplicatesInFile: analysis.duplicatesInFile,
      duplicatesExisting: analysis.duplicatesExisting,
      invalid: analysis.invalid,
      warnings: analysis.warnings,
      allowance: analysis.allowance,
      preview: analysis.preview,
    });
  } catch (err) {
    if (err instanceof UploadError) return apiError(err.message, err.status);
    console.error("[api/leads/import/preview] failed", err);
    return apiError("Couldn't read that file.", 500);
  }
}
