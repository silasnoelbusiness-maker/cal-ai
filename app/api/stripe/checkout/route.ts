import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { getApiAuthContext } from "@/lib/auth/session";
import { apiError, apiUnauthorized } from "@/lib/api/response";
import { createCheckoutSession } from "@/lib/stripe/checkout";
import { BillingUnavailableError } from "@/lib/stripe/client";

const BodySchema = z.object({ plan: z.enum(["STARTER", "GROWTH", "PRO"]) });

export async function POST(request: NextRequest) {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  const json = await request.json().catch(() => null);
  const parsed = BodySchema.safeParse(json);
  if (!parsed.success) return apiError(parsed.error.issues[0].message);

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || request.nextUrl.origin;

  try {
    const session = await createCheckoutSession(auth.business, parsed.data.plan, appUrl);
    return NextResponse.json({ url: session.url });
  } catch (err) {
    if (err instanceof BillingUnavailableError) return apiError(err.message, 503);
    console.error("[api/stripe/checkout] failed", err);
    return apiError(err instanceof Error ? err.message : "Couldn't start checkout.", 500);
  }
}
