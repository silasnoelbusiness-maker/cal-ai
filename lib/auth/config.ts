/**
 * Centralized "is this external service configured" checks. Converana must
 * start and render a clear setup message instead of crashing when a service
 * (Supabase, Anthropic, Stripe, Twilio, Resend) has no credentials yet.
 */
export const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
export const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";
export const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

function looksConfigured(value: string): boolean {
  return value.length > 0 && !value.includes("xxxx") && !value.startsWith("your-");
}

export const isSupabaseConfigured = looksConfigured(supabaseUrl) && looksConfigured(supabaseAnonKey);
export const isSupabaseAdminConfigured = isSupabaseConfigured && looksConfigured(supabaseServiceRoleKey);

export const isAnthropicConfigured = looksConfigured(process.env.ANTHROPIC_API_KEY || "");
export const isStripeConfigured = looksConfigured(process.env.STRIPE_SECRET_KEY || "");
export const isTwilioConfigured =
  looksConfigured(process.env.TWILIO_ACCOUNT_SID || "") &&
  looksConfigured(process.env.TWILIO_AUTH_TOKEN || "") &&
  looksConfigured(process.env.TWILIO_PHONE_NUMBER || "");
export const isResendConfigured = looksConfigured(process.env.RESEND_API_KEY || "");
