import "server-only";
import { createClient } from "@supabase/supabase-js";
import { isSupabaseAdminConfigured, supabaseServiceRoleKey, supabaseUrl } from "./config";

/**
 * Service-role Supabase client. Bypasses Row Level Security — use only in
 * trusted server contexts (webhooks, cron jobs, admin actions), never send
 * this client or its key to the browser.
 */
export function createSupabaseAdminClient() {
  if (!isSupabaseAdminConfigured) {
    throw new Error(
      "Supabase admin client requested but SUPABASE_SERVICE_ROLE_KEY is not configured."
    );
  }
  return createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
