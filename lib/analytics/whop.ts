/**
 * Whop conversion tracking.
 *
 * Whop is used for advertising attribution only. Nothing here touches
 * billing — checkout, subscriptions and payments are Stripe's alone, and no
 * plan, price or payment detail is ever put on the wire.
 *
 * The base pixel (components/analytics/whop-pixel.tsx) defines a global
 * `whop` object whose `track` calls are queued until Whop's s.js loads, so
 * these calls are safe to make the moment the inline snippet has run.
 */

/** The subset of Whop's queued API this module uses. */
interface WhopGlobal {
  track: (event: string, payload?: Record<string, unknown>) => void;
}

declare global {
  interface Window {
    whop?: WhopGlobal;
  }
}

/** Whop's official conversion event, the one the ads campaign optimizes for. */
const COMPLETE_REGISTRATION = "complete_registration";
const IDENTIFY = "identify";

/** How long to wait for the pixel snippet to define `window.whop`. */
const READY_TIMEOUT_MS = 3000;
const READY_POLL_MS = 200;

/**
 * Registrations already reported, so one account can only ever produce one
 * conversion. Backed by localStorage — the in-memory Set alone would be lost
 * on reload, and React's development double-invoke would fire twice.
 */
const firedThisSession = new Set<string>();

function storageKey(userId: string): string {
  return `whop:complete_registration:${userId}`;
}

function hasAlreadyFired(userId: string): boolean {
  if (firedThisSession.has(userId)) return true;
  try {
    return window.localStorage.getItem(storageKey(userId)) !== null;
  } catch {
    // Private browsing or blocked storage — the in-memory guard still holds
    // for this page, which covers the refresh case that actually matters.
    return false;
  }
}

function markFired(userId: string): void {
  firedThisSession.add(userId);
  try {
    window.localStorage.setItem(storageKey(userId), new Date().toISOString());
  } catch {
    /* nothing more to do — the in-memory guard is the fallback */
  }
}

function getWhop(): WhopGlobal | null {
  if (typeof window === "undefined") return null;
  const whop = window.whop;
  return whop && typeof whop.track === "function" ? whop : null;
}

export interface RegistrationIdentity {
  /** Converana user id (identical to the Supabase auth user id). */
  userId: string;
  email: string;
}

/**
 * Reports a completed registration to Whop: an `identify` so the conversion
 * can be matched to a person, then the `complete_registration` conversion
 * itself.
 *
 * Callers must only invoke this when a genuinely new account was created —
 * never on page load, never on a failed signup, never on login, and never
 * for an email that already had an account. Those checks belong on the
 * server, where the signup result is known; see signUpAction.
 *
 * Returns whether the events were sent. `false` means either they had
 * already been sent for this user, or the pixel wasn't present (blocked by
 * an extension, for instance) — neither is an error worth showing anyone.
 */
export function trackWhopRegistration({ userId, email }: RegistrationIdentity): boolean {
  if (typeof window === "undefined") return false;
  if (!userId) return false;

  const whop = getWhop();
  if (!whop) return false;
  if (hasAlreadyFired(userId)) return false;

  // Marked before sending: a synchronous re-entry (a double-invoked effect)
  // must not slip between the check and the call.
  markFired(userId);

  // No plan, price, currency or payment detail — Whop is not a billing
  // provider here and must never be handed billing data.
  const identity = { email, external_id: userId };
  whop.track(IDENTIFY, identity);
  whop.track(COMPLETE_REGISTRATION, identity);

  return true;
}

/**
 * Same as `trackWhopRegistration`, but waits briefly for the pixel snippet
 * to define `window.whop` first. The snippet loads with `afterInteractive`,
 * so on a slow connection a fast signup could otherwise land before it.
 */
export function trackWhopRegistrationWhenReady(identity: RegistrationIdentity): void {
  if (typeof window === "undefined") return;
  if (trackWhopRegistration(identity)) return;
  // Already reported, or genuinely nothing to report to.
  if (!identity.userId || hasAlreadyFired(identity.userId) || getWhop()) return;

  let waited = 0;
  const timer = window.setInterval(() => {
    waited += READY_POLL_MS;
    if (getWhop()) {
      window.clearInterval(timer);
      trackWhopRegistration(identity);
    } else if (waited >= READY_TIMEOUT_MS) {
      window.clearInterval(timer);
    }
  }, READY_POLL_MS);
}
