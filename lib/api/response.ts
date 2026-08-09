import { NextResponse } from "next/server";

export function apiError(message: string, status = 400, extra?: Record<string, unknown>) {
  return NextResponse.json({ error: message, ...extra }, { status });
}

export function apiUnauthorized(message = "Authentication required.") {
  return apiError(message, 401);
}

export function apiForbidden(message = "You don't have access to this resource.") {
  return apiError(message, 403);
}

export function apiNotFound(message = "Not found.") {
  return apiError(message, 404);
}

export function apiRateLimited(retryAfterMs: number) {
  return NextResponse.json(
    { error: "Too many requests. Please slow down." },
    { status: 429, headers: { "Retry-After": String(Math.ceil(retryAfterMs / 1000)) } }
  );
}
