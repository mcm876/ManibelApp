// Pragmatic email check — one "@", no spaces, a dotted domain. Real
// deliverability can't be proven by a regex; this just rejects typos.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;

/** The trimmed, lowercased address, or null when it isn't a valid email. */
export function normalizeEmail(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) return null;
  return email;
}

export const INVALID_EMAIL_MESSAGE = 'Please enter a valid email address.';
