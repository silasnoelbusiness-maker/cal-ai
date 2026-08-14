import Script from "next/script";

/**
 * Whop advertising pixel.
 *
 * Whop is used for advertising attribution only — checkout, billing,
 * subscriptions and plan activation all run through Stripe, and nothing here
 * touches any of that.
 *
 * Mounted from the marketing and auth layouts rather than the root layout,
 * so it covers the ad → landing page → signup funnel without loading on:
 *   - /dashboard/**, where it would send authenticated customers' page views
 *     to a third party that the privacy policy doesn't disclose; and
 *   - /embed/[businessId], which renders inside OUR customers' own websites,
 *     where firing our tracking on their visitors would be their legal
 *     exposure, not ours.
 *
 * The script body below is Whop's snippet verbatim, character for character.
 * Only the surrounding <script> tag is replaced by next/script, which emits
 * the same tag itself. Do not reformat it — a linter run over this string
 * would change what Whop serves.
 */
const WHOP_PIXEL = `!function(w,d,s,u,n,a,b){if(w[n])return;a=w[n]={q:[],t:+new Date,s:[],o:u,track:function(){a.q.push([+new Date].concat([].slice.call(arguments)))},setScope:function(){a.s=[].slice.call(arguments).filter(function(x){return typeof x==="string"});a.q.push([+new Date,"setScope"].concat(a.s))},scope:function(){var c=[].slice.call(arguments);return{track:function(){a.q.push([+new Date].concat([].slice.call(arguments)).concat([{__scope:c}]))}}}};b=d.createElement(s);b.async=1;b.src=u+"/s.js";d.getElementsByTagName(s)[0].parentNode.insertBefore(b,d.getElementsByTagName(s)[0])}(window,document,"script","https://t.whop.tw","whop");whop.setScope("biz_rQypTocnLGAaJw");whop.track("page");`;

export function WhopPixel() {
  return (
    <Script
      id="whop-pixel"
      strategy="afterInteractive"
      dangerouslySetInnerHTML={{ __html: WHOP_PIXEL }}
    />
  );
}
