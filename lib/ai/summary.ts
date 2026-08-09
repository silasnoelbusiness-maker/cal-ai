import type { Lead } from "@prisma/client";
import { formatCurrency, unknownOr } from "@/lib/utils";

export interface LeadSummaryLine {
  label: string | null;
  value: string;
}

/**
 * Formats a lead's stored AI qualification fields into the human-readable
 * summary shown on the lead detail page (Section 15). This is a pure
 * formatter, not a new AI call — the qualification fields it reads were
 * already produced by qualifyLead(), so re-summarizing via another AI
 * request would just add cost and a second chance to fabricate details.
 */
export function generateLeadSummary(lead: Lead): LeadSummaryLine[] {
  if (!lead.aiSummary && lead.qualificationScore === null) {
    return [{ label: null, value: "This lead hasn't been qualified by AI yet." }];
  }

  const lines: LeadSummaryLine[] = [];

  if (lead.aiSummary) {
    lines.push({ label: null, value: lead.aiSummary });
  }

  lines.push({ label: "Location", value: unknownOr(lead.aiLocation) });
  lines.push({ label: "Urgency", value: unknownOr(lead.aiUrgency) });
  lines.push({ label: "Availability", value: unknownOr(lead.aiAvailability) });
  lines.push({
    label: "Estimated job value",
    value: lead.estimatedValue ? formatCurrency(lead.estimatedValue.toString()) : "Unknown",
  });
  lines.push({
    label: "Recommended action",
    value: unknownOr(lead.aiRecommendedAction),
  });

  return lines;
}
