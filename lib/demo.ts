// Note: intentionally no `import "server-only"` here — this module is also
// imported by prisma/seed.ts, which runs as a plain Node script outside
// Next.js's server-component bundling, where the server-only guard throws
// unconditionally. It's still only ever called from server actions, route
// handlers, and this seed script.
import { prisma } from "@/lib/db/prisma";
import { currentMonthKey } from "@/lib/plans";

/**
 * V1 demo/sample data (Section 41). Everything created here is flagged
 * isDemo: true so it can be identified in the UI and removed cleanly via
 * removeDemoData(). This never runs automatically — a user opts in.
 */
export async function loadDemoData(businessId: string) {
  const now = new Date();
  const daysAgo = (n: number) => new Date(now.getTime() - n * 24 * 60 * 60 * 1000);
  const hoursFromNow = (n: number) => new Date(now.getTime() + n * 60 * 60 * 1000);

  // John Smith — AC Repair — HOT, with a full qualifying conversation + appointment.
  const john = await prisma.lead.create({
    data: {
      businessId,
      firstName: "John",
      lastName: "Smith",
      email: "john.smith@example.com",
      phone: "+15125550101",
      source: "website",
      serviceRequested: "AC Repair",
      message: "My AC stopped working and it's 95 degrees. Can someone come tomorrow?",
      status: "APPOINTMENT",
      temperature: "HOT",
      estimatedValue: 950,
      qualificationScore: 91,
      aiIntent: "high",
      aiUrgency: "high",
      aiLocation: "Austin, TX 78701",
      aiBudget: "Unknown",
      aiAvailability: "Tomorrow morning",
      aiSummary: "Customer needs emergency AC repair. Unit stopped cooling entirely.",
      aiRecommendedAction: "Call customer immediately to confirm the appointment window.",
      needsHuman: false,
      smsConsent: true,
      isDemo: true,
      createdAt: daysAgo(1),
      lastContactedAt: daysAgo(1),
    },
  });

  const johnConvo = await prisma.conversation.create({
    data: {
      businessId,
      leadId: john.id,
      channel: "WEB",
      status: "OPEN",
      createdAt: daysAgo(1),
    },
  });

  await prisma.message.createMany({
    data: [
      {
        conversationId: johnConvo.id,
        sender: "CUSTOMER",
        content: "My AC stopped working and it's 95 degrees. Can someone come tomorrow?",
        createdAt: daysAgo(1),
      },
      {
        conversationId: johnConvo.id,
        sender: "AI",
        content: "Sorry to hear that, John. We can help with AC repairs — what ZIP code is the property in?",
        aiGenerated: true,
        createdAt: daysAgo(1),
      },
      { conversationId: johnConvo.id, sender: "CUSTOMER", content: "78701", createdAt: daysAgo(1) },
      {
        conversationId: johnConvo.id,
        sender: "AI",
        content: "Got it. Are you available in the morning or afternoon tomorrow?",
        aiGenerated: true,
        createdAt: daysAgo(1),
      },
      { conversationId: johnConvo.id, sender: "CUSTOMER", content: "Morning works best.", createdAt: daysAgo(1) },
    ],
  });

  await prisma.appointment.create({
    data: {
      businessId,
      leadId: john.id,
      scheduledAt: hoursFromNow(18),
      status: "CONFIRMED",
      notes: "AC not cooling — bring refrigerant gauges.",
    },
  });

  await prisma.leadEvent.createMany({
    data: [
      { leadId: john.id, businessId, type: "LEAD_CREATED", description: "Lead captured from website form.", createdAt: daysAgo(1) },
      { leadId: john.id, businessId, type: "AI_QUALIFIED", description: "AI qualified this lead as HOT (score 91).", createdAt: daysAgo(1) },
      { leadId: john.id, businessId, type: "APPOINTMENT_BOOKED", description: "Appointment confirmed for tomorrow morning.", createdAt: daysAgo(1) },
    ],
  });

  // Sarah Johnson — Maintenance — WARM
  const sarah = await prisma.lead.create({
    data: {
      businessId,
      firstName: "Sarah",
      lastName: "Johnson",
      email: "sarah.johnson@example.com",
      phone: "+15125550102",
      source: "google_ads",
      serviceRequested: "AC Maintenance",
      message: "Looking to get my system serviced before summer.",
      status: "QUALIFIED",
      temperature: "WARM",
      estimatedValue: 220,
      qualificationScore: 58,
      aiIntent: "medium",
      aiUrgency: "low",
      aiLocation: "Austin, TX",
      aiBudget: "Unknown",
      aiAvailability: "Flexible, prefers weekends",
      aiSummary: "Customer wants routine AC maintenance, no urgency.",
      aiRecommendedAction: "Offer available weekend slots within the next two weeks.",
      isDemo: true,
      createdAt: daysAgo(3),
      lastContactedAt: daysAgo(2),
      nextFollowUpAt: hoursFromNow(20),
    },
  });

  const sarahConvo = await prisma.conversation.create({
    data: { businessId, leadId: sarah.id, channel: "WEB", status: "OPEN", createdAt: daysAgo(3) },
  });
  await prisma.message.createMany({
    data: [
      { conversationId: sarahConvo.id, sender: "CUSTOMER", content: "Looking to get my system serviced before summer.", createdAt: daysAgo(3) },
      {
        conversationId: sarahConvo.id,
        sender: "AI",
        content: "Happy to help! Do weekday or weekend appointments work better for you?",
        aiGenerated: true,
        createdAt: daysAgo(3),
      },
    ],
  });
  await prisma.leadEvent.create({
    data: { leadId: sarah.id, businessId, type: "AI_QUALIFIED", description: "AI qualified this lead as WARM (score 58).", createdAt: daysAgo(3) },
  });

  // Mike Brown — Installation — COLD
  const mike = await prisma.lead.create({
    data: {
      businessId,
      firstName: "Mike",
      lastName: "Brown",
      email: "mike.brown@example.com",
      phone: "+15125550103",
      source: "facebook_ads",
      serviceRequested: "New System Installation",
      message: "Just curious what a new install would run.",
      status: "NEW",
      temperature: "COLD",
      estimatedValue: 6500,
      qualificationScore: 22,
      aiIntent: "low",
      aiUrgency: "low",
      aiLocation: "Unknown",
      aiBudget: "Unknown",
      aiAvailability: "Unknown",
      aiSummary: "Customer is early-stage researching pricing, no immediate need identified.",
      aiRecommendedAction: "Send pricing guide and re-engage in a few weeks.",
      isDemo: true,
      createdAt: daysAgo(5),
    },
  });
  await prisma.leadEvent.create({
    data: { leadId: mike.id, businessId, type: "LEAD_CREATED", description: "Lead captured from Facebook Ads.", createdAt: daysAgo(5) },
  });

  // A couple more leads for pipeline/analytics variety.
  const priya = await prisma.lead.create({
    data: {
      businessId,
      firstName: "Priya",
      lastName: "Nair",
      email: "priya.nair@example.com",
      phone: "+15125550104",
      source: "referral",
      serviceRequested: "Water Heater Install",
      status: "CONVERTED",
      temperature: "HOT",
      estimatedValue: 1800,
      qualificationScore: 88,
      aiLocation: "Round Rock, TX",
      aiUrgency: "high",
      aiSummary: "Customer needed same-week water heater replacement.",
      aiRecommendedAction: "Job completed — follow up for a review.",
      isDemo: true,
      createdAt: daysAgo(10),
      convertedAt: daysAgo(6),
    },
  });
  await prisma.appointment.create({
    data: {
      businessId,
      leadId: priya.id,
      scheduledAt: daysAgo(7),
      status: "COMPLETED",
      notes: "Installed 50-gallon water heater.",
    },
  });

  await prisma.lead.create({
    data: {
      businessId,
      firstName: "Chris",
      lastName: "Ibe",
      email: "chris.ibe@example.com",
      source: "website",
      serviceRequested: "Duct Cleaning",
      status: "LOST",
      temperature: "COLD",
      estimatedValue: 300,
      qualificationScore: 15,
      aiSummary: "Customer went with another provider.",
      aiRecommendedAction: "No further action needed.",
      isDemo: true,
      createdAt: daysAgo(14),
    },
  });

  // Usage counters for the current month so the dashboard/analytics aren't empty.
  const month = currentMonthKey();
  await prisma.usage.upsert({
    where: { businessId_month: { businessId, month } },
    create: {
      businessId,
      month,
      leadsCount: 6,
      messagesCount: 9,
      aiMessagesCount: 6,
      appointmentsCount: 2,
    },
    update: {
      leadsCount: { increment: 6 },
      messagesCount: { increment: 9 },
      aiMessagesCount: { increment: 6 },
      appointmentsCount: { increment: 2 },
    },
  });
}

export async function removeDemoData(businessId: string) {
  await prisma.lead.deleteMany({ where: { businessId, isDemo: true } });
}

export async function hasDemoData(businessId: string): Promise<boolean> {
  const count = await prisma.lead.count({ where: { businessId, isDemo: true } });
  return count > 0;
}
