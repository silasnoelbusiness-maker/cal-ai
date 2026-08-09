import "server-only";
import type { NextRequest } from "next/server";
import type { Business } from "@prisma/client";
import { getApiAuthContext } from "@/lib/auth/session";
import { resolveApiKey } from "@/lib/api-keys";

export interface RequestAuthContext {
  business: Business;
  /** Present when authenticated via a business API key rather than a session. */
  apiKeyId?: string;
}

/**
 * Resolves the business behind an incoming API request. Tries a Bearer API
 * key first (for external integrations), then falls back to the dashboard
 * session cookie (for the app's own client-side calls). Every route using
 * this derives its authorization from here — never from a client-supplied
 * businessId.
 */
export async function resolveRequestAuth(request: NextRequest): Promise<RequestAuthContext | null> {
  const authHeader = request.headers.get("authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const rawKey = authHeader.slice("Bearer ".length).trim();
    if (rawKey.startsWith("ll_live_")) {
      const record = await resolveApiKey(rawKey);
      if (!record) return null;
      return { business: record.business, apiKeyId: record.id };
    }
  }

  const sessionAuth = await getApiAuthContext();
  if (!sessionAuth) return null;
  return { business: sessionAuth.business };
}
