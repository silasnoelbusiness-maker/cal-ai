import "server-only";
import Anthropic from "@anthropic-ai/sdk";
import { isAnthropicConfigured } from "@/lib/auth/config";

/**
 * Default model for all Converana AI features. Override with ANTHROPIC_MODEL
 * if needed (e.g. to pin a specific dated snapshot).
 */
export const AI_MODEL = process.env.ANTHROPIC_MODEL || "claude-sonnet-5";

export class AIUnavailableError extends Error {
  constructor(message = "AI is temporarily unavailable. You can still reply manually.") {
    super(message);
    this.name = "AIUnavailableError";
  }
}

let cachedClient: Anthropic | null = null;

/**
 * Lazily creates the Anthropic client. Throws AIUnavailableError instead of
 * a raw SDK error when ANTHROPIC_API_KEY isn't configured, so callers can
 * show a graceful "AI unavailable" message instead of crashing.
 */
export function getAnthropicClient(): Anthropic {
  if (!isAnthropicConfigured) {
    throw new AIUnavailableError(
      "AI features aren't configured yet. Set ANTHROPIC_API_KEY to enable AI qualification and replies."
    );
  }
  if (!cachedClient) {
    cachedClient = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  }
  return cachedClient;
}
