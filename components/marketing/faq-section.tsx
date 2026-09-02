import Link from "next/link";
import { ChevronDown } from "lucide-react";

/**
 * FAQ.
 *
 * Built on native <details>/<summary>, which is keyboard operable, screen
 * reader announced and correctly expanded/collapsed with no JavaScript and no
 * ARIA of our own to get wrong. A hand-rolled accordion would be more code
 * and less accessible.
 *
 * Every answer is checked against the implementation — see
 * lib/marketing/product-facts.ts for the claims register. Nothing here
 * promises a capability the product doesn't have; where the honest answer is
 * "no", it says no.
 */

interface Faq {
  q: string;
  a: React.ReactNode;
}

const FAQS: Faq[] = [
  {
    q: "What is Converana?",
    a: (
      <>
        Software that answers your leads when you can&apos;t. It replies to a new enquiry straight
        away, asks the questions you&apos;d ask, works out how serious and how urgent the job is,
        keeps following up if they go quiet, and tells you when someone is ready to book.
      </>
    ),
  },
  {
    q: "Who is it built for?",
    a: (
      <>
        Home-service businesses — HVAC, plumbing, roofing, electrical, cleaning and similar trades
        — where the owner is on a job when the lead comes in and the first company to reply usually
        wins the work.
      </>
    ),
  },
  {
    q: "How does Converana receive my leads?",
    a: (
      <>
        Five ways: an embeddable form for your website, a lead capture API for your own pages and
        tools, a CSV import for the list you already have, an inbound text if you connect your own
        Twilio number, and typing one in by hand. There&apos;s no one-click Facebook or Google Ads
        connector yet — leads from ad platforms come in through the API or a CSV export.
      </>
    ),
  },
  {
    q: "How does the AI talk to my leads?",
    a: (
      <>
        By email and in a web conversation on your site, and by two-way SMS if you connect your own
        Twilio account. It does not make phone calls.
      </>
    ),
  },
  {
    q: "Will the AI invent prices or make promises for me?",
    a: (
      <>
        No — and this is enforced in the instructions it follows on every message, not left to
        chance. If you haven&apos;t given it pricing, it says the price depends on the job and that
        someone will follow up. It won&apos;t commit to an appointment time you haven&apos;t
        confirmed, and if a customer asks whether they&apos;re talking to a person, it says
        it&apos;s an AI assistant for your business.
      </>
    ),
  },
  {
    q: "What happens when a conversation needs a human?",
    a: (
      <>
        It stops trying to handle it. Emergencies, complaints, refunds, anger, legal threats or
        anyone simply asking for a person all get acknowledged, handed over, and flagged to you
        with a notification. You can take over any conversation yourself at any point.
      </>
    ),
  },
  {
    q: "Can I import a lead list I already have?",
    a: (
      <>
        Yes. Upload a CSV, match your columns, and review what we found before anything is
        imported — duplicates against your existing leads are skipped automatically. Imported leads
        are stored only: Converana will not message them until you decide to.
      </>
    ),
  },
  {
    q: "Does Converana book appointments automatically?",
    a: (
      <>
        No. It qualifies the lead and tells you when someone is ready — you confirm the time. We
        made that deliberate: a bot committing your calendar is how a business ends up double-booked
        two towns apart.
      </>
    ),
  },
  {
    q: "What happens when I reach my plan limit?",
    a: (
      <>
        Two different things. Once you hit your monthly <strong>lead</strong> allowance, new leads
        are declined and the response says so rather than failing quietly. If you run out of{" "}
        <strong>AI messages</strong>, leads are still captured and saved — you just stop getting
        automatic replies until the next month or an upgrade. Upgrading takes effect immediately.
      </>
    ),
  },
  {
    q: "Can I cancel at any time?",
    a: (
      <>
        Yes. Plans are monthly with no contract, and you can cancel or change plan from the billing
        page. If you move to a smaller plan, you keep the plan you paid for until the end of the
        billing period you&apos;ve already paid for, then it switches over.
      </>
    ),
  },
  {
    q: "Do I need a credit card to start?",
    a: (
      <>
        No. You can create your account, set up your business and connect a lead source without
        entering payment details. There&apos;s no time-limited trial counting down in the
        background — you pick a plan when you&apos;re ready to go live.
      </>
    ),
  },
  {
    q: "How is my customer information protected?",
    a: (
      <>
        Every query is scoped to your business on the server, so one account can never read
        another&apos;s leads or conversations, and that isolation is enforced at the database level
        too. API keys are stored hashed, and traffic is encrypted in transit. Full detail is in our{" "}
        <Link href="/privacy" className="text-brand underline underline-offset-2 hover:no-underline">
          Privacy Policy
        </Link>
        .
      </>
    ),
  },
];

export function FaqSection() {
  return (
    <section id="faq" className="scroll-mt-20 border-t border-border bg-surface py-20 sm:py-24">
      <div className="mx-auto max-w-3xl px-4 sm:px-6">
        <div className="text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            Questions worth asking
          </h2>
          <p className="mt-4 text-lg text-muted">
            Including the ones where the answer is no.
          </p>
        </div>

        <div className="mt-12 divide-y divide-border border-y border-border">
          {FAQS.map((faq) => (
            <details key={faq.q} className="group py-4">
              <summary className="flex cursor-pointer list-none items-start justify-between gap-4 rounded-md text-left font-medium text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 [&::-webkit-details-marker]:hidden">
                <span>{faq.q}</span>
                <ChevronDown
                  className="mt-0.5 h-4 w-4 shrink-0 text-muted transition-transform group-open:rotate-180"
                  aria-hidden
                />
              </summary>
              <div className="mt-3 pr-8 text-sm leading-relaxed text-muted">{faq.a}</div>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}

/** The same questions and answers as plain text, for JSON-LD. */
export const FAQ_PLAIN: { question: string; answer: string }[] = [
  {
    question: "What is Converana?",
    answer:
      "Software that answers your leads when you can't. It replies to a new enquiry straight away, asks qualifying questions, works out how urgent the job is, follows up if they go quiet, and tells you when someone is ready to book.",
  },
  {
    question: "Who is it built for?",
    answer:
      "Home-service businesses — HVAC, plumbing, roofing, electrical, cleaning and similar trades — where the owner is on a job when the lead comes in.",
  },
  {
    question: "How does Converana receive my leads?",
    answer:
      "An embeddable website form, a lead capture API, CSV import, inbound SMS through your own Twilio number, or adding a lead by hand. There is no one-click Facebook or Google Ads connector yet.",
  },
  {
    question: "How does the AI talk to my leads?",
    answer:
      "By email and web conversation, and by two-way SMS if you connect your own Twilio account. It does not make phone calls.",
  },
  {
    question: "Will the AI invent prices or make promises?",
    answer:
      "No. It is instructed never to invent a price, never to promise an appointment time you haven't confirmed, and never to claim to be a human.",
  },
  {
    question: "Does Converana book appointments automatically?",
    answer:
      "No. It qualifies the lead and notifies you when someone is ready to book; you confirm the time.",
  },
  {
    question: "What happens when I reach my plan limit?",
    answer:
      "New leads are declined once you reach your monthly lead allowance. If you run out of AI messages, leads are still captured but automatic replies stop until the next month or an upgrade.",
  },
  {
    question: "Do I need a credit card to start?",
    answer:
      "No. You can create an account and set up your business without payment details. There is no time-limited trial; you choose a plan when you are ready.",
  },
];
