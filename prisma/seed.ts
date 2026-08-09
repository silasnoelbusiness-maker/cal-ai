/**
 * Development seed script — creates a demo LeadLoop workspace you can log
 * into locally. Requires Supabase to be configured (it creates a real auth
 * user) since LeadLoop users are Supabase-auth-backed.
 *
 * Usage: npm run db:seed
 * Configure DEMO_USER_EMAIL / DEMO_USER_PASSWORD in .env.local first.
 */
import { loadEnvConfig } from "@next/env";

loadEnvConfig(process.cwd());

import { PrismaClient } from "@prisma/client";
import { createClient } from "@supabase/supabase-js";
import { loadDemoData } from "../lib/demo";

const prisma = new PrismaClient();

async function main() {
  const email = process.env.DEMO_USER_EMAIL;
  const password = process.env.DEMO_USER_PASSWORD;
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!email || !password) {
    console.log(
      "⚠️  DEMO_USER_EMAIL / DEMO_USER_PASSWORD not set — skipping seed.\n" +
        "   Set them in .env.local and re-run `npm run db:seed`."
    );
    return;
  }

  if (!supabaseUrl || !serviceRoleKey || supabaseUrl.includes("xxxx")) {
    console.log(
      "⚠️  Supabase isn't configured — skipping seed.\n" +
        "   Set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env.local first."
    );
    return;
  }

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  console.log(`Creating (or reusing) demo auth user ${email}...`);
  let userId: string;
  const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (created?.user) {
    userId = created.user.id;
  } else if (createError?.message?.toLowerCase().includes("already")) {
    const { data: list } = await supabaseAdmin.auth.admin.listUsers();
    const existing = list?.users.find((u) => u.email === email);
    if (!existing) throw new Error("Demo user exists in Supabase but could not be found.");
    userId = existing.id;
  } else {
    throw createError || new Error("Failed to create demo user.");
  }

  const user = await prisma.user.upsert({
    where: { id: userId },
    update: { email },
    create: { id: userId, email },
  });

  let business = await prisma.business.findFirst({ where: { ownerId: user.id } });
  if (!business) {
    business = await prisma.business.create({
      data: {
        ownerId: user.id,
        name: "PeakFlow HVAC",
        industry: "HVAC",
        website: "https://peakflowhvac.example.com",
        phone: "+15125550100",
        email,
        serviceArea: "Austin, TX and surrounding areas (25 mi)",
        timezone: "America/Chicago",
        businessHours: {
          mon: "8:00 AM - 6:00 PM",
          tue: "8:00 AM - 6:00 PM",
          wed: "8:00 AM - 6:00 PM",
          thu: "8:00 AM - 6:00 PM",
          fri: "8:00 AM - 6:00 PM",
          sat: "9:00 AM - 2:00 PM",
          sun: "Closed",
        },
        aiDescription: "A family-owned HVAC company serving greater Austin since 2010.",
        aiServices: "AC repair, AC installation, furnace repair, duct cleaning, maintenance plans",
        aiTypicalCustomer: "Homeowners needing repair, maintenance, or new system installs.",
        aiTone: "professional",
        onboardingCompleted: true,
        onboardingStep: 8,
      },
    });
    await prisma.businessMember.create({
      data: { businessId: business.id, userId: user.id, role: "OWNER" },
    });
    await prisma.followUpSettings.create({ data: { businessId: business.id } });
    await prisma.notificationSettings.create({ data: { businessId: business.id } });
    await prisma.subscription.create({ data: { businessId: business.id, plan: "STARTER", status: "NONE" } });
    console.log(`Created demo business "${business.name}".`);
  } else {
    console.log(`Reusing existing business "${business.name}".`);
  }

  const existingLeads = await prisma.lead.count({ where: { businessId: business.id } });
  if (existingLeads === 0) {
    await loadDemoData(business.id);
    console.log("Loaded sample leads, conversations, and an appointment.");
  } else {
    console.log("Business already has leads — skipping demo data load.");
  }

  console.log("\n✅ Seed complete. Log in with:");
  console.log(`   Email:    ${email}`);
  console.log(`   Password: ${password}`);
}

main()
  .catch((err) => {
    console.error("Seed failed:", err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
