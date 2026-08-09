import "server-only";
import type { Business, Lead } from "@prisma/client";
import { AIUnavailableError, AI_MODEL, getAnthropicClient } from "./client";
import { buildSystemPrompt } from "./prompt";
import { formatTranscript } from "./context";
import type { AiMessage } from "./types";

const STEP_GUIDANCE: Record<number, string> = {
  1: "This is a quick 30-minute check-in after the lead went quiet. Keep it very short and low-pressure.",
  2: "This is a follow-up about 24 hours after the lead went quiet. Re-offer help and make it easy for them to respond, e.g. by suggesting a time.",
  3: "This is the final follow-up after a few days of silence. Keep the door open without being pushy, and let them know they can reach out anytime.",
};

export interface GeneratedFollowUp {
  content: string;
}

/**
 * Generates a context-aware follow-up message for a quiet lead (Section
 * 26/59/67). Every follow-up considers the full conversation so far so
 * consecutive follow-ups never repeat themselves verbatim.
 */
export async function generateFollowUp(params: {
  business: Business;
  lead: Pick<Lead, "firstName" | "lastName" | "serviceRequested">;
  messages: AiMessage[];
  stepIndex: number;
}): Promise<GeneratedFollowUp> {
  const client = getAnthropicClient();
  const system = buildSystemPrompt(params.business);
  const guidance = STEP_GUIDANCE[params.stepIndex] || STEP_GUIDANCE[1];

  const userContent = `The lead ${params.lead.firstName} has gone quiet after asking about ${
    params.lead.serviceRequested || "a service"
  }. ${guidance}

Conversation so far:
${formatTranscript(params.messages)}

Write a short, natural follow-up message continuing this specific conversation — do not reuse generic wording from previous follow-ups. Reply with only the message text.`;

  try {
    const response = await client.messages.create({
      model: AI_MODEL,
      max_tokens: 300,
      system,
      messages: [{ role: "user", content: userContent }],
    });

    const textBlock = response.content.find((block) => block.type === "text");
    const content = textBlock && textBlock.type === "text" ? textBlock.text.trim() : "";
    if (!content) throw new AIUnavailableError("AI returned an empty follow-up.");

    return { content };
  } catch (err) {
    if (err instanceof AIUnavailableError) throw err;
    console.error("[ai] generateFollowUp request failed", err);
    throw new AIUnavailableError();
  }
}
