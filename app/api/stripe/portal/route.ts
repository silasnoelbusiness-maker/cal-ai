import { NextResponse, type NextRequest } from "next/server";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiRateLimited, apiUnauthorized } from "@/lib/api/response";
import { rateLimit } from "@/lib/api/rate-limit";
import { createPortalSession } from "@/lib/stripe/checkout";
import { BillingUnavailableError } from "@/lib/stripe/client";

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const { allowed, retryAfterMs } = rateLimit(`stripe-portal:${auth.business.id}`, 10, 60_000);
  if (!allowed) return apiRateLimited(retryAfterMs);

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || request.nextUrl.origin;

  try {
    const session = await createPortalSession(auth.business, appUrl);
    return NextResponse.json({ url: session.url });
  } catch (err) {
    if (err instanceof BillingUnavailableError) return apiError(err.message, 503);
    console.error("[api/stripe/portal] failed", err);
    return apiError(err instanceof Error ? err.message : "Couldn't open billing portal.", 400);
  }
}
