import "server-only";
import { Resend } from "resend";
import { isResendConfigured } from "@/lib/auth/config";

let cachedClient: Resend | null = null;

function getClient(): Resend {
  if (!cachedClient) {
    cachedClient = new Resend(process.env.RESEND_API_KEY);
  }
  return cachedClient;
}

export interface SendEmailParams {
  to: string;
  subject: string;
  text: string;
  html?: string;
}

export interface SendEmailResult {
  sent: boolean;
  reason?: string;
}

/**
 * Central email-sending abstraction (Section 28). Never scatter Resend
 * calls elsewhere — everything routes through here so the graceful
 * "not configured" fallback only needs to live in one place.
 */
export async function sendEmail(params: SendEmailParams): Promise<SendEmailResult> {
  if (!isResendConfigured) {
    console.warn(`[email] RESEND_API_KEY not configured — skipped email to ${params.to}: ${params.subject}`);
    return { sent: false, reason: "Email isn't configured. Set RESEND_API_KEY and RESEND_FROM_EMAIL." };
  }

  const from = process.env.RESEND_FROM_EMAIL;
  if (!from) {
    console.warn("[email] RESEND_FROM_EMAIL not configured");
    return { sent: false, reason: "RESEND_FROM_EMAIL isn't configured." };
  }

  try {
    const { error } = await getClient().emails.send({
      from,
      to: params.to,
      subject: params.subject,
      text: params.text,
      html: params.html,
    });
    if (error) {
      console.error("[email] Resend returned an error", error);
      return { sent: false, reason: error.message };
    }
    return { sent: true };
  } catch (err) {
    console.error("[email] failed to send", err);
    return { sent: false, reason: "Unexpected error sending email." };
  }
}
