/**
 * Admin identification.
 *
 * Deliberately env-driven rather than a database column: an `isAdmin` field
 * would require a migration against the live production database, and an
 * allowlist that only exists in server environment variables cannot be
 * escalated into by anything a normal user can do through the app.
 *
 * Set ADMIN_EMAILS to a comma-separated list, e.g.
 *   ADMIN_EMAILS="you@converana.com,ops@converana.com"
 *
 * With ADMIN_EMAILS unset there are NO admins and every admin surface is
 * closed — failing shut rather than open.
 */
export function adminEmails(): string[] {
  return (process.env.ADMIN_EMAILS || "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

export function isAdminEmail(email: string | null | undefined): boolean {
  if (!email) return false;
  const list = adminEmails();
  if (list.length === 0) return false;
  return list.includes(email.trim().toLowerCase());
}

/** True when at least one admin is configured (used for setup notices). */
export const hasAdminsConfigured = () => adminEmails().length > 0;
