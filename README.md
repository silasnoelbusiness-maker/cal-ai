# Converana

**Turn missed leads into booked customers.**

Converana is an AI-powered lead recovery and follow-up platform for local service
businesses (HVAC, plumbing, roofing, electrical, dental, med spa, auto detailing,
cleaning, real estate, and similar). It captures leads, automatically follows up,
qualifies them with AI, flags hot leads, tracks conversations and appointments,
and reports on recovered revenue.

This is a real, working V1 — a Next.js app, Postgres database (via Prisma),
Supabase auth, Anthropic AI, Stripe billing, and Twilio/Resend messaging, all
wired together with server-side authorization and graceful fallbacks when a
service isn't configured. Inbound SMS (customers texting a business back) is
fully wired end-to-end with Twilio signature verification; see §7.

---

## 1. Run it locally

```bash
npm install
cp .env.example .env.local   # then fill in the values (see below)
npm run db:migrate           # applies the Prisma schema to your database
npm run dev
```

Open http://localhost:3000. The marketing site works immediately; sign-up,
login, and the dashboard need Supabase configured (see §4).

Other useful scripts:

```bash
npm run typecheck   # tsc --noEmit
npm run lint         # eslint
npm run test         # vitest — 100+ unit/integration tests, no database required
npm run build         # production build
npm run db:studio    # Prisma Studio — browse your database
npm run db:seed       # create a demo workspace (needs Supabase configured)
```

Before deploying, run all four of `typecheck` / `lint` / `test` / `build` and
confirm they're clean — see §17 for the full production checklist.

## 2. Environment variables

Copy `.env.example` to `.env.local` and fill in real values. The app is
designed to **start even when a service is unconfigured** — the affected
feature shows a clear "isn't configured" notice instead of crashing.

| Variable | Required for | Notes |
|---|---|---|
| `DATABASE_URL` | Everything | Postgres connection string |
| `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Auth, dashboard | See §4 |
| `ANTHROPIC_API_KEY` | AI qualification, replies, follow-ups | See §5 |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`, `STRIPE_PRICE_STARTER/GROWTH/PRO` | Billing | See §6 |
| `RESEND_API_KEY`, `RESEND_FROM_EMAIL` | Email notifications/follow-ups | See §8 |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER` | SMS follow-ups | See §7 |
| `LEADLOOP_API_SECRET` | Cron endpoint | Any long random string |
| `NEXT_PUBLIC_APP_URL` | Emails, embed snippets, Stripe redirects | e.g. `http://localhost:3000` in dev |
| `DEMO_USER_EMAIL`, `DEMO_USER_PASSWORD` | `npm run db:seed` only | Not used at runtime |

## 3. Database setup

Converana uses PostgreSQL via Prisma. Any Postgres works (Supabase's built-in
Postgres is the easiest since you need a Supabase project anyway for auth).

```bash
# Point DATABASE_URL at your database, then:
npm run db:migrate     # applies prisma/migrations
npm run db:generate     # regenerates the Prisma client (also runs on install)
```

The schema (see `prisma/schema.prisma`) covers businesses, leads, conversations,
messages, appointments, follow-ups, subscriptions, usage, API keys, and
notifications, with indexes on the columns leads/conversations are filtered
and sorted by.

## 4. Supabase setup (authentication)

1. Create a project at https://supabase.com.
2. Project Settings → API: copy the **Project URL** → `NEXT_PUBLIC_SUPABASE_URL`,
   the **anon public** key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and the
   **service_role** key → `SUPABASE_SERVICE_ROLE_KEY` (server-only, never
   exposed to the browser).
3. Project Settings → Database: copy the connection string → `DATABASE_URL`
   (use the "Transaction" pooler connection string if deploying serverless).
4. Authentication → URL Configuration: set the Site URL to your
   `NEXT_PUBLIC_APP_URL`, and add `{NEXT_PUBLIC_APP_URL}/auth/callback` as a
   Redirect URL (needed for email confirmation and password reset links).
5. Authentication → Providers → Email: leave "Confirm email" on for
   production; Converana handles both the confirmed and unconfirmed sign-up
   paths.

Converana mirrors each Supabase auth user into its own `users` table on first
sign-in, and links users to businesses via `business_members` — a user never
sees another business's data, enforced server-side on every query.

## 5. Anthropic API setup (AI)

1. Get an API key at https://console.anthropic.com.
2. Set `ANTHROPIC_API_KEY`.
3. (Optional) set `ANTHROPIC_MODEL` to pin a specific model; defaults to
   `claude-sonnet-5`.

All AI calls are centralized in `lib/ai/` (qualification, follow-ups,
summaries, replies) — nothing calls the Anthropic SDK directly from a route
or component. If the key is missing or a call fails, features degrade to a
manual-only experience with a visible notice rather than breaking the page.

## 6. Stripe setup (billing)

1. Create a Stripe account (test mode is fine for development).
2. Developers → API keys: copy the secret key → `STRIPE_SECRET_KEY`, and the
   publishable key → `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`.

### 6a. Create the products/prices

In the Stripe Dashboard → Product catalog, create three recurring monthly
products/prices (or via CLI):

```bash
stripe products create --name "Converana Starter"
stripe prices create --product <id> --unit-amount 4900 --currency usd --recurring[interval]=month

stripe products create --name "Converana Growth"
stripe prices create --product <id> --unit-amount 9900 --currency usd --recurring[interval]=month

stripe products create --name "Converana Pro"
stripe prices create --product <id> --unit-amount 19900 --currency usd --recurring[interval]=month
```

Set the resulting price IDs as `STRIPE_PRICE_STARTER`, `STRIPE_PRICE_GROWTH`,
`STRIPE_PRICE_PRO`.

### 6b. Configure the webhook

```bash
# Local development:
stripe listen --forward-to localhost:3000/api/stripe/webhook
# copy the printed whsec_... into STRIPE_WEBHOOK_SECRET

# Production: Developers → Webhooks → Add endpoint
#   URL: https://yourdomain.com/api/stripe/webhook
#   Events: checkout.session.completed, customer.subscription.created,
#           customer.subscription.updated, customer.subscription.deleted,
#           invoice.payment_failed
```

The webhook (`app/api/stripe/webhook/route.ts`) is the **only** place
subscription state is written — checkout redirects and client state are
never trusted.

## 7. Twilio setup (SMS — inbound and outbound)

1. Create a Twilio account and buy a phone number.
2. Set `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER` (this
   is the platform-wide fallback "from" number for outbound sends).
3. In the Twilio Console, open your number → **Messaging** → "A message
   comes in" → set to **Webhook**, **HTTP POST**, and paste:

   ```
   https://yourdomain.com/api/webhooks/twilio/sms
   ```

That's the entire flow this webhook drives:

```
Customer texts the number
  → Twilio POSTs to /api/webhooks/twilio/sms
  → X-Twilio-Signature is verified against TWILIO_AUTH_TOKEN (rejected with
    403 if missing/invalid — see lib/api/timing-safe-equal.ts usage in that
    route for the constant-time comparison)
  → STOP/START/UNSUBSCRIBE/CANCEL/END/QUIT opts the lead out (and
    START/YES/UNSTOP opts back in) before anything else runs
  → the lead is matched by Business.twilioPhoneNumber (the number that
    received the text) and then by the sender's phone number against an
    existing lead; a genuinely new number creates a new lead
  → the message is appended to the conversation, the business is notified,
    and — if AI is enabled and configured — the AI generates and sends a
    reply in the same request
  → a TwiML response is returned to Twilio (empty unless a STOP/START
    confirmation needs to be spoken back)
```

**Multi-tenant routing:** with more than one business on a shared platform
number, Twilio has no way to know which business a text is *for* — so
per-business inbound routing needs a **dedicated number per business**, set
in **Settings → Integrations → SMS (Twilio)** (stored as
`Business.twilioPhoneNumber`). Point that number's webhook at the same URL
above. Without a dedicated number, a business can still *send* SMS (via the
shared `TWILIO_PHONE_NUMBER`) but can't *receive* replies — the settings
page explains this inline.

All SMS sends go through `lib/twilio/send-sms.ts`, which never throws: without
credentials, sends are skipped with a logged warning instead of failing the
request — set the default follow-up channel to Email until Twilio is
configured.

## 8. Resend setup (email — outbound only)

1. Create a Resend account and verify a sending domain.
2. Set `RESEND_API_KEY` and `RESEND_FROM_EMAIL` (e.g. `Converana <notifications@yourdomain.com>`).

All email sends go through `lib/resend/send-email.ts` (never throws — a
missing key or a Resend-side failure just skips the send with a logged
reason), used for lead/appointment notifications and email follow-ups.

**Inbound email is not supported in V1 — this is not wired up, and nothing
in the product claims otherwise.** If a customer replies to a Converana email,
that reply lands in the business's own inbox and Converana never sees it; it
is not added to the conversation and does not trigger AI processing. This is
a materially bigger integration than inbound SMS: Resend has no built-in
inbound-parse webhook (unlike e.g. SendGrid's Inbound Parse), so supporting
it would mean either standing up your own MX records + mail receiver for a
subdomain and parsing raw MIME, or switching/adding a provider that offers
inbound email parsing, then matching the reply back to a lead (most
naturally via a `reply+{leadId}@yourdomain.com` convention) and verifying
the sender to prevent spoofed inbound "replies." None of that exists yet.
Until then, email follow-ups are effectively one-way: the business can see
and respond to email replies manually in their own mail client, but that
reply won't appear in the Converana conversation thread the way an inbound
SMS reply does.

## 9. Deployment

Converana is a standard Next.js app — deploy it anywhere Next.js runs (Vercel,
Fly, Render, a Node server, etc.).

1. Set every environment variable from §2 in your hosting platform.
2. Run `npm run db:migrate` against your production database once (or wire
   it into your deploy pipeline).
3. Point `NEXT_PUBLIC_APP_URL` at your real domain — it's used in emails,
   embed snippets, and Stripe redirect URLs. Note that `NEXT_PUBLIC_*`
   variables are inlined at **build** time, so it must be set before the
   first build, and changing it later needs a redeploy (not just a restart).
4. Configure the webhooks and scheduler below against the deployed URL.

`vercel.json` pins serverless functions to `dub1` (Dublin) to sit next to a
Supabase project in `eu-west-1`. If your database lives elsewhere, change
`regions` to the Vercel region closest to it — every request makes several
sequential database round-trips, so co-locating matters more than it looks.

### Webhook URLs (quick reference)

| Service | URL to configure | Where |
|---|---|---|
| Stripe | `https://yourdomain.com/api/stripe/webhook` | Stripe Dashboard → Developers → Webhooks (see §6b for the exact events) |
| Twilio | `https://yourdomain.com/api/webhooks/twilio/sms` | Twilio Console → your number → Messaging → "A message comes in" (see §7) — repeat per dedicated business number |

Both are signature-verified server-side (`stripe.webhooks.constructEvent` /
`twilio.validateRequest`) — requests without a valid signature are rejected
before anything is written.

## 10. Configure the follow-up cron

Automated follow-ups (30 min / 24 hr / 3 day) are processed by
`GET`/`POST /api/cron/follow-ups`, secured with `LEADLOOP_API_SECRET`. Point
any scheduler at it every 5–15 minutes:

```bash
curl -X POST https://yourdomain.com/api/cron/follow-ups \
  -H "Authorization: Bearer $LEADLOOP_API_SECRET"
```

- **Vercel Hobby:** Hobby plans only allow *daily* cron jobs, so `vercel.json`
  intentionally contains **no** `crons` block — including one would make the
  deployment itself fail. Use an external scheduler instead (below). A daily
  cron would leave the 30-minute follow-up up to 24 hours late anyway, which
  defeats the feature.
- **Vercel Pro/Enterprise:** you can add a `crons` entry to `vercel.json`
  (e.g. `{"path": "/api/cron/follow-ups", "schedule": "*/15 * * * *"}`).
  Vercel Cron cannot send custom headers — it sends
  `Authorization: Bearer $CRON_SECRET`, which this route already accepts, so
  set `CRON_SECRET` to the same value as `LEADLOOP_API_SECRET`.
- **External scheduler (works on any plan):** GitHub Actions on a schedule,
  cron-job.org, a system crontab with `curl`, etc. Prefer the
  `Authorization` header over the `?secret=` query param — query strings get
  written to proxy, CDN, and access logs.

## 11. Connect a business's website

Once logged in, go to **Settings → Integrations**:

- **Embeddable form:** copy the `<iframe>` snippet and paste it into the
  business's website HTML — no code changes needed on their end. It posts to
  a public, rate-limited endpoint that creates a lead, triggers the AI first
  response and qualification, and notifies the business.
- **API:** create an API key in **Settings → API Keys**, then `POST` to
  `/api/leads` with `Authorization: Bearer <key>` from any form, CRM, or ad
  platform (see the curl example on that page).

## 12. Full V1 feature list

- Marketing site: home, pricing, terms, privacy, SEO metadata, sitemap, robots.txt
- Email/password auth (Supabase): sign-up, login, logout, password reset, protected routes
- 8-step onboarding with optional demo data
- Dashboard: revenue-first metrics, pipeline, recent activity, AI activity, upcoming appointments
- Leads: filterable/sortable/searchable table, pagination, manual creation, detail page with timeline
- AI: structured lead qualification (score/temperature/intent/urgency/etc.), lead summaries, AI first response, "Suggest AI Reply", human hand-off detection
- Conversations: split list/detail UI, manual reply, AI-generated indicator, mobile-responsive
- Inbound SMS: Twilio webhook with signature verification, STOP/START opt-out handling, lead matching by business number then phone number, AI auto-reply
- Automated follow-up engine (30 min / 24 hr / 3 day, configurable, consent-aware, cron-driven)
- Appointments: list + status workflow (confirm/cancel/complete)
- Analytics: leads over time, funnel, temperature mix, response time, follow-up success rate — always scoped to real (non-demo) leads only
- Billing: Stripe Checkout, Customer Portal, webhook-driven subscription state, plan-limit enforcement
- Lead capture API (`/api/leads`) with hashed API keys, plus a public embeddable form endpoint
- Settings: business, AI assistant, follow-up, notifications, integrations (embed snippet, SMS number/webhook, lead capture API), API keys, account
- Demo mode: load/remove clearly-labeled sample data, kept out of revenue/analytics and rolled back cleanly from plan usage on removal
- Notifications: in-app bell + email, per-event preferences
- Error boundaries at the dashboard, app, and root-layout levels — a database or other unhandled failure shows a styled "something went wrong" page with a retry action instead of crashing
- Tests: 100+ unit/integration tests covering plan limits, AI qualification parsing, lead/conversation isolation, API key auth, appointment creation, Stripe checkout + webhook mapping, follow-up eligibility, inbound SMS signature verification, demo-data integrity, and constant-time secret comparison

## 13. What needs manual configuration

Nothing in this list is faked — each is a real integration that simply needs
credentials before it's live:

- Supabase project + env vars (auth won't work at all without this)
- A Postgres database + `npm run db:migrate`
- `ANTHROPIC_API_KEY` (AI features fall back to "AI unavailable, reply manually" without it)
- Stripe account, products/prices, and webhook (billing page works but checkout/portal need this)
- Resend account + verified domain (email notifications/follow-ups — outbound only, see §8)
- Twilio account + number, with its webhook pointed at `/api/webhooks/twilio/sms` (outbound SMS follow-ups AND inbound replies both need this)
- A scheduler pointed at `/api/cron/follow-ups` (otherwise follow-ups queue but never send)
- `LEADLOOP_API_SECRET` for the cron endpoint

## 14. Known limitations (V1)

- **No inbound email.** Customers can't reply to a Converana email and have it
  land back in the conversation — see §8 for exactly why and what a fix
  would require. Inbound SMS *is* fully wired (§7); outbound email/SMS
  sending is fully wired either way.
- **Single business per account** in the UI (the schema supports multiple
  via `business_members`, but onboarding creates one).
- **No team invite flow yet** — the Account page shows current members, but
  there's no invite-by-email UI. Existing members are shown against the
  plan's seat limit.
- **In-memory rate limiting.** Fine for a single instance; use a shared
  store (e.g. Redis) behind a multi-instance deployment.
- **Appointments are a list/agenda view**, not a full calendar grid.
- Demo/AI-generated content in this README/product is illustrative — always
  review AI-configured business settings before going live.

## 15. Suggested V1.1 roadmap

- Inbound email (a provider with inbound-parse support, or your own MX +
  mail receiver) so email replies land back in the conversation the way
  inbound SMS already does — see §8 for what this actually involves
- Team invitations (email invite → accept → join business)
- Calendar-grid appointment view with drag-to-reschedule
- Saved views/segments for the leads table
- Webhook subscriptions for external systems (Section 66 API design lists this)
- Multi-business switcher for users who manage more than one workspace
- Configurable AI qualification score thresholds from Settings (currently
  centralized in `lib/ai/types.ts` — easy to change, not yet UI-exposed)

## 16. Production-readiness audit notes

This V1 went through a full production-readiness audit (auth/authorization,
database integrity, AI behavior, the end-to-end lead flow, the follow-up
engine, SMS, email, the embeddable form, Stripe billing, API keys, security,
UX, demo-mode data integrity, error handling, mobile layout, and the
production build) before launch. Real bugs found during that audit —
cross-tenant data leaks, billing double-subscription/limit-bypass edge
cases, a Decimal-serialization crash, a mobile layout overflow, demo data
contaminating real revenue figures, and missing error boundaries, among
others — were fixed and covered with tests, not just noted. Nothing above
in §12–15 is aspirational marketing copy: every "supported" feature was
exercised against a real database and, where applicable, a real running
server during that audit.

## 17. Production checklist

Run through this before pointing real customers at a deployment:

- [ ] `npm run typecheck`, `npm run lint`, `npm run test`, and `npm run build`
      all pass cleanly (see §1)
- [ ] Every environment variable in §2 is set in your hosting platform (not
      just `.env.local`)
- [ ] `npm run db:migrate` has been run against the production database
- [ ] Supabase: Site URL and `{APP_URL}/auth/callback` redirect URL are set
      to your real production domain, not localhost (§4)
- [ ] Stripe: live-mode keys and price IDs (not test-mode), webhook
      configured at `/api/stripe/webhook` with the events listed in §6b, and
      `STRIPE_WEBHOOK_SECRET` matches that endpoint specifically (§6b)
- [ ] Twilio: number's inbound webhook points at `/api/webhooks/twilio/sms`
      over HTTPS (Twilio signature verification will reject everything
      otherwise) — repeat for every business's dedicated number (§7)
- [ ] Resend: sending domain is verified (SPF/DKIM), not just an API key (§8)
- [ ] A scheduler is actually hitting `/api/cron/follow-ups` on an interval
      — not just configured, but confirmed firing (check `FollowUp` rows
      transition from `PENDING` to `SENT`) (§10)
- [ ] `NEXT_PUBLIC_APP_URL` is the real production URL — it's baked into
      email links, embed snippets, and Stripe redirect URLs
- [ ] `LEADLOOP_API_SECRET` is a long random value, not the sample from
      `.env.example`
- [ ] Sign up as a brand-new business end-to-end in production once: create
      a test lead, confirm the AI response, book an appointment, and check
      the analytics/billing pages before inviting real customers

---

## Project structure

```
app/              routes (marketing, auth, onboarding, dashboard, API)
  error.tsx             error boundary for everything outside /dashboard
  global-error.tsx      last-resort boundary for a root-layout failure
  dashboard/error.tsx   error boundary for all dashboard pages
  api/webhooks/twilio/sms/route.ts   inbound SMS webhook (signature-verified)
  api/stripe/webhook/route.ts        Stripe webhook (signature-verified)
components/       ui/, dashboard/, leads/, conversations/, appointments/,
                  analytics/, billing/, settings/, marketing/, auth/, embed/
lib/
  ai/             centralized Anthropic integration
  stripe/         checkout, portal, status mapping
  twilio/         SMS abstraction (outbound) + inbound webhook logic
  resend/         email abstraction (outbound only — see §8)
  auth/           Supabase clients, session/authorization helpers
  db/             Prisma client
  leads/          lead creation pipeline, query builders
  follow-ups/     follow-up scheduling
  api/            shared API helpers (auth, rate limiting, responses, timing-safe compare)
  demo.ts         demo/sample data load + clean removal (revenue/usage-safe)
prisma/           schema, migrations, seed script
tests/            vitest unit + integration tests (100+)
```
