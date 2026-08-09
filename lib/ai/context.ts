import type { AiMessage } from "./types";

/**
 * Formats recent conversation history as plain text for prompts, and caps
 * how much history is sent to control AI cost (Section 69) — long threads
 * are truncated to the most recent turns rather than replayed in full.
 */
export function formatTranscript(messages: AiMessage[], limit = 24): string {
  if (messages.length === 0) return "(no messages yet)";
  const recent = messages.slice(-limit);
  const label: Record<AiMessage["sender"], string> = {
    CUSTOMER: "Customer",
    AI: "AI",
    BUSINESS: "Business",
    SYSTEM: "System",
  };
  return recent.map((m) => `${label[m.sender]}: ${m.content}`).join("\n");
}
