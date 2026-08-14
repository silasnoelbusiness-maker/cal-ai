import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Converana collects, uses, and protects data.",
};

const EFFECTIVE_DATE = "January 1, 2026";

export default function PrivacyPage() {
  return (
    <div className="mx-auto max-w-3xl px-4 py-16 sm:px-6 sm:py-24">
      <h1 className="text-3xl font-semibold tracking-tight text-foreground">Privacy Policy</h1>
      <p className="mt-2 text-sm text-muted">Effective {EFFECTIVE_DATE}</p>

      <div className="prose-sm mt-10 space-y-6 text-sm leading-relaxed text-foreground [&_h2]:mt-8 [&_h2]:text-base [&_h2]:font-semibold [&_p]:text-muted [&_li]:text-muted">
        <p className="text-muted">
          This Privacy Policy explains what information Converana collects, how it is used, and
          the choices available to you. Converana is software used by businesses to manage their
          own customers&apos; contact information — businesses are the data controller for the
          lead data they store in Converana, and are responsible for how they collect and use it.
        </p>

        <section>
          <h2>1. Information we collect</h2>
          <ul className="list-disc space-y-1 pl-5">
            <li>Account information: name, email, and authentication details.</li>
            <li>
              Business information you provide: business name, services, service area, hours, and
              AI assistant configuration.
            </li>
            <li>
              Lead data your business collects: names, contact details, messages, and
              conversation history submitted through your lead sources (embed form, API, or
              manual entry).
            </li>
            <li>Billing information, processed directly by our payment processor (Stripe).</li>
            <li>Usage data (e.g., feature usage, log data) used to operate and improve the Service.</li>
          </ul>
        </section>

        <section>
          <h2>2. How we use information</h2>
          <p>
            We use information to provide the Service (storing leads, generating AI qualification
            and replies, sending follow-ups you configure, processing billing), to secure
            accounts, and to communicate with you about your account.
          </p>
        </section>

        <section>
          <h2>3. AI processing</h2>
          <p>
            Lead conversations may be sent to our AI provider (Anthropic) to generate
            qualification summaries and suggested replies. We do not sell lead data to third
            parties.
          </p>
        </section>

        <section>
          <h2>4. Third-party services</h2>
          <p>
            Converana relies on service providers to operate: Supabase (authentication and
            database hosting), Anthropic (AI), Stripe (billing), Resend (email delivery), and
            Twilio (SMS delivery), each of which processes data solely to provide their respective
            service to Converana.
          </p>
          <p>
            We also use Whop for advertising measurement. Whop receives page views on our public
            marketing and sign-up pages, and — when you create an account — your email address and
            account identifier, so we can tell which advertising brought you to Converana. Whop is
            not involved in billing, and receives no payment, plan or subscription information. It
            does not receive anything from inside your dashboard, and it receives nothing at all
            about the leads or customers you store in Converana.
          </p>
        </section>

        <section>
          <h2>5. Data isolation and security</h2>
          <p>
            Each business account&apos;s data is isolated at the database and application layer.
            We use encryption in transit, hashed API keys, and server-side authorization checks so
            that a business can never access another business&apos;s leads, conversations, or
            settings.
          </p>
        </section>

        <section>
          <h2>6. SMS and email consent</h2>
          <p>
            Converana provides consent and opt-out fields for leads so businesses can track and
            honor communication preferences, including STOP requests for SMS. Businesses are
            responsible for obtaining appropriate consent before contacting a lead, consistent
            with applicable law.
          </p>
        </section>

        <section>
          <h2>7. Data retention and deletion</h2>
          <p>
            We retain account and lead data for as long as an account is active. You can request
            deletion of your account and associated data by contacting us.
          </p>
        </section>

        <section>
          <h2>8. Your choices</h2>
          <p>
            You can access, update, or delete business and lead data directly within the
            dashboard, and manage notification preferences in Settings.
          </p>
        </section>

        <section>
          <h2>9. Changes to this policy</h2>
          <p>We may update this policy from time to time and will post the current version here.</p>
        </section>

        <section>
          <h2>10. Contact</h2>
          <p>
            Questions about this policy can be sent to{" "}
            <a href="mailto:privacy@converana.com" className="text-brand hover:underline">
              privacy@converana.com
            </a>
            .
          </p>
        </section>
      </div>
    </div>
  );
}
