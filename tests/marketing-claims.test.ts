import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  AI_GUARDRAILS,
  CHANNELS,
  LEAD_SOURCES,
  PLAN_LIMIT_BEHAVIOUR,
  PRODUCT_ANSWERS,
  START_FREE,
} from "@/lib/marketing/product-facts";
import { TESTIMONIALS, CASE_STUDIES } from "@/components/marketing/testimonials-section";

/**
 * The marketing site may only describe behaviour that ships.
 *
 * Copy drifts from reality quietly — a feature gets cut and the landing page
 * keeps promising it. These tests make that drift fail CI instead of failing
 * a customer, and they're the reason product-facts.ts records a `source` for
 * every claim.
 */

const read = (p: string) => readFileSync(p, "utf8");

const ALL_CLAIMS = [...LEAD_SOURCES, ...CHANNELS, ...PRODUCT_ANSWERS, ...AI_GUARDRAILS];

describe("every marketing claim names code that implements it", () => {
  it("cites at least one source per claim", () => {
    for (const claim of ALL_CLAIMS) {
      expect(claim.source.length, claim.title).toBeGreaterThan(0);
    }
  });

  it("every cited path actually exists", () => {
    for (const claim of ALL_CLAIMS) {
      for (const path of claim.source) {
        expect(existsSync(path), `${claim.title} cites missing path: ${path}`).toBe(true);
      }
    }
  });
});

describe("claims that would be lies if the code changed", () => {
  it("the AI really is instructed never to invent prices", () => {
    expect(read("lib/ai/prompt.ts")).toMatch(/Never invent prices/i);
  });

  it("the AI really is instructed never to claim to be human", () => {
    expect(read("lib/ai/prompt.ts")).toMatch(/Never claim to be a human/i);
  });

  it("the AI really is instructed not to promise unconfirmed appointment times", () => {
    expect(read("lib/ai/prompt.ts")).toMatch(/Never promise a specific appointment time/i);
  });

  it("\"no trial\" is true — checkout sets no trial period", () => {
    // START_FREE tells visitors there is no time-limited trial. The moment
    // someone adds trial_period_days, that sentence becomes false.
    expect(read("lib/stripe/checkout.ts")).not.toMatch(/trial_period_days|trial_end/);
    expect(START_FREE.detail).toMatch(/no time-limited trial/i);
  });

  it("\"no card at signup\" is true — signup never touches Stripe", () => {
    const signup = read("app/(auth)/actions.ts");
    expect(signup).not.toMatch(/stripe/i);
  });

  it("the lead limit really does decline new leads", () => {
    const createLead = read("lib/leads/create-lead.ts");
    expect(createLead).toMatch(/checkPlanLimit\(plan, "leads", usage\)/);
    expect(createLead).toMatch(/if \(!limitCheck\.allowed\)/);
    expect(PLAN_LIMIT_BEHAVIOUR.leads).toMatch(/declined/i);
  });

  it("imported leads really are not messaged, as the FAQ promises", () => {
    const importer = read("lib/leads/import/run.ts");
    expect(importer).toMatch(/smsConsent: false/);
    expect(importer).toMatch(/emailConsent: false/);
  });
});

describe("capabilities the site must NOT claim", () => {
  const marketingCopy = [
    "components/marketing/faq-section.tsx",
    "components/marketing/lead-sources-section.tsx",
    "components/marketing/product-clarity-section.tsx",
    "components/marketing/hero-section.tsx",
    "components/marketing/pricing-section.tsx",
    "lib/marketing/product-facts.ts",
  ]
    .map(read)
    .join("\n");

  it("never claims Converana makes phone calls", () => {
    // ConversationChannel has a PHONE member, but nothing implements voice.
    expect(marketingCopy).toMatch(/does not make phone calls|doesn't make or answer phone calls/i);
    expect(marketingCopy).not.toMatch(/we call your leads|automated calling|voice agent/i);
  });

  it("never claims a native Facebook or Google Ads integration", () => {
    const claimsNative = /(one-click|native|direct)\s+(facebook|google)/i;
    const disclaims = /no one-click Facebook or Google|there's no one-click Facebook/i;
    if (claimsNative.test(marketingCopy)) {
      expect(marketingCopy).toMatch(disclaims);
    }
  });

  it("never claims outbound webhooks, which are not implemented", () => {
    // The only webhooks in the codebase are inbound (Twilio, Stripe).
    expect(marketingCopy).not.toMatch(/outbound webhook|webhooks when|send webhooks/i);
  });

  it("never claims automatic appointment booking", () => {
    expect(marketingCopy).toMatch(/does not book|doesn't book|No\. It qualifies/i);
  });
});

describe("the demo button promises only what exists", () => {
  const modal = read("components/marketing/demo-modal.tsx");

  it("has no demo video, so the button must not name a runtime", () => {
    const hasVideo = !/const DEMO_VIDEO_URL: string \| null = null;/.test(modal);
    if (hasVideo) return; // A real recording exists; "60-Second Demo" is fair.
    expect(modal).toMatch(/"See Product Preview"/);
    expect(modal).toMatch(/DEMO_VIDEO_URL \? "Watch 60-Second Demo" : "See Product Preview"/);
  });

  it("makes no promise that a recording is coming", () => {
    expect(modal).not.toMatch(/on its way|coming soon|will be available/i);
  });

  it("keeps the illustrative-data disclaimer", () => {
    expect(modal).toMatch(/aren&apos;t results from a customer account|Illustrative data/i);
  });
});

describe("public mock-ups never imply automatic booking", () => {
  const mockups = [
    "components/marketing/product-preview.tsx",
    "components/marketing/dashboard-preview-section.tsx",
  ].map(read).join("\n");

  it("shows \"Ready to book\", not a booked appointment", () => {
    expect(mockups).not.toMatch(/Appointment booked/);
    expect(mockups).toMatch(/Ready to book/);
  });

  it("does not label a lead \"Converted\" in a marketing mock-up", () => {
    expect(mockups).not.toMatch(/>\s*Converted/);
  });

  it("labels ad-platform leads with the route they actually arrive by", () => {
    // A bare "Google Ads" source reads as a one-click integration.
    for (const m of mockups.matchAll(/source: "([^"]+)"/g)) {
      const source = m[1];
      if (/google ads|facebook ads/i.test(source)) {
        expect(source, `bare ad-platform source: ${source}`).toMatch(/·\s*via (API|CSV)/i);
      }
    }
  });
});

describe("no fabricated social proof", () => {
  it("ships with zero testimonials and zero case studies", () => {
    // Both stay empty until a real customer has agreed to be quoted. The
    // component renders nothing while they are, so an accidental import
    // cannot put invented praise on the site.
    expect(TESTIMONIALS).toHaveLength(0);
    expect(CASE_STUDIES).toHaveLength(0);
  });

  it("the testimonials section is not mounted on any page", () => {
    const homepage = read("app/(marketing)/page.tsx");
    expect(homepage).not.toMatch(/<TestimonialsSection/);
  });

  it("publishes no review or rating structured data", () => {
    // Invented review markup is a manual-action risk with Google, and we
    // have no reviews to mark up.
    const homepage = read("app/(marketing)/page.tsx");
    expect(homepage).not.toMatch(/aggregateRating|reviewCount|ratingValue/);
  });
});
