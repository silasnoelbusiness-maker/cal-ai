import { z } from "zod";
import type { LeadTemperature } from "@prisma/client";

/** A minimal, provider-agnostic chat turn used to build AI prompts. */
export interface AiMessage {
  sender: "CUSTOMER" | "AI" | "BUSINESS" | "SYSTEM";
  content: string;
}

/**
 * Score thresholds that map a 0-100 qualification score to a lead
 * temperature. Centralized here so the mapping is consistent and testable —
 * change these two numbers to retune the whole product (Section 58).
 */
export const TEMPERATURE_THRESHOLDS = {
  HOT: 70,
  WARM: 40,
} as const;

export function scoreToTemperature(score: number): LeadTemperature {
  if (score >= TEMPERATURE_THRESHOLDS.HOT) return "HOT";
  if (score >= TEMPERATURE_THRESHOLDS.WARM) return "WARM";
  return "COLD";
}

/**
 * Structured lead-qualification result. The model is instructed to never
 * invent information — any field it can't determine from the conversation
 * must be the literal string "Unknown" (or false for booleans it can't
 * support with evidence).
 */
export const QualificationResultSchema = z.object({
  qualification_score: z.number().int().min(0).max(100),
  intent: z.enum(["high", "medium", "low", "unknown"]),
  urgency: z.enum(["high", "medium", "low", "unknown"]),
  service: z.string().min(1),
  location: z.string().min(1),
  budget: z.string().min(1),
  availability: z.string().min(1),
  summary: z.string().min(1),
  recommended_action: z.string().min(1),
  needs_human: z.boolean(),
});

export type QualificationResult = z.infer<typeof QualificationResultSchema>;

export interface QualifiedLead extends QualificationResult {
  temperature: LeadTemperature;
}
