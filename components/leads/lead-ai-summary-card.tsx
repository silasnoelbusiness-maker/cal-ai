import { Sparkles, ShieldAlert } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { generateLeadSummary } from "@/lib/ai/summary";
import { scoreToTemperature } from "@/lib/ai/types";
import type { Lead } from "@prisma/client";

export function LeadAiSummaryCard({ lead }: { lead: Lead }) {
  const lines = generateLeadSummary(lead);
  const score = lead.qualificationScore;

  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2 space-y-0">
        <Sparkles className="h-4 w-4 text-brand" />
        <CardTitle>AI summary</CardTitle>
      </CardHeader>
      <CardContent>
        {lead.needsHuman && (
          <div className="mb-4 flex items-start gap-2 rounded-md bg-danger-surface px-3 py-2.5 text-sm text-danger">
            <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />
            <span>This lead was flagged for human follow-up — review before the AI continues automatically.</span>
          </div>
        )}

        {score !== null && (
          <div className="mb-4">
            <div className="mb-1 flex items-center justify-between text-xs">
              <span className="text-muted">Qualification score</span>
              <span className="font-medium text-foreground">
                {score}/100 · {scoreToTemperature(score)}
              </span>
            </div>
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted-surface">
              <div
                className="h-full rounded-full bg-brand transition-all"
                style={{ width: `${score}%` }}
              />
            </div>
          </div>
        )}

        <dl className="space-y-3 text-sm">
          {lines.map((line, i) =>
            line.label ? (
              <div key={i} className="flex justify-between gap-4">
                <dt className="text-muted">{line.label}</dt>
                <dd className="text-right font-medium text-foreground">{line.value}</dd>
              </div>
            ) : (
              <p key={i} className="text-foreground">
                {line.value}
              </p>
            )
          )}
        </dl>
      </CardContent>
    </Card>
  );
}
