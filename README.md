# LeadLoop

**Turn missed leads into booked customers.**

LeadLoop is an AI-powered lead recovery and follow-up platform for local service
businesses (HVAC, plumbing, roofing, electrical, dental, med spa, auto detailing,
cleaning, real estate, and similar). It captures leads, automatically follows up,
qualifies them with AI, flags hot leads, tracks conversations and appointments,
and reports on recovered revenue.

This is a real, working V1 — a Next.js app, Postgres database (via Prisma),
Supabase auth, Anthropic AI, Stripe billing, and Twilio/Resend messaging, all
wired together with server-side authorization and graceful fallbacks when a
service isn't configured.

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
npm run test         # vitest (unit tests, no database required)
npm run build         # production build
npm run db:studio    # Prisma Studio — browse your database
npm run db:seed       # create a demo workspace (needs Supabase configured)
```

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

LeadLoop uses PostgreSQL via Prisma. Any Postgres works (Supabase's built-in
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
   production; LeadLoop handles both the confirmed and unconfirmed sign-up
   paths.

LeadLoop mirrors each Supabase auth user into its own `users` table on first
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
stripe products create --name "LeadLoop Starter"
stripe prices create --product <id> --unit-amount 4900 --currency usd --recurring[interval]=month

stripe products create --name "LeadLoop Growth"
stripe prices create --product <id> --unit-amount 9900 --currency usd --recurring[interval]=month

stripe products create --name "LeadLoop Pro"
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

## 7. Twilio setup (SMS)

1. Create a Twilio account and buy a phone number.
2. Set `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`.

All SMS sends go through `lib/twilio/send-sms.ts`. Without credentials, SMS
follow-ups are skipped with a logged warning instead of failing the request
— set the SMS default follow-up channel to Email until Twilio is configured.
Note: inbound SMS (customers replying by text) isn't wired to a webhook in
V1 — see Known Limitations.

## 8. Resend setup (email)

1. Create a Resend account and verify a sending domain.
2. Set `RESEND_API_KEY` and `RESEND_FROM_EMAIL` (e.g. `LeadLoop <notifications@yourdomain.com>`).

All email sends go through `lib/resend/send-email.ts`, used for lead/appointment
notifications and email follow-ups.

## 9. Deployment

LeadLoop is a standard Next.js app — deploy it anywhere Next.js runs (Vercel,
Fly, Render, a Node server, etc.).

1. Set every environment variable from §2 in your hosting platform.
2. Run `npm run db:migrate` against your production database once (or wire
   it into your deploy pipeline).
3. Point `NEXT_PUBLIC_APP_URL` at your real domain — it's used in emails,
   embed snippets, and Stripe redirect URLs.
4. Configure the Stripe webhook and cron job (below) against the deployed URL.

## 10. Configure the follow-up cron

Automated follow-ups (30 min / 24 hr / 3 day) are processed by
`GET`/`POST /api/cron/follow-ups`, secured with `LEADLOOP_API_SECRET`. Point
any scheduler at it every 5–15 minutes:

```bash
curl -X POST https://yourdomain.com/api/cron/follow-ups \
  -H "Authorization: Bearer $LEADLOOP_API_SECRET"
```

- **Vercel:** add a `vercel.json` cron entry pointing at that URL (or use
  Vercel's built-in Cron Jobs UI) — pass the secret via the `secret` query
  param if you can't set headers: `.../api/cron/follow-ups?secret=...`.
- **Anything else:** GitHub Actions on a schedule, cron-job.org, a system
  crontab with `curl`, etc. — any scheduler that can make an HTTPS request
  works.

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
- Automated follow-up engine (30 min / 24 hr / 3 day, configurable, consent-aware, cron-driven)
- Appointments: list + status workflow (confirm/cancel/complete)
- Analytics: leads over time, funnel, temperature mix, response time, follow-up success rate
- Billing: Stripe Checkout, Customer Portal, webhook-driven subscription state, plan-limit enforcement
- Lead capture API (`/api/leads`) with hashed API keys, plus a public embeddable form endpoint
- Settings: business, AI assistant, follow-up, notifications, integrations, API keys, account
- Demo mode: load/remove clearly-labeled sample data
- Notifications: in-app bell + email, per-event preferences
- Tests: plan limits, AI qualification parsing, lead isolation, API key auth, appointment creation, Stripe webhook mapping, follow-up eligibility

## 13. What needs manual configuration

Nothing in this list is faked — each is a real integration that simply needs
credentials before it's live:

- Supabase project + env vars (auth won't work at all without this)
- A Postgres database + `npm run db:migrate`
- `ANTHROPIC_API_KEY` (AI features fall back to "AI unavailable, reply manually" without it)
- Stripe account, products/prices, and webhook (billing page works but checkout/portal need this)
- Resend account + verified domain (email notifications/follow-ups)
- Twilio account + number (SMS follow-ups)
- A scheduler pointed at `/api/cron/follow-ups` (otherwise follow-ups queue but never send)
- `LEADLOOP_API_SECRET` for the cron endpoint

## 14. Known limitations (V1)

- **No inbound SMS/email webhook.** Customers can't reply by text or email
  yet — conversations continue on the web channel or via the business
  replying manually in the dashboard. Outbound SMS/email sending is fully
  wired.
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

- Inbound SMS (Twilio) and email (Resend) webhooks so customers can reply
  directly, with STOP-keyword opt-out handling wired end-to-end
- Team invitations (email invite → accept → join business)
- Calendar-grid appointment view with drag-to-reschedule
- Saved views/segments for the leads table
- Webhook subscriptions for external systems (Section 66 API design lists this)
- Multi-business switcher for users who manage more than one workspace
- Configurable AI qualification score thresholds from Settings (currently
  centralized in `lib/ai/types.ts` — easy to change, not yet UI-exposed)

---

## Project structure

```
app/              routes (marketing, auth, onboarding, dashboard, API)
components/       ui/, dashboard/, leads/, conversations/, appointments/,
                  analytics/, billing/, settings/, marketing/, auth/, embed/
lib/
  ai/             centralized Anthropic integration
  stripe/         checkout, portal, status mapping
  twilio/         SMS abstraction
  resend/         email abstraction
  auth/           Supabase clients, session/authorization helpers
  db/             Prisma client
  leads/          lead creation pipeline, query builders
  follow-ups/     follow-up scheduling
  api/            shared API helpers (auth, rate limiting, responses)
prisma/           schema, migrations, seed script
tests/            vitest unit tests
```
