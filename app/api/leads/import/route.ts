import { NextResponse, type NextRequest } from "next/server";
import { revalidatePath } from "next/cache";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { readCsvUpload, UploadError } from "@/lib/leads/import/request";
import { parseMapping, runImport } from "@/lib/leads/import/run";
import { suggestMapping } from "@/lib/leads/import/fields";

/** 2,000 rows of validation plus batched inserts stays well inside this. */
export const maxDuration = 60;

/**
 * Imports the leads in an uploaded CSV.
 *
 * Everything that decides what gets written happens here on the server: the
 * file is re-parsed and re-validated (the preview's numbers are never
 * trusted), duplicates are re-checked, and the plan allowance is re-read
 * immediately before the insert. The client can only supply a file and a
 * column mapping — never a business id, a plan, or a row count.
 *
 * Imported leads get no conversation, no AI qualification, no notification
 * and no scheduled follow-up. Nothing is sent to them.
 */
export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`leads-import:${auth.business.id}`, 5, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  try {
    const formData = await request.formData();
    const { parsed, fileName } = await readCsvUpload(formData);

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

    if (!mapping.includes("firstName")) {
      return apiError("Map a column to First Name before importing.");
    }
    if (!mapping.includes("email") && !mapping.includes("phone")) {
      return apiError("Map a column to Email or Phone before importing.");
    }

    const result = await runImport(auth.business, parsed, mapping, fileName);

    revalidatePath("/dashboard/leads");
    revalidatePath("/dashboard");

    return NextResponse.json(result);
  } catch (err) {
    if (err instanceof UploadError) return apiError(err.message, err.status);
    console.error("[api/leads/import] failed", err);
    return apiError("The import couldn't be completed. No leads were changed.", 500);
  }
}
