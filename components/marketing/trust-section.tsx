import Link from "next/link";
import { Database, KeyRound, Lock, UserCheck } from "lucide-react";

/**
 * Credibility without social proof.
 *
 * Converana has no customers to quote yet, and inventing some would be both
 * dishonest and, for a paid ad account, dangerous. What it does have is
 * verifiable engineering: real data isolation, hashed keys, and an AI with
 * published limits. Those are checkable claims, which is a stronger trust
 * signal than an unattributed five-star quote.
 */

const POINTS = [
  {
    icon: Database,
    title: "Your data is yours alone",
    body: "Every query is scoped to your business on the server, and the same isolation is enforced at the database level. One account cannot read another's leads or conversations.",
  },
  {
    icon: KeyRound,
    title: "API keys are stored hashed",
    body: "We keep a hash, not the key. If our database were ever exposed, your key still couldn't be used — and you can revoke and reissue at any time.",
  },
  {
    icon: UserCheck,
    title: "The AI says what it is",
    body: "Asked whether they're talking to a person, it says it's an AI assistant for your business. It won't invent a price or promise a time you haven't confirmed.",
  },
  {
    icon: Lock,
    title: "Nothing is sold on",
    body: "Your leads and conversations are not sold or shared with third parties. Our processors are named in the privacy policy.",
  },
];

export function TrustSection() {
  return (
    <section className="border-t border-border bg-background py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            Built to be checked, not just believed
          </h2>
          <p className="mt-4 text-lg text-muted">
            Converana is new, so we&apos;re not going to show you testimonials we don&apos;t have.
            Here&apos;s what we can actually stand behind.
          </p>
        </div>

        <div className="mt-12 grid gap-6 sm:grid-cols-2">
          {POINTS.map((point) => {
            const Icon = point.icon;
            return (
              <div key={point.title} className="flex min-w-0 gap-4">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-brand/10 text-brand">
                  <Icon className="h-4.5 w-4.5" aria-hidden />
                </div>
                <div className="min-w-0">
                  <h3 className="text-sm font-semibold text-foreground">{point.title}</h3>
                  <p className="mt-1.5 text-sm leading-relaxed text-muted">{point.body}</p>
                </div>
              </div>
            );
          })}
        </div>

        <p className="mt-10 text-center text-sm text-muted">
          Read the{" "}
          <Link href="/privacy" className="text-brand underline underline-offset-2 hover:no-underline">
            Privacy Policy
          </Link>{" "}
          and{" "}
          <Link href="/terms" className="text-brand underline underline-offset-2 hover:no-underline">
            Terms of Service
          </Link>
          .
        </p>
      </div>
    </section>
  );
}
