class AuthService {
  /// Central active password state across login sessions for testing
  static String activePassword = 'Password123!';

  /// Strict password validation rules:
  /// - At least 8 characters
  /// - At least 1 uppercase letter (A-Z)
  /// - At least 1 lowercase letter (a-z)
  /// - At least 1 number (0-9)
  /// - At least 1 special character (!@#$%^&*)
  static String? validatePasswordRules(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    if (!RegExp(r'(?=.*[A-Z])').hasMatch(value)) {
      return 'Must contain at least one uppercase letter (A-Z)';
    }
    if (!RegExp(r'(?=.*[a-z])').hasMatch(value)) {
      return 'Must contain at least one lowercase letter (a-z)';
    }
    if (!RegExp(r'(?=.*[0-9])').hasMatch(value)) {
      return 'Must contain at least one number (0-9)';
    }
    if (!RegExp(r'(?=.*[!@#\$&*~%^()_+=|{}[\],.<>?/\-])').hasMatch(value)) {
      return 'Must contain at least one special character (!@#\$%^&*)';
    }
    return null;
  }
}