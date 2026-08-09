import "server-only";
import type { Business, Lead } from "@prisma/client";
import { AIUnavailableError, AI_MODEL, getAnthropicClient } from "./client";
import { buildSystemPrompt } from "./prompt";
import { formatTranscript } from "./context";
import type { AiMessage } from "./types";

export interface GeneratedReply {
  content: string;
}

/**
 * Generates the AI assistant's next reply in an ongoing conversation with a
 * lead (Section 18/24). Used both for the automatic first response to a new
 * lead and for the "Suggest AI Reply" button, which businesses can edit
 * before sending — this function never sends anything itself.
 */
export async function generateBusinessReply(params: {
  business: Business;
  lead: Pick<Lead, "firstName" | "lastName" | "serviceRequested" | "message">;
  messages: AiMessage[];
}): Promise<GeneratedReply> {
  const client = getAnthropicClient();
  const system = buildSystemPrompt(params.business);

  const isFirstContact = params.messages.length === 0;
  const userContent = isFirstContact
    ? `A new lead just came in. Write the first message to them.
Name: ${params.lead.firstName}
Service requested: ${params.lead.serviceRequested || "Unknown"}
Their message: ${params.lead.message || "(no message provided)"}

Greet them briefly, confirm you can help with what they mentioned (if known), and ask one useful qualifying question. Reply with only the message text — no preamble, no quotation marks.`
    : `Conversation so far:
${formatTranscript(params.messages)}

Write the next message from the AI assistant to the customer. Reply with only the message text — no preamble, no quotation marks, no signature.`;

  try {
    const response = await client.messages.create({
      model: AI_MODEL,
      max_tokens: 400,
      system,
      messages: [{ role: "user", content: userContent }],
    });

    const textBlock = response.content.find((block) => block.type === "text");
    const content = textBlock && textBlock.type === "text" ? textBlock.text.trim() : "";
    if (!content) throw new AIUnavailableError("AI returned an empty reply.");

    return { content };
  } catch (err) {
    if (err instanceof AIUnavailableError) throw err;
    console.error("[ai] generateBusinessReply request failed", err);
    throw new AIUnavailableError();
  }
}
