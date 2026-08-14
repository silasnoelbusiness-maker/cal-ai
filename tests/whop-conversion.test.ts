import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/**
 * The Whop `complete_registration` conversion.
 *
 * An ad campaign optimizes spend against this event, so a false or repeated
 * conversion costs real money and trains the campaign on a lie. These tests
 * pin both halves of the guarantee: the server only reports a genuinely new
 * account, and the client sends it at most once.
 */

const mockSignUp = vi.fn();
const mockSignInWithPassword = vi.fn();

vi.mock("@/lib/auth/supabase-server", () => ({
  createSupabaseServerClient: async () => ({
    auth: { signUp: mockSignUp, signInWithPassword: mockSignInWithPassword },
  }),
}));
vi.mock("@/lib/auth/config", () => ({ isSupabaseConfigured: true }));

const redirectError = new Error("NEXT_REDIRECT");
vi.mock("next/navigation", () => ({
  redirect: (path: string) => {
    (redirectError as Error & { path?: string }).path = path;
    throw redirectError;
  },
}));

const { signUpAction, loginAction } = await import("@/app/(auth)/actions");
const { trackWhopRegistration } = await import("@/lib/analytics/whop");

function form(fields: Record<string, string>) {
  const data = new FormData();
  for (const [key, value] of Object.entries(fields)) data.set(key, value);
  return data;
}

const NEW_SIGNUP = form({ email: "new@example.com", password: "hunter2hunter2" });

/** Supabase's shape for a brand-new account: one identity row. */
function newUser(id = "user_new") {
  return { id, email: "new@example.com", identities: [{ id: "ident_1" }] };
}

describe("the server decides what counts as a registration", () => {
  beforeEach(() => vi.clearAllMocks());

  it("reports a new account, with the user id and email", async () => {
    mockSignUp.mockResolvedValue({ data: { user: newUser(), session: { access_token: "t" } }, error: null });

    const state = await signUpAction({}, NEW_SIGNUP);

    expect(state.registered).toEqual({ userId: "user_new", email: "new@example.com" });
    expect(state.error).toBeUndefined();
  });

  it("reports a new account that still has to confirm its email", async () => {
    mockSignUp.mockResolvedValue({ data: { user: newUser(), session: null }, error: null });

    const state = await signUpAction({}, NEW_SIGNUP);

    expect(state.registered).toEqual({ userId: "user_new", email: "new@example.com" });
    expect(state.success).toMatch(/check your email/i);
  });

  it("does NOT report an email that already has an account", async () => {
    // Supabase returns an obfuscated user with no identities rather than an
    // error, so that signup can't be used to enumerate accounts.
    mockSignUp.mockResolvedValue({
      data: { user: { id: "obfuscated", identities: [] }, session: null },
      error: null,
    });

    const state = await signUpAction({}, NEW_SIGNUP);

    expect(state.registered).toBeUndefined();
    // The response still has to look identical to a real signup.
    expect(state.success).toMatch(/check your email/i);
  });

  it("does NOT report a failed signup", async () => {
    mockSignUp.mockResolvedValue({ data: { user: null, session: null }, error: { message: "Signup disabled" } });

    const state = await signUpAction({}, NEW_SIGNUP);

    expect(state.registered).toBeUndefined();
    expect(state.error).toBe("Signup disabled");
  });

  it("does NOT report a submission rejected before it reaches Supabase", async () => {
    const badEmail = await signUpAction({}, form({ email: "nope", password: "hunter2hunter2" }));
    expect(badEmail.registered).toBeUndefined();
    expect(mockSignUp).not.toHaveBeenCalled();

    const shortPassword = await signUpAction({}, form({ email: "new@example.com", password: "short" }));
    expect(shortPassword.registered).toBeUndefined();
    expect(mockSignUp).not.toHaveBeenCalled();
  });

  it("does NOT report anything on login, successful or otherwise", async () => {
    mockSignInWithPassword.mockResolvedValue({ error: null });
    await expect(loginAction({}, form({ email: "a@example.com", password: "x" }))).rejects.toThrow(
      "NEXT_REDIRECT"
    );

    mockSignInWithPassword.mockResolvedValue({ error: { message: "bad" } });
    const failed = await loginAction({}, form({ email: "a@example.com", password: "x" }));
    expect(failed.registered).toBeUndefined();
    expect(failed.error).toBe("Incorrect email or password.");
  });

  it("hands navigation to the client so the conversion isn't lost to a redirect", async () => {
    mockSignUp.mockResolvedValue({ data: { user: newUser(), session: { access_token: "t" } }, error: null });

    const state = await signUpAction({}, NEW_SIGNUP);

    expect(state.redirectTo).toBe("/onboarding");
  });
});

describe("the client sends one conversion per account", () => {
  const track = vi.fn();
  let store: Record<string, string>;

  beforeEach(() => {
    track.mockClear();
    store = {};
    vi.stubGlobal("window", {
      whop: { track },
      localStorage: {
        getItem: (k: string) => (k in store ? store[k] : null),
        setItem: (k: string, v: string) => {
          store[k] = v;
        },
      },
      setInterval: vi.fn(),
      clearInterval: vi.fn(),
    });
  });

  afterEach(() => vi.unstubAllGlobals());

  it("sends identify and complete_registration, with email and external_id", () => {
    expect(trackWhopRegistration({ userId: "u1", email: "new@example.com" })).toBe(true);

    expect(track).toHaveBeenCalledTimes(2);
    expect(track).toHaveBeenNthCalledWith(1, "identify", {
      email: "new@example.com",
      external_id: "u1",
    });
    expect(track).toHaveBeenNthCalledWith(2, "complete_registration", {
      email: "new@example.com",
      external_id: "u1",
    });
  });

  it("sends no billing information whatsoever", () => {
    trackWhopRegistration({ userId: "u_billing", email: "new@example.com" });

    const payloads = JSON.stringify(track.mock.calls);
    for (const forbidden of ["plan", "price", "amount", "currency", "stripe", "subscription", "card"]) {
      expect(payloads.toLowerCase()).not.toContain(forbidden);
    }
  });

  it("ignores a repeat call for the same user", () => {
    expect(trackWhopRegistration({ userId: "u2", email: "new@example.com" })).toBe(true);
    expect(trackWhopRegistration({ userId: "u2", email: "new@example.com" })).toBe(false);
    expect(track).toHaveBeenCalledTimes(2);
  });

  it("stays deduplicated across a page reload", () => {
    trackWhopRegistration({ userId: "u3", email: "new@example.com" });
    track.mockClear();

    // A reload clears module state but not localStorage.
    vi.resetModules();
    vi.stubGlobal("window", {
      whop: { track },
      localStorage: { getItem: (k: string) => store[k] ?? null, setItem: () => {} },
    });

    return import("@/lib/analytics/whop").then(({ trackWhopRegistration: fresh }) => {
      expect(fresh({ userId: "u3", email: "new@example.com" })).toBe(false);
      expect(track).not.toHaveBeenCalled();
    });
  });

  it("still counts a different account as a separate registration", () => {
    expect(trackWhopRegistration({ userId: "u4", email: "a@example.com" })).toBe(true);
    expect(trackWhopRegistration({ userId: "u5", email: "b@example.com" })).toBe(true);
    expect(track).toHaveBeenCalledTimes(4);
  });

  it("does nothing without a user id", () => {
    expect(trackWhopRegistration({ userId: "", email: "new@example.com" })).toBe(false);
    expect(track).not.toHaveBeenCalled();
  });

  it("degrades quietly when the pixel is blocked", () => {
    vi.stubGlobal("window", { localStorage: { getItem: () => null, setItem: () => {} } });
    expect(trackWhopRegistration({ userId: "u6", email: "new@example.com" })).toBe(false);
  });

  it("survives storage being unavailable, still guarding within the page", () => {
    vi.stubGlobal("window", {
      whop: { track },
      localStorage: {
        getItem: () => {
          throw new Error("blocked");
        },
        setItem: () => {
          throw new Error("blocked");
        },
      },
    });

    expect(trackWhopRegistration({ userId: "u7", email: "new@example.com" })).toBe(true);
    expect(trackWhopRegistration({ userId: "u7", email: "new@example.com" })).toBe(false);
  });

  it("does nothing when there is no browser at all", () => {
    vi.stubGlobal("window", undefined);
    expect(trackWhopRegistration({ userId: "u8", email: "new@example.com" })).toBe(false);
  });
});
