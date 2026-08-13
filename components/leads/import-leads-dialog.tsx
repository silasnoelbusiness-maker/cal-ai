"use client";

import { useCallback, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  Download,
  FileSpreadsheet,
  Upload,
  Users,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { IMPORT_FIELDS, type ColumnMapping, type ImportField } from "@/lib/leads/import/fields";
import { toCsv } from "@/lib/leads/import/csv";
import { cn } from "@/lib/utils";

/** Radix Select needs a non-empty value, so "ignore" gets its own sentinel. */
const IGNORE = "__ignore__";

const STEPS = ["Upload", "Match columns", "Review", "Done"] as const;

interface PreviewRow {
  rowNumber: number;
  values: Partial<Record<ImportField, string>>;
  state: "ready" | "duplicate" | "invalid";
  reason?: string;
  warnings: string[];
}

interface Allowance {
  planLabel: string;
  limit: number;
  used: number;
  remaining: number;
  willImport: number;
  capped: boolean;
}

interface Analysis {
  headers: string[];
  mapping: (ImportField | null)[];
  totalRows: number;
  ready: number;
  duplicatesInFile: number;
  duplicatesExisting: number;
  invalid: number;
  warnings: number;
  allowance: Allowance;
  preview: PreviewRow[];
}

interface FailedRow {
  rowNumber: number;
  reason: string;
  cells: string[];
}

interface ImportResult {
  imported: number;
  duplicatesSkipped: number;
  invalidSkipped: number;
  skippedOverLimit: number;
  allowance: Allowance;
  failedRows: FailedRow[];
  headers: string[];
}

type Step = "upload" | "map" | "review" | "done";

/**
 * Multi-step CSV import.
 *
 * The browser only ever holds the file and the user's column choices — every
 * decision that matters (what parses, what's a duplicate, how many rows the
 * plan allows) is made server-side, and the file is re-validated from
 * scratch on the final import. The preview is a display of the server's
 * answer, not an input to it.
 */
export function ImportLeadsDialog({ triggerVariant = "outline" }: { triggerVariant?: "outline" | "default" }) {
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState<Step>("upload");
  const [file, setFile] = useState<File | null>(null);
  const [analysis, setAnalysis] = useState<Analysis | null>(null);
  const [mapping, setMapping] = useState<ColumnMapping>([]);
  const [result, setResult] = useState<ImportResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [dragging, setDragging] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const router = useRouter();

  const reset = useCallback(() => {
    setStep("upload");
    setFile(null);
    setAnalysis(null);
    setMapping([]);
    setResult(null);
    setError(null);
    setPending(false);
    setDragging(false);
  }, []);

  function handleOpenChange(next: boolean) {
    setOpen(next);
    if (!next) {
      // Leads imported in this session should be visible behind the dialog.
      if (result?.imported) router.refresh();
      reset();
    }
  }

  async function post(path: string, body: FormData) {
    const res = await fetch(path, { method: "POST", body });
    const data = await res.json().catch(() => null);
    if (!res.ok) throw new Error(data?.error || "Something went wrong. Try again.");
    return data;
  }

  async function handleFile(selected: File) {
    setError(null);
    setFile(selected);
    setPending(true);
    try {
      const body = new FormData();
      body.set("file", selected);
      const data: Analysis = await post("/api/leads/import/preview", body);
      setAnalysis(data);
      setMapping(data.mapping);
      setStep("map");
    } catch (err) {
      setFile(null);
      setError(err instanceof Error ? err.message : "Couldn't read that file.");
    } finally {
      setPending(false);
    }
  }

  async function handleReview() {
    if (!file) return;
    setError(null);
    setPending(true);
    try {
      const body = new FormData();
      body.set("file", file);
      body.set("mapping", JSON.stringify(mapping));
      const data: Analysis = await post("/api/leads/import/preview", body);
      setAnalysis(data);
      setStep("review");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't validate that file.");
    } finally {
      setPending(false);
    }
  }

  async function handleImport() {
    if (!file) return;
    setError(null);
    setPending(true);
    try {
      const body = new FormData();
      body.set("file", file);
      body.set("mapping", JSON.stringify(mapping));
      const data: ImportResult = await post("/api/leads/import", body);
      setResult(data);
      setStep("done");
    } catch (err) {
      setError(err instanceof Error ? err.message : "The import couldn't be completed.");
    } finally {
      setPending(false);
    }
  }

  function downloadErrorReport() {
    if (!result) return;
    const headers = [...result.headers, "error_reason"];
    const rows = result.failedRows.map((row) => {
      const cells = [...row.cells];
      while (cells.length < result.headers.length) cells.push("");
      return [...cells.slice(0, result.headers.length), row.reason];
    });
    const blob = new Blob([toCsv(headers, rows)], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "converana-import-errors.csv";
    link.click();
    URL.revokeObjectURL(url);
  }

  const mappedFields = new Set(mapping.filter(Boolean) as ImportField[]);
  const hasFirstName = mappedFields.has("firstName");
  const hasIdentifier = mappedFields.has("email") || mappedFields.has("phone");
  const stepIndex = step === "upload" ? 0 : step === "map" ? 1 : step === "review" ? 2 : 3;

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button variant={triggerVariant}>
          <Upload className="h-4 w-4" />
          Import CSV
        </Button>
      </DialogTrigger>

      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle>Import leads</DialogTitle>
          <DialogDescription>
            Bring in existing leads from your CRM, a spreadsheet, Meta campaigns, or any other lead
            source.
          </DialogDescription>
        </DialogHeader>

        <ol className="mb-5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
          {STEPS.map((label, index) => (
            <li key={label} className="flex items-center gap-2">
              <span
                className={cn(
                  "flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-medium",
                  index < stepIndex && "bg-brand/15 text-brand",
                  index === stepIndex && "bg-brand text-brand-foreground",
                  index > stepIndex && "bg-muted-surface text-muted"
                )}
              >
                {index + 1}
              </span>
              <span className={cn(index === stepIndex ? "font-medium text-foreground" : "text-muted")}>
                {label}
              </span>
              {index < STEPS.length - 1 && <span className="text-border">—</span>}
            </li>
          ))}
        </ol>

        {error && (
          <p role="alert" className="mb-4 rounded-md border border-danger/30 bg-danger/5 px-3 py-2 text-sm text-danger">
            {error}
          </p>
        )}

        {step === "upload" && (
          <div className="space-y-4">
            <div
              onDragOver={(e) => {
                e.preventDefault();
                setDragging(true);
              }}
              onDragLeave={() => setDragging(false)}
              onDrop={(e) => {
                e.preventDefault();
                setDragging(false);
                const dropped = e.dataTransfer.files?.[0];
                if (dropped) void handleFile(dropped);
              }}
              className={cn(
                "flex flex-col items-center justify-center rounded-lg border border-dashed px-6 py-12 text-center transition-colors",
                dragging ? "border-brand bg-brand/5" : "border-border bg-muted-surface/40"
              )}
            >
              <FileSpreadsheet className="mb-3 h-8 w-8 text-muted" aria-hidden />
              <p className="text-sm font-medium text-foreground">
                {pending ? "Reading your file…" : "Drag and drop your CSV here"}
              </p>
              <p className="mt-1 text-xs text-muted">CSV files up to 5 MB, 2,000 rows per import.</p>
              <input
                ref={inputRef}
                type="file"
                accept=".csv,.tsv,.txt,text/csv"
                className="sr-only"
                onChange={(e) => {
                  const selected = e.target.files?.[0];
                  if (selected) void handleFile(selected);
                  e.target.value = "";
                }}
              />
              <Button
                variant="outline"
                className="mt-4"
                loading={pending}
                onClick={() => inputRef.current?.click()}
              >
                Choose file
              </Button>
            </div>

            <p className="text-xs text-muted">
              Not sure about the format?{" "}
              <a href="/api/leads/import/sample" className="font-medium text-brand hover:underline" download>
                Download a sample CSV
              </a>
              . Columns can be in any order, and you can match them in the next step.
            </p>
          </div>
        )}

        {step === "map" && analysis && (
          <div className="space-y-4">
            <p className="text-sm text-muted">
              We found <strong className="text-foreground">{analysis.totalRows.toLocaleString()}</strong> rows
              and {analysis.headers.length} columns. Check the matches below — we&apos;ve guessed where we
              can.
            </p>

            <div className="max-h-72 overflow-auto rounded-md border border-border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Column in your file</TableHead>
                    <TableHead>Import as</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {analysis.headers.map((header, index) => (
                    <TableRow key={`${header}-${index}`}>
                      <TableCell className="font-medium text-foreground">{header || `Column ${index + 1}`}</TableCell>
                      <TableCell>
                        <Select
                          value={mapping[index] ?? IGNORE}
                          onValueChange={(value) => {
                            setMapping((current) => {
                              const next = [...current];
                              const field = value === IGNORE ? null : (value as ImportField);
                              // A Lead field can only come from one column.
                              if (field) {
                                for (let i = 0; i < next.length; i++) {
                                  if (i !== index && next[i] === field) next[i] = null;
                                }
                              }
                              next[index] = field;
                              return next;
                            });
                          }}
                        >
                          <SelectTrigger className="max-w-56">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value={IGNORE}>Ignore this column</SelectItem>
                            {IMPORT_FIELDS.map((field) => (
                              <SelectItem key={field.key} value={field.key}>
                                {field.label}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            {(!hasFirstName || !hasIdentifier) && (
              <p className="flex items-start gap-2 text-xs text-warning">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                {!hasFirstName
                  ? "Match a column to First Name to continue."
                  : "Match a column to Email or Phone — a lead needs at least one way to be contacted."}
              </p>
            )}

            <DialogFooter>
              <Button variant="outline" onClick={reset} disabled={pending}>
                <ArrowLeft className="h-4 w-4" />
                Start over
              </Button>
              <Button onClick={handleReview} loading={pending} disabled={!hasFirstName || !hasIdentifier}>
                Review import
              </Button>
            </DialogFooter>
          </div>
        )}

        {step === "review" && analysis && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Summary label="Rows detected" value={analysis.totalRows} />
              <Summary label="Ready to import" value={analysis.allowance.willImport} tone="success" />
              <Summary
                label="Duplicates"
                value={analysis.duplicatesInFile + analysis.duplicatesExisting}
                tone={analysis.duplicatesInFile + analysis.duplicatesExisting > 0 ? "warning" : undefined}
              />
              <Summary label="Invalid" value={analysis.invalid} tone={analysis.invalid > 0 ? "danger" : undefined} />
            </div>

            {analysis.allowance.capped && (
              <p className="flex items-start gap-2 rounded-md border border-warning/30 bg-warning-surface px-3 py-2 text-xs">
                <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-warning" aria-hidden />
                <span className="text-foreground">
                  You have {analysis.allowance.remaining.toLocaleString()} of{" "}
                  {analysis.allowance.limit.toLocaleString()} leads remaining on your{" "}
                  {analysis.allowance.planLabel} plan this month. Only the first{" "}
                  {analysis.allowance.willImport.toLocaleString()} rows will be imported — upgrade your plan
                  to import the rest.
                </span>
              </p>
            )}

            <div className="overflow-x-auto rounded-md border border-border">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-12">Row</TableHead>
                    <TableHead>Name</TableHead>
                    <TableHead>Email</TableHead>
                    <TableHead>Phone</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {analysis.preview.map((row) => (
                    <TableRow key={row.rowNumber}>
                      <TableCell className="text-muted">{row.rowNumber}</TableCell>
                      <TableCell className="text-foreground">
                        {[row.values.firstName, row.values.lastName].filter(Boolean).join(" ") || "—"}
                      </TableCell>
                      <TableCell className="text-muted">{row.values.email || "—"}</TableCell>
                      <TableCell className="text-muted">{row.values.phone || "—"}</TableCell>
                      <TableCell>
                        <Badge
                          variant={
                            row.state === "ready" ? "success" : row.state === "duplicate" ? "secondary" : "danger"
                          }
                        >
                          {row.state === "ready" ? "Ready" : row.state === "duplicate" ? "Duplicate" : "Invalid"}
                        </Badge>
                        {(row.reason || row.warnings.length > 0) && (
                          <p className="mt-1 text-xs text-muted">{row.reason ?? row.warnings.join("; ")}</p>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            {analysis.totalRows > analysis.preview.length && (
              <p className="text-xs text-muted">
                Showing the first {analysis.preview.length} rows. All{" "}
                {analysis.totalRows.toLocaleString()} were checked.
              </p>
            )}

            <p className="rounded-md border border-border bg-muted-surface/50 px-3 py-2 text-xs text-muted">
              Imported leads are stored only — Converana won&apos;t message them, qualify them, or start
              any follow-up automation. Only contact leads when you have the appropriate permission to do
              so.
            </p>

            <DialogFooter>
              <Button variant="outline" onClick={() => setStep("map")} disabled={pending}>
                <ArrowLeft className="h-4 w-4" />
                Back
              </Button>
              <Button
                onClick={handleImport}
                loading={pending}
                disabled={analysis.allowance.willImport === 0}
              >
                {analysis.allowance.willImport === 0
                  ? "Nothing to import"
                  : `Import ${analysis.allowance.willImport.toLocaleString()} lead${analysis.allowance.willImport === 1 ? "" : "s"}`}
              </Button>
            </DialogFooter>
          </div>
        )}

        {step === "done" && result && (
          <div className="space-y-4">
            <div className="flex flex-col items-center gap-2 py-4 text-center">
              <CheckCircle2 className="h-9 w-9 text-success" aria-hidden />
              <p className="text-lg font-semibold text-foreground">Import complete</p>
              <p className="text-sm text-muted">
                {result.imported.toLocaleString()} lead{result.imported === 1 ? "" : "s"} imported
              </p>
            </div>

            <ul className="space-y-1 rounded-md border border-border bg-muted-surface/50 px-4 py-3 text-sm text-muted">
              <li>{result.imported.toLocaleString()} leads imported</li>
              <li>{result.duplicatesSkipped.toLocaleString()} duplicates skipped</li>
              <li>{result.invalidSkipped.toLocaleString()} invalid rows skipped</li>
              {result.skippedOverLimit > 0 && (
                <li className="text-warning">
                  {result.skippedOverLimit.toLocaleString()} rows skipped — your {result.allowance.planLabel}{" "}
                  plan&apos;s monthly lead limit was reached
                </li>
              )}
            </ul>

            <DialogFooter>
              {result.failedRows.length > 0 && (
                <Button variant="outline" onClick={downloadErrorReport}>
                  <Download className="h-4 w-4" />
                  Download error report
                </Button>
              )}
              <Button
                onClick={() => {
                  handleOpenChange(false);
                  router.push("/dashboard/leads");
                }}
              >
                <Users className="h-4 w-4" />
                View leads
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function Summary({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone?: "success" | "warning" | "danger";
}) {
  return (
    <div className="min-w-0 rounded-md border border-border px-3 py-2">
      <p
        className={cn(
          "text-lg font-semibold",
          tone === "success" && "text-success",
          tone === "warning" && "text-warning",
          tone === "danger" && "text-danger",
          !tone && "text-foreground"
        )}
      >
        {value.toLocaleString()}
      </p>
      <p className="truncate text-xs text-muted">{label}</p>
    </div>
  );
}
