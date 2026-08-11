import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The terms that govern use of the Converana platform.",
};

const EFFECTIVE_DATE = "January 1, 2026";

export default function TermsPage() {
  return (
    <div className="mx-auto max-w-3xl px-4 py-16 sm:px-6 sm:py-24">
      <h1 className="text-3xl font-semibold tracking-tight text-foreground">Terms of Service</h1>
      <p className="mt-2 text-sm text-muted">Effective {EFFECTIVE_DATE}</p>

      <div className="prose-sm mt-10 space-y-6 text-sm leading-relaxed text-foreground [&_h2]:mt-8 [&_h2]:text-base [&_h2]:font-semibold [&_p]:text-muted [&_li]:text-muted">
        <p className="text-muted">
          These Terms of Service (&quot;Terms&quot;) govern access to and use of Converana (the
          &quot;Service&quot;), provided by Converana (&quot;Converana,&quot; &quot;we,&quot;
          &quot;us&quot;). By creating an account or using the Service, you agree to these Terms.
        </p>

        <section>
          <h2>1. The Service</h2>
          <p>
            Converana is software that helps businesses capture, store, and follow up with leads,
            including AI-assisted qualification and automated messaging. Converana is a tool — it
            does not provide legal, medical, financial, or other professional advice, and it does
            not guarantee any specific business outcome, revenue, or number of customers.
          </p>
        </section>

        <section>
          <h2>2. Your responsibilities</h2>
          <p>
            You are responsible for the accuracy of the business information you provide, for the
            content of communications sent to your customers (including AI-generated messages you
            choose to send or automate), and for complying with all applicable laws regarding
            customer communications, including telemarketing, SMS (e.g., TCPA), email (e.g.,
            CAN-SPAM), and data protection laws relevant to your business and jurisdiction.
            Converana provides consent-tracking fields and opt-out handling as tools, but you are
            responsible for using them correctly and for obtaining any consent required by law
            before contacting a lead.
          </p>
        </section>

        <section>
          <h2>3. AI features</h2>
          <p>
            Converana&apos;s AI assistant is configured using information you provide about your
            business. It is designed not to invent pricing, availability, or promises on your
            behalf, and to escalate situations that need a human. You remain responsible for
            reviewing AI-suggested replies before they are sent where applicable, and for the
            business settings that shape the AI&apos;s behavior.
          </p>
        </section>

        <section>
          <h2>4. Accounts and data</h2>
          <p>
            You are responsible for maintaining the confidentiality of your account credentials
            and API keys. Each business account&apos;s data is isolated and accessible only to
            authorized members of that business. See our{" "}
            <a href="/privacy" className="text-brand hover:underline">
              Privacy Policy
            </a>{" "}
            for details on how we handle data.
          </p>
        </section>

        <section>
          <h2>5. Billing</h2>
          <p>
            Paid plans are billed monthly in advance via our payment processor (Stripe). You can
            cancel at any time from your billing settings; access continues through the end of the
            current billing period. Plan limits (leads, AI messages, and team members) are
            described on our{" "}
            <a href="/pricing" className="text-brand hover:underline">
              pricing page
            </a>{" "}
            and enforced automatically.
          </p>
        </section>

        <section>
          <h2>6. No guarantees</h2>
          <p>
            Converana helps automate and speed up lead follow-up, but we do not guarantee
            increased revenue, conversions, or customer acquisition. Results depend on your
            business, market, and how you use the Service.
          </p>
        </section>

        <section>
          <h2>7. Termination</h2>
          <p>
            You may stop using the Service and cancel your subscription at any time. We may
            suspend or terminate accounts that violate these Terms or applicable law.
          </p>
        </section>

        <section>
          <h2>8. Disclaimers and limitation of liability</h2>
          <p>
            The Service is provided &quot;as is&quot; without warranties of any kind. To the
            maximum extent permitted by law, Converana is not liable for indirect, incidental, or
            consequential damages arising from use of the Service.
          </p>
        </section>

        <section>
          <h2>9. Changes</h2>
          <p>
            We may update these Terms from time to time. Continued use of the Service after
            changes take effect constitutes acceptance of the updated Terms.
          </p>
        </section>

        <section>
          <h2>10. Contact</h2>
          <p>
            Questions about these Terms can be sent to{" "}
            <a href="mailto:legal@converana.com" className="text-brand hover:underline">
              legal@converana.com
            </a>
            .
          </p>
        </section>
      </div>
    </div>
  );
}
