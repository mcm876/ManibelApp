/// Basic email checks shared by sign-up and Settings. The backend validates
/// again (see utils/emailAddress.ts) — this just catches typos early.
class EmailUtils {
  const EmailUtils._();

  static final RegExp _pattern = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$');

  /// Lowercased/trimmed form, as the backend stores it.
  static String normalize(String value) => value.trim().toLowerCase();

  static bool isValid(String value) {
    final email = normalize(value);
    return email.length <= 254 && _pattern.hasMatch(email);
  }
}
