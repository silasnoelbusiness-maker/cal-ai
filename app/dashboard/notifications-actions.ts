"use server";

import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/db/prisma";
import { requireBusiness } from "@/lib/auth/session";

export async function markAllNotificationsReadAction() {
  const { business } = await requireBusiness();
  await prisma.notification.updateMany({
    where: { businessId: business.id, read: false },
    data: { read: true },
  });
  revalidatePath("/dashboard");
}

export async function markNotificationReadAction(notificationId: string) {
  const { business } = await requireBusiness();
  // Scoped by businessId so a client-supplied id can never touch another
  // business's notification.
  await prisma.notification.updateMany({
    where: { id: notificationId, businessId: business.id },
    data: { read: true },
  });
  revalidatePath("/dashboard");
}
