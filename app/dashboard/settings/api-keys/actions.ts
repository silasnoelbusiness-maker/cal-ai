"use server";

import { revalidatePath } from "next/cache";
import { requireBusiness } from "@/lib/auth/session";
import { createApiKey, revokeApiKey, type CreatedApiKey } from "@/lib/api-keys";

export interface CreateApiKeyState {
  error?: string;
  key?: CreatedApiKey;
}

export async function createApiKeyAction(
  _prevState: CreateApiKeyState,
  formData: FormData
): Promise<CreateApiKeyState> {
  const { business } = await requireBusiness();
  const name = String(formData.get("name") || "").trim();
  if (!name) return { error: "Give this key a name." };

  const key = await createApiKey(business.id, name);
  revalidatePath("/dashboard/settings/api-keys");
  return { key };
}

export async function revokeApiKeyAction(keyId: string) {
  const { business } = await requireBusiness();
  await revokeApiKey(business.id, keyId);
  revalidatePath("/dashboard/settings/api-keys");
}
