import "server-only";
import { createHash, timingSafeEqual } from "crypto";

/**
 * Constant-time string comparison for secrets (shared-secret headers, etc.).
 * A plain `===` leaks timing information proportional to how many leading
 * characters match. Hashing both sides to a fixed-length digest first also
 * sidesteps the length-mismatch case, which `timingSafeEqual` would
 * otherwise throw on (and checking the length up front would itself leak
 * a timing signal).
 */
export function safeCompare(a: string, b: string): boolean {
  const digestA = createHash("sha256").update(a).digest();
  const digestB = createHash("sha256").update(b).digest();
  return timingSafeEqual(digestA, digestB);
}
