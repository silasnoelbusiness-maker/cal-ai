import "server-only";
import twilio from "twilio";
import { isTwilioConfigured } from "@/lib/auth/config";

let cachedClient: ReturnType<typeof twilio> | null = null;

function getClient() {
  if (!cachedClient) {
    cachedClient = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
  }
  return cachedClient;
}

export interface SendSmsParams {
  to: string;
  body: string;
}

export interface SendSmsResult {
  sent: boolean;
  reason?: string;
}

/**
 * Central SMS-sending abstraction (Section 27). Never call Twilio directly
 * elsewhere — this is the one place that knows how to send, and the one
 * place that degrades gracefully when Twilio isn't configured.
 */
export async function sendSMS(params: SendSmsParams): Promise<SendSmsResult> {
  if (!isTwilioConfigured) {
    console.warn(`[sms] Twilio not configured — skipped SMS to ${params.to}`);
    return {
      sent: false,
      reason: "SMS isn't configured. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_PHONE_NUMBER.",
    };
  }

  try {
    await getClient().messages.create({
      to: params.to,
      from: process.env.TWILIO_PHONE_NUMBER,
      body: params.body,
    });
    return { sent: true };
  } catch (err) {
    console.error("[sms] failed to send", err);
    return { sent: false, reason: "Unexpected error sending SMS." };
  }
}
