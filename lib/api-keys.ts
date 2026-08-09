import "server-only";
import { randomBytes, createHash } from "crypto";
import { prisma } from "@/lib/db/prisma";

const KEY_PREFIX = "ll_live_";

function hashKey(rawKey: string): string {
  return createHash("sha256").update(rawKey).digest("hex");
}

export interface CreatedApiKey {
  id: string;
  name: string;
  keyPrefix: string;
  /** The full plaintext secret — only ever returned once, at creation. */
  plaintext: string;
}

/**
 * Generates a new API key for a business. The plaintext is returned once and
 * never stored — only its SHA-256 hash and a display prefix are persisted.
 */
export async function createApiKey(businessId: string, name: string): Promise<CreatedApiKey> {
  const secret = randomBytes(24).toString("base64url");
  const plaintext = `${KEY_PREFIX}${secret}`;
  const keyPrefix = plaintext.slice(0, KEY_PREFIX.length + 6);

  const record = await prisma.apiKey.create({
    data: {
      businessId,
      name: name.trim() || "API Key",
      keyPrefix,
      hashedKey: hashKey(plaintext),
    },
  });

  return { id: record.id, name: record.name, keyPrefix: record.keyPrefix, plaintext };
}

/**
 * Resolves a raw API key from an incoming request to its business. Never
 * trust a client-supplied businessId — this is the only legitimate way an
 * external request establishes which business it's acting on behalf of.
 */
export async function resolveApiKey(rawKey: string) {
  if (!rawKey.startsWith(KEY_PREFIX)) return null;

  const hashed = hashKey(rawKey);
  const record = await prisma.apiKey.findFirst({
    where: { hashedKey: hashed, revokedAt: null },
    include: { business: true },
  });
  if (!record) return null;

  await prisma.apiKey.update({ where: { id: record.id }, data: { lastUsedAt: new Date() } });

  return record;
}

export async function revokeApiKey(businessId: string, keyId: string) {
  await prisma.apiKey.updateMany({
    where: { id: keyId, businessId, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}
