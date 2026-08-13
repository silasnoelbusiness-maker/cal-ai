import "server-only";
import type { Business, Plan, Prisma } from "@prisma/client";
import { prisma } from "@/lib/db/prisma";
import { PLAN_LIMITS, currentMonthKey, effectivePlan } from "@/lib/plans";
import type { ColumnMapping, ImportField } from "./fields";
import { IMPORT_FIELD_KEYS } from "./fields";
import type { ParsedCsv } from "./csv";
import { applyMapping, validateRow, normalizeEmail, normalizePhone, type ImportableLead } from "./validate";

/**
 * Bulk CSV import.
 *
 * Deliberately does NOT go through `createLead`: that path exists to run the
 * full new-lead pipeline — AI first response, AI qualification, business
 * notifications and follow-up scheduling. Running it 500 times from an
 * upload would blast a customer's entire spreadsheet with automated
 * outreach, which is exactly what a bulk importer must never do. This module
 * writes the same `leads` rows into the same table with the same plan-limit
 * accounting, and stops there. Imported leads are inert until the business
 * chooses to act on them.
 */

/** Rows written per INSERT. Keeps statements comfortably small. */
const INSERT_CHUNK = 500;

/**
 * Ceiling on existing leads scanned for duplicate matching. Well beyond any
 * plan's monthly allowance; a business past this simply gets duplicate
 * detection against its most recent leads rather than a slow query.
 */
const DUPLICATE_SCAN_LIMIT = 50_000;

export type RowState = "ready" | "duplicate" | "invalid";

export interface PreviewRow {
  /** 1-based row number in the file, not counting the header. */
  rowNumber: number;
  values: Partial<Record<ImportField, string>>;
  state: RowState;
  reason?: string;
  warnings: string[];
}

export interface FailedRow {
  rowNumber: number;
  reason: string;
  cells: string[];
}

export interface PlanAllowance {
  plan: Plan;
  planLabel: string;
  limit: number;
  used: number;
  remaining: number;
  /** How many rows will actually be written, after capping. */
  willImport: number;
  /** True when the plan's remaining allowance is the binding constraint. */
  capped: boolean;
}

export interface ImportAnalysis {
  totalRows: number;
  ready: number;
  duplicatesInFile: number;
  duplicatesExisting: number;
  invalid: number;
  warnings: number;
  allowance: PlanAllowance;
  preview: PreviewRow[];
  failedRows: FailedRow[];
}

interface PreparedRow {
  rowNumber: number;
  lead: ImportableLead;
}

interface AnalyzeResult extends ImportAnalysis {
  /** Importable rows, in file order, before the plan cap is applied. */
  prepared: PreparedRow[];
}

/** How many preview rows the review step shows. */
const PREVIEW_ROWS = 10;

function normalizeExistingKeys(leads: { email: string | null; phone: string | null }[]) {
  const emails = new Set<string>();
  const phones = new Set<string>();
  for (const lead of leads) {
    if (lead.email) {
      const email = normalizeEmail(lead.email);
      if (email) emails.add(email);
    }
    if (lead.phone) {
      const phone = normalizePhone(lead.phone);
      if (phone) phones.add(phone.key);
    }
  }
  return { emails, phones };
}

async function readPlanAllowance(businessId: string, ready: number): Promise<PlanAllowance> {
  const [usage, subscription] = await Promise.all([
    prisma.usage.findUnique({
      where: { businessId_month: { businessId, month: currentMonthKey() } },
    }),
    prisma.subscription.findUnique({ where: { businessId } }),
  ]);

  // effectivePlan, not subscription.plan — a lapsed Pro subscriber gets
  // Starter's allowance, exactly as every other lead-creating path does.
  const plan = effectivePlan(subscription);
  const limits = PLAN_LIMITS[plan];
  const used = usage?.leadsCount ?? 0;
  const remaining = Math.max(limits.leadsPerMonth - used, 0);

  return {
    plan,
    planLabel: limits.label,
    limit: limits.leadsPerMonth,
    used,
    remaining,
    willImport: Math.min(ready, remaining),
    capped: ready > remaining,
  };
}

/**
 * Validates and classifies every row, detects duplicates, and works out how
 * many rows the business's plan actually allows. Read-only — nothing is
 * written until `runImport`.
 *
 * `business` always comes from the authenticated server-side session, so
 * duplicate matching and the eventual insert are scoped to that business and
 * cannot reach another one's leads.
 */
export async function analyzeImport(
  business: Business,
  parsed: ParsedCsv,
  mapping: ColumnMapping
): Promise<AnalyzeResult> {
  const existing = await prisma.lead.findMany({
    where: { businessId: business.id },
    select: { email: true, phone: true },
    orderBy: { createdAt: "desc" },
    take: DUPLICATE_SCAN_LIMIT,
  });
  const existingKeys = normalizeExistingKeys(existing);

  const seenEmails = new Set<string>();
  const seenPhones = new Set<string>();

  const prepared: PreparedRow[] = [];
  const preview: PreviewRow[] = [];
  const failedRows: FailedRow[] = [];

  let duplicatesInFile = 0;
  let duplicatesExisting = 0;
  let invalid = 0;
  let warnings = 0;

  for (let i = 0; i < parsed.rows.length; i++) {
    const rowNumber = i + 1;
    const cells = parsed.rows[i];
    const values = applyMapping(cells, mapping);
    const result = validateRow(values);

    if (!result.ok) {
      invalid++;
      failedRows.push({ rowNumber, reason: result.reason, cells });
      if (preview.length < PREVIEW_ROWS) {
        preview.push({ rowNumber, values, state: "invalid", reason: result.reason, warnings: [] });
      }
      continue;
    }

    const { emailKey, phoneKey } = result;
    const isExistingDuplicate =
      (emailKey !== null && existingKeys.emails.has(emailKey)) ||
      (phoneKey !== null && existingKeys.phones.has(phoneKey));
    const isFileDuplicate =
      (emailKey !== null && seenEmails.has(emailKey)) || (phoneKey !== null && seenPhones.has(phoneKey));

    if (isExistingDuplicate || isFileDuplicate) {
      const reason = isExistingDuplicate
        ? "Already in your leads"
        : "Duplicate of an earlier row in this file";
      if (isExistingDuplicate) duplicatesExisting++;
      else duplicatesInFile++;
      failedRows.push({ rowNumber, reason, cells });
      if (preview.length < PREVIEW_ROWS) {
        preview.push({ rowNumber, values, state: "duplicate", reason, warnings: result.warnings });
      }
      continue;
    }

    if (emailKey) seenEmails.add(emailKey);
    if (phoneKey) seenPhones.add(phoneKey);
    if (result.warnings.length > 0) warnings++;

    prepared.push({ rowNumber, lead: result.lead });
    if (preview.length < PREVIEW_ROWS) {
      preview.push({ rowNumber, values, state: "ready", warnings: result.warnings });
    }
  }

  const allowance = await readPlanAllowance(business.id, prepared.length);

  return {
    totalRows: parsed.rows.length,
    ready: prepared.length,
    duplicatesInFile,
    duplicatesExisting,
    invalid,
    warnings,
    allowance,
    preview,
    failedRows,
    prepared,
  };
}

export interface ImportResult {
  imported: number;
  duplicatesSkipped: number;
  invalidSkipped: number;
  /** Rows dropped purely because the plan's monthly allowance ran out. */
  skippedOverLimit: number;
  allowance: PlanAllowance;
  failedRows: FailedRow[];
  headers: string[];
}

/**
 * Performs the import. Leads, their audit events and the usage counter are
 * written in a single transaction, so a partial failure can never leave
 * imported leads that don't count against the plan.
 */
export async function runImport(
  business: Business,
  parsed: ParsedCsv,
  mapping: ColumnMapping,
  fileName: string
): Promise<ImportResult> {
  const analysis = await analyzeImport(business, parsed, mapping);

  // Re-read the allowance immediately before writing. Two imports started at
  // once could each have been analyzed against the same usage count.
  const allowance = await readPlanAllowance(business.id, analysis.ready);
  const toImport = analysis.prepared.slice(0, allowance.willImport);
  const skippedOverLimit = analysis.ready - toImport.length;

  const importId = crypto.randomUUID();
  const safeFileName = fileName.replace(/[\u0000-\u001F\u007F]/g, "").slice(0, 120) || "upload.csv";

  const summary = {
    import_id: importId,
    file_name: safeFileName,
    rows_uploaded: analysis.totalRows,
    rows_imported: toImport.length,
    duplicates_skipped: analysis.duplicatesInFile + analysis.duplicatesExisting,
    invalid_rows: analysis.invalid,
    skipped_over_plan_limit: skippedOverLimit,
  };

  if (toImport.length > 0) {
    // Ids are generated up front so the audit events can be written in the
    // same transaction without a round-trip per lead.
    const rows = toImport.map((row) => ({ id: crypto.randomUUID(), ...row }));
    const month = currentMonthKey();

    await prisma.usage.upsert({
      where: { businessId_month: { businessId: business.id, month } },
      create: { businessId: business.id, month },
      update: {},
    });

    const operations: Prisma.PrismaPromise<unknown>[] = [];
    for (let i = 0; i < rows.length; i += INSERT_CHUNK) {
      const chunk = rows.slice(i, i + INSERT_CHUNK);
      operations.push(
        prisma.lead.createMany({
          data: chunk.map(({ id, lead }) => ({
            id,
            businessId: business.id,
            firstName: lead.firstName,
            lastName: lead.lastName,
            email: lead.email,
            phone: lead.phone,
            source: lead.source,
            serviceRequested: lead.serviceRequested,
            message: lead.message,
            status: lead.status,
            temperature: lead.temperature,
            estimatedValue: lead.estimatedValue,
            // Imported leads carry no consent until the business records it.
            // The follow-up cron and the manual send path both require these
            // flags, so nothing can be sent to an imported lead by accident.
            smsConsent: false,
            emailConsent: false,
            isDemo: false,
          })),
        })
      );
      operations.push(
        prisma.leadEvent.createMany({
          data: chunk.map(({ id, rowNumber }) => ({
            leadId: id,
            businessId: business.id,
            type: "BULK_IMPORT",
            description: `Imported from ${safeFileName} (row ${rowNumber}).`,
            meta: summary,
          })),
        })
      );
    }

    operations.push(
      prisma.usage.update({
        where: { businessId_month: { businessId: business.id, month } },
        data: { leadsCount: { increment: rows.length } },
      })
    );

    await prisma.$transaction(operations);
  }

  return {
    imported: toImport.length,
    duplicatesSkipped: analysis.duplicatesInFile + analysis.duplicatesExisting,
    invalidSkipped: analysis.invalid,
    skippedOverLimit,
    allowance: { ...allowance, willImport: toImport.length },
    failedRows: analysis.failedRows,
    headers: parsed.headers,
  };
}

/** Guards a mapping that arrived over the wire. */
export function parseMapping(input: unknown, columnCount: number): ColumnMapping | null {
  if (!Array.isArray(input) || input.length !== columnCount) return null;
  const mapping: ColumnMapping = [];
  for (const entry of input) {
    if (entry === null) {
      mapping.push(null);
      continue;
    }
    if (typeof entry !== "string") return null;
    const field = IMPORT_FIELD_KEYS.find((key) => key === entry);
    if (!field) return null;
    mapping.push(field);
  }
  return mapping;
}
