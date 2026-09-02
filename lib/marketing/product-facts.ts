/**
 * Every factual claim the marketing site makes about Converana, in one place,
 * each one traced to the code that implements it.
 *
 * The rule this file exists to enforce: the website may only describe
 * behaviour that actually ships. Marketing copy drifts from reality quietly —
 * a feature gets cut, a channel never gets built, and the landing page keeps
 * promising it for months. Keeping the claims here, with a `source` pointing
 * at the implementing file, makes that drift reviewable in a diff and
 * testable in CI (see tests/marketing-claims.test.ts).
 *
 * If you add a claim here, add the file that makes it true. If you can't name
 * one, the claim doesn't belong on the site.
 */

export interface Claim {
  /** Short label shown in the UI. */
  title: string;
  /** Plain-business-language explanation. No jargon, no hedging. */
  body: string;
  /** The file(s) implementing this. Never empty. */
  source: string[];
}

/** How a lead can get into Converana today. */
export interface LeadSource extends Claim {
  /**
   * "native"   — built in, works with no third-party service
   * "byo"      — works, but the customer supplies an outside account (Twilio)
   * "indirect" — reachable through the API/CSV, not a one-click integration
   */
  kind: "native" | "byo" | "indirect";
}

export const LEAD_SOURCES: LeadSource[] = [
  {
    kind: "native",
    title: "Embeddable lead form",
    body: "Drop one line of HTML on your website and every enquiry lands in Converana. Nothing else to install.",
    source: ["app/embed/[businessId]/page.tsx", "app/dashboard/settings/integrations/page.tsx"],
  },
  {
    kind: "native",
    title: "CSV import",
    body: "Upload a spreadsheet from your old CRM. Map your columns, review what we found, and import — duplicates are skipped automatically.",
    source: ["lib/leads/import/run.ts", "components/leads/import-leads-dialog.tsx"],
  },
  {
    kind: "native",
    title: "Lead capture API",
    body: "Post leads from your own site, landing pages, or internal tools using an API key you generate in settings.",
    source: ["app/api/public/leads/[businessId]/route.ts", "app/api/leads/route.ts"],
  },
  {
    kind: "byo",
    title: "Inbound SMS",
    body: "Connect your own Twilio number and a text from a customer starts a conversation and creates the lead automatically.",
    source: ["app/api/webhooks/twilio/sms/route.ts"],
  },
  {
    kind: "native",
    title: "Add by hand",
    body: "Type in a lead you took over the phone. It gets the same follow-up and qualification as everything else.",
    source: ["components/leads/new-lead-dialog.tsx", "lib/leads/create-lead.ts"],
  },
];

/** How Converana can talk to a lead. Voice is deliberately absent. */
export interface Channel extends Claim {
  status: "available" | "byo";
}

export const CHANNELS: Channel[] = [
  {
    status: "available",
    title: "Email",
    body: "Automatic replies and follow-ups sent from your business. Requires an email sending key on your deployment.",
    source: ["lib/resend/send-email.ts", "app/api/cron/follow-ups/route.ts"],
  },
  {
    status: "byo",
    title: "SMS",
    body: "Two-way texting through your own Twilio account. Replies come back into the same conversation, and STOP opts the customer out automatically.",
    source: ["lib/twilio/send-sms.ts", "app/api/webhooks/twilio/sms/route.ts"],
  },
  {
    status: "available",
    title: "Web conversation",
    body: "Leads that arrive through your website form get an AI reply in a conversation thread your team can read and take over at any time.",
    source: ["app/dashboard/conversations", "lib/ai/reply.ts"],
  },
];

/**
 * The six questions the site answers plainly. Every answer below is checked
 * against the implementation named in `source`.
 */
export const PRODUCT_ANSWERS: Claim[] = [
  {
    title: "How quickly does Converana respond?",
    body: "Straight away. A new lead gets an AI reply as soon as it arrives, before anyone on your team has to look at it. You can turn the immediate reply off in settings if you'd rather answer first.",
    source: ["lib/leads/create-lead.ts", "app/dashboard/settings/follow-up"],
  },
  {
    title: "Which channels does it use?",
    body: "Email and web conversations out of the box, plus two-way SMS if you connect your own Twilio number. Converana does not make phone calls.",
    source: ["lib/resend/send-email.ts", "lib/twilio/send-sms.ts"],
  },
  {
    title: "What does the AI actually ask?",
    body: "One useful question at a time, based on the services and details you configure — what the job involves, where it is, how urgent it is, and when they're free. It works from your business information, not a generic script.",
    source: ["lib/ai/prompt.ts", "app/dashboard/settings/ai"],
  },
  {
    title: "What happens when a lead needs a person?",
    body: "The AI stops trying to handle it and tells the customer a team member will follow up. Emergencies, complaints, refunds, anger, legal threats, or anyone simply asking for a human all trigger this, and you get a notification.",
    source: ["lib/ai/prompt.ts", "lib/ai/qualify.ts", "lib/notifications.ts"],
  },
  {
    title: "Does it book appointments by itself?",
    body: "No. Converana qualifies the lead and tells you when someone is ready to book — you or your team confirm the time. The AI is explicitly instructed never to promise a slot that hasn't been confirmed.",
    source: ["lib/ai/prompt.ts", "app/dashboard/appointments"],
  },
  {
    title: "How do I bring in the leads I already have?",
    body: "Import a CSV from your current CRM or spreadsheet. Imported leads are stored only — Converana will not message them until you say so.",
    source: ["lib/leads/import/run.ts"],
  },
];

/**
 * What the AI is forbidden from doing. These are real system-prompt rules,
 * quoted from lib/ai/prompt.ts, and they are the most credible thing the site
 * can say — they're checkable limitations rather than promises.
 */
export const AI_GUARDRAILS: Claim[] = [
  {
    title: "It never invents a price",
    body: "If you haven't given Converana pricing information, it says the price depends on the job and a team member will follow up. It will not guess a number.",
    source: ["lib/ai/prompt.ts"],
  },
  {
    title: "It never pretends to be a person",
    body: "Asked directly, it says it's an AI assistant for your business. No fake names, no pretending.",
    source: ["lib/ai/prompt.ts"],
  },
  {
    title: "It never promises a time you haven't confirmed",
    body: "Scheduling stays with your team. The AI can say you'll follow up; it cannot commit your calendar.",
    source: ["lib/ai/prompt.ts"],
  },
  {
    title: "It hands over instead of guessing",
    body: "Anything urgent, angry, or outside the information you've given gets escalated to a human rather than improvised.",
    source: ["lib/ai/prompt.ts", "lib/ai/qualify.ts"],
  },
];

/**
 * What "Start Free" actually means on this deployment.
 *
 * Checked against lib/stripe/checkout.ts: there is NO trial_period_days
 * anywhere in the Checkout Session, so there is no time-limited trial to
 * advertise. Signup collects no payment details at all — see
 * app/(auth)/actions.ts, which only calls supabase.auth.signUp.
 */
export const START_FREE = {
  headline: "No credit card required",
  detail:
    "Create your account, set up your business, and connect a lead source without entering payment details. There's no time-limited trial to keep track of — you choose a plan when you're ready to go live.",
  source: ["app/(auth)/actions.ts", "lib/stripe/checkout.ts"],
} as const;

/**
 * What happens at a plan's monthly ceiling. Both behaviours are implemented,
 * so both can be stated plainly.
 */
export const PLAN_LIMIT_BEHAVIOUR = {
  leads:
    "New leads are declined once you hit your monthly lead allowance, and the response says so rather than failing silently. Upgrading raises the ceiling immediately.",
  aiMessages:
    "If you run out of AI messages, leads are still captured and stored — you just stop getting automatic replies until the next month or an upgrade.",
  source: ["lib/plans.ts", "lib/leads/create-lead.ts"],
} as const;
