import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

/**
 * Whop is an advertising pixel only — it must never creep into the billing
 * path, and it must never load where it would track someone who hasn't
 * agreed to it.
 *
 * These assertions read the source files directly, because the risk being
 * guarded against is a future refactor: a formatter reflowing the vendor
 * snippet, or someone hoisting the pixel into the root layout without
 * noticing what else that layout wraps.
 */

const read = (path: string) => readFileSync(path, "utf8");

/** Whop's snippet exactly as supplied, minus its <script> wrapper. */
const OFFICIAL_SNIPPET =
  '!function(w,d,s,u,n,a,b){if(w[n])return;a=w[n]={q:[],t:+new Date,s:[],o:u,track:function(){a.q.push([+new Date].concat([].slice.call(arguments)))},setScope:function(){a.s=[].slice.call(arguments).filter(function(x){return typeof x==="string"});a.q.push([+new Date,"setScope"].concat(a.s))},scope:function(){var c=[].slice.call(arguments);return{track:function(){a.q.push([+new Date].concat([].slice.call(arguments)).concat([{__scope:c}]))}}}};b=d.createElement(s);b.async=1;b.src=u+"/s.js";d.getElementsByTagName(s)[0].parentNode.insertBefore(b,d.getElementsByTagName(s)[0])}(window,document,"script","https://t.whop.tw","whop");whop.setScope("biz_rQypTocnLGAaJw");whop.track("page");';

describe("the vendor snippet is preserved verbatim", () => {
  it("matches Whop's snippet character for character", () => {
    const source = read("components/analytics/whop-pixel.tsx");
    const match = source.match(/const WHOP_PIXEL = `([\s\S]*?)`;/);

    expect(match, "WHOP_PIXEL constant not found").not.toBeNull();
    expect(match![1]).toBe(OFFICIAL_SNIPPET);
  });

  it("carries the correct business id", () => {
    expect(OFFICIAL_SNIPPET).toContain('whop.setScope("biz_rQypTocnLGAaJw")');
  });
});

describe("the pixel only loads where it should", () => {
  const mounts = (path: string) => read(path).includes("WhopPixel");

  it("loads on the marketing and auth funnels", () => {
    expect(mounts("app/(marketing)/layout.tsx")).toBe(true);
    expect(mounts("app/(auth)/layout.tsx")).toBe(true);
  });

  it("does not load on authenticated dashboard pages", () => {
    // Logged-in customers' page views are not ours to hand to an ad network.
    expect(mounts("app/dashboard/layout.tsx")).toBe(false);
    expect(mounts("app/onboarding/layout.tsx")).toBe(false);
  });

  it("does not load from the root layout, which wraps everything", () => {
    expect(mounts("app/layout.tsx")).toBe(false);
  });

  it("does not load inside the embeddable lead form", () => {
    // That page renders on OUR customers' websites — firing our advertising
    // pixel on their visitors would be their legal exposure, not ours.
    expect(read("app/embed/[businessId]/page.tsx")).not.toContain("WhopPixel");
  });
});

describe("Whop stays out of billing", () => {
  it("appears nowhere in the Stripe or plan-limit code", () => {
    for (const path of [
      "lib/stripe/checkout.ts",
      "lib/stripe/client.ts",
      "lib/plans.ts",
      "app/api/stripe/webhook/route.ts",
      "app/api/stripe/checkout/route.ts",
    ]) {
      expect(read(path).toLowerCase(), path).not.toContain("whop");
    }
  });
});
