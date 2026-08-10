import '../network/api_client.dart';

/// Result of a successful signup/login against the backend
/// (`backend/src/routes/authCommuter.ts` / `authDriver.ts`) — a session
/// token plus the raw profile JSON (`commuter` or `driver` object) the API
/// returned.
class AuthResult {
  final String token;
  final Map<String, dynamic> profile;

  const AuthResult({required this.token, required this.profile});
}

/// Calls the backend's `/auth/commuter` and `/auth/driver` routes. Screens
/// should go through this instead of hitting [ApiClient] directly, so the
/// request shapes stay in one place.
class AuthApi {
  const AuthApi._();

  static String _segment(bool isDriver) => isDriver ? 'driver' : 'commuter';

  static Future<AuthResult> commuterSignUp({
    required String fullName,
    required String mobileNumber,
    required String password,
    DateTime? dateOfBirth,
  }) async {
    final json = await ApiClient.instance.post(
      '/auth/commuter/signup',
      body: {
        'fullName': fullName,
        'mobileNumber': mobileNumber,
        'password': password,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
      },
    );
    return AuthResult(
      token: json['token'] as String,
      profile: json['commuter'] as Map<String, dynamic>,
    );
  }

  static Future<AuthResult> commuterLogIn({
    required String mobileNumber,
    required String password,
  }) async {
    final json = await ApiClient.instance.post(
      '/auth/commuter/login',
      body: {'mobileNumber': mobileNumber, 'password': password},
    );
    return AuthResult(
      token: json['token'] as String,
      profile: json['commuter'] as Map<String, dynamic>,
    );
  }

  static Future<AuthResult> driverLogIn({
    required String mobileNumber,
    required String password,
  }) async {
    final json = await ApiClient.instance.post(
      '/auth/driver/login',
      body: {'mobileNumber': mobileNumber, 'password': password},
    );
    return AuthResult(
      token: json['token'] as String,
      profile: json['driver'] as Map<String, dynamic>,
    );
  }

  /// Triggers a password-reset OTP for either role. The server logs the
  /// code to its console in local dev — there's no SMS gateway wired up.
  static Future<void> forgotPassword({
    required bool isDriver,
    required String mobileNumber,
  }) async {
    await ApiClient.instance.post(
      '/auth/${_segment(isDriver)}/forgot-password',
      body: {'mobileNumber': mobileNumber},
    );
  }

  /// Verifies the OTP and returns a short-lived reset token (10 min) to
  /// pass to [resetPassword] — the OTP itself can't be used to change the
  /// password directly, only to prove ownership of the account.
  static Future<String> verifyResetOtp({
    required bool isDriver,
    required String mobileNumber,
    required String code,
  }) async {
    final json = await ApiClient.instance.post(
      '/auth/${_segment(isDriver)}/verify-reset-otp',
      body: {'mobileNumber': mobileNumber, 'code': code},
    );
    return json['resetToken'] as String;
  }

  static Future<void> resetPassword({
    required bool isDriver,
    required String resetToken,
    required String newPassword,
  }) async {
    await ApiClient.instance.post(
      '/auth/${_segment(isDriver)}/reset-password',
      body: {'resetToken': resetToken, 'newPassword': newPassword},
    );
  }
}
