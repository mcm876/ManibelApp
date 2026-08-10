/**
 * Mirrors the Flutter app's PhoneUtils.toE164 (lib/core/utils/phone_utils.dart)
 * so the server normalizes PH mobile numbers the same way the client does
 * before comparing/storing them. Keep these two in sync.
 */
export function toE164(phone: string): string {
  const trimmed = phone.trim();
  if (trimmed.startsWith('+63')) {
    return `+63${trimmed.slice(3).replace(/\D/g, '')}`;
  }

  const digitsOnly = trimmed.replace(/\D/g, '');

  if (digitsOnly.startsWith('63')) {
    return `+${digitsOnly}`;
  }
  if (digitsOnly.startsWith('0')) {
    return `+63${digitsOnly.slice(1)}`;
  }
  return `+63${digitsOnly}`;
}
