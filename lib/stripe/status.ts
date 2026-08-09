import type Stripe from "stripe";
import type { SubscriptionStatus } from "@prisma/client";

/** Maps a Stripe subscription status to LeadLoop's SubscriptionStatus enum. */
export function mapStripeStatus(status: Stripe.Subscription.Status): SubscriptionStatus {
  switch (status) {
    case "trialing":
      return "TRIALING";
    case "active":
      return "ACTIVE";
    case "past_due":
      return "PAST_DUE";
    case "canceled":
    case "incomplete_expired":
      return "CANCELED";
    case "incomplete":
      return "INCOMPLETE";
    case "unpaid":
      return "UNPAID";
    default:
      return "NONE";
  }
}
