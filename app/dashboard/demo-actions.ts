"use server";

import { revalidatePath } from "next/cache";
import { requireBusiness } from "@/lib/auth/session";
import { loadDemoData, removeDemoData } from "@/lib/demo";

export async function removeDemoDataAction() {
  const { business } = await requireBusiness();
  await removeDemoData(business.id);
  revalidatePath("/dashboard", "layout");
}

export async function loadDemoDataAction() {
  const { business } = await requireBusiness();
  await loadDemoData(business.id);
  revalidatePath("/dashboard", "layout");
}
