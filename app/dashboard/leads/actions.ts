"use server";

import { revalidatePath } from "next/cache";
import { requireBusiness } from "@/lib/auth/session";
import { createLead } from "@/lib/leads/create-lead";

const TEST_LEADS = [
  {
    firstName: "Taylor",
    lastName: "Reed",
    email: "taylor.reed@example.com",
    phone: "+15125550199",
    serviceRequested: "AC Repair",
    message: "My air conditioner is blowing warm air, can someone take a look this week?",
  },
  {
    firstName: "Jordan",
    lastName: "Blake",
    email: "jordan.blake@example.com",
    phone: "+15125550188",
    serviceRequested: "Drain Cleaning",
    message: "Kitchen sink is draining really slowly, looking for a quote.",
  },
  {
    firstName: "Casey",
    lastName: "Morgan",
    email: "casey.morgan@example.com",
    phone: "+15125550177",
    serviceRequested: "Roof Inspection",
    message: "Noticed a few shingles missing after the storm, want it checked out.",
  },
];

export async function createTestLeadAction() {
  const { business } = await requireBusiness();
  const sample = TEST_LEADS[Math.floor(Math.random() * TEST_LEADS.length)];

  const result = await createLead(business, {
    ...sample,
    source: "manual",
    channel: "WEB",
  });

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/leads");
  return result;
}
