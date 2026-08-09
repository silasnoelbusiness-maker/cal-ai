import "server-only";
import type { Business, Lead } from "@prisma/client";
import { AIUnavailableError, AI_MODEL, getAnthropicClient } from "./client";
import { buildSystemPrompt } from "./prompt";
import { formatTranscript } from "./context";
import {
  QualificationResultSchema,
  scoreToTemperature,
  type AiMessage,
  type QualifiedLead,
} from "./types";

const QUALIFY_TOOL = {
  name: "submit_qualification",
  description: "Submit the structured qualification assessment for this lead.",
  input_schema: {
    type: "object" as const,
    properties: {
      qualification_score: {
        type: "integer",
        minimum: 0,
        maximum: 100,
        description: "0-100 score of how sales-ready this lead is.",
      },
      intent: { type: "string", enum: ["high", "medium", "low", "unknown"] },
      urgency: { type: "string", enum: ["high", "medium", "low", "unknown"] },
      service: { type: "string", description: "Service requested, or 'Unknown'." },
      location: { type: "string", description: "Customer location/ZIP, or 'Unknown'." },
      budget: { type: "string", description: "Budget mentioned, or 'Unknown'." },
      availability: { type: "string", description: "Availability mentioned, or 'Unknown'." },
      summary: { type: "string", description: "1-3 sentence factual summary." },
      recommended_action: { type: "string", description: "What the business should do next." },
      needs_human: {
        type: "boolean",
        description: "True if this needs a human: anger, emergency, complaint, refund, legal threat, unclear situation, or explicit request for a human.",
      },
    },
    required: [
      "qualification_score",
      "intent",
      "urgency",
      "service",
      "location",
      "budget",
      "availability",
      "summary",
      "recommended_action",
      "needs_human",
    ],
  },
};

/**
 * Runs structured AI lead qualification (Section 16/58). Never fabricates
 * information — the model is instructed to answer "Unknown" for anything it
 * can't determine, and the result is validated with Zod before use.
 */
export async function qualifyLead(params: {
  business: Business;
  lead: Pick<Lead, "firstName" | "lastName" | "serviceRequested" | "message" | "source">;
  messages: AiMessage[];
}): Promise<QualifiedLead> {
  const client = getAnthropicClient();
  const system = `${buildSystemPrompt(params.business)}

You are now performing internal lead qualification, not talking to the customer. Analyze the lead below and call submit_qualification with your honest assessment. Never invent facts: use "Unknown" for any text field you cannot determine from the information given, and "unknown" for intent/urgency if unclear.`;

  const userContent = `Lead details:
Name: ${params.lead.firstName} ${params.lead.lastName || ""}
Source: ${params.lead.source}
Service requested (as submitted): ${params.lead.serviceRequested || "Unknown"}
Initial message: ${params.lead.message || "(none)"}

Conversation so far:
${formatTranscript(params.messages)}`;

  let response;
  try {
    response = await client.messages.create({
      model: AI_MODEL,
      max_tokens: 1024,
      system,
      messages: [{ role: "user", content: userContent }],
      tools: [QUALIFY_TOOL],
      tool_choice: { type: "tool", name: "submit_qualification" },
    });
  } catch (err) {
    console.error("[ai] qualifyLead request failed", err);
    throw new AIUnavailableError();
  }

  const toolUse = response.content.find((block) => block.type === "tool_use");
  if (!toolUse || toolUse.type !== "tool_use") {
    throw new AIUnavailableError("AI did not return a structured qualification result.");
  }

  const parsed = QualificationResultSchema.safeParse(toolUse.input);
  if (!parsed.success) {
    console.error("[ai] qualifyLead validation failed", parsed.error.flatten());
    throw new AIUnavailableError("AI returned an unexpected qualification format.");
  }

  return {
    ...parsed.data,
    temperature: scoreToTemperature(parsed.data.qualification_score),
  };
}
