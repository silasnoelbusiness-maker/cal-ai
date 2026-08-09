import "server-only";
import Stripe from "stripe";
import { isStripeConfigured } from "@/lib/auth/config";

export class BillingUnavailableError extends Error {
  constructor(message = "Billing is temporarily unavailable.") {
    super(message);
    this.name = "BillingUnavailableError";
  }
}

let cachedClient: Stripe | null = null;

export function getStripeClient(): Stripe {
  if (!isStripeConfigured) {
    throw new BillingUnavailableError("Billing isn't configured yet. Set STRIPE_SECRET_KEY to enable it.");
  }
  if (!cachedClient) {
    cachedClient = new Stripe(process.env.STRIPE_SECRET_KEY!);
  }
  return cachedClient;
}
