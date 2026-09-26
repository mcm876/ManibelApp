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

/// One accepted government ID type from `GET /auth/commuter/id-types`.
class GovernmentIdType {
  final String code;
  final String label;
  final bool hasExpiry;
  final bool requiresBack;

  const GovernmentIdType({
    required this.code,
    required this.label,
    required this.hasExpiry,
    required this.requiresBack,
  });

  factory GovernmentIdType.fromJson(Map<String, dynamic> json) =>
      GovernmentIdType(
        code: json['code'] as String,
        label: json['label'] as String,
        hasExpiry: json['hasExpiry'] as bool,
        requiresBack: json['requiresBack'] as bool,
      );
}

/// Outcome of `POST /auth/commuter/verify-id`. [approved] means every check
/// passed; otherwise the submission is waiting on a manual review, and
/// [reviewReasons] says why (e.g. `FACE_NOT_MATCHED`, `FACE_UNVERIFIED`,
/// `BIRTH_DATE_UNREADABLE`).
class IdVerificationResult {
  final bool approved;
  final List<String> reviewReasons;

  const IdVerificationResult({
    required this.approved,
    required this.reviewReasons,
  });
}

/// Result of `GET /auth/commuter/id-status`. [status] is `NONE`,
/// `PENDING_REVIEW` or `VERIFIED`; [rejectionReason] is set when an admin
/// rejected the latest submission (status is then `NONE`).
class IdStatus {
  final String status;
  final String? idTypeLabel;
  final String? rejectionReason;

  const IdStatus({
    required this.status,
    this.idTypeLabel,
    this.rejectionReason,
  });
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

  /// Verifies the OTP sent right after commuter signup. Unlike
  /// [verifyResetOtp], this doesn't return a token — the caller already has
  /// a session token from [commuterSignUp]; this just confirms phone
  /// ownership before moving on to ID + face verification.
  static Future<Map<String, dynamic>> verifySignupOtp({
    required String mobileNumber,
    required String code,
  }) async {
    final json = await ApiClient.instance.post(
      '/auth/commuter/verify-signup-otp',
      body: {'mobileNumber': mobileNumber, 'code': code},
    );
    return json['commuter'] as Map<String, dynamic>;
  }

  /// Re-sends the signup-verification OTP. The server logs the code to its
  /// console in local dev — there's no SMS gateway wired up.
  static Future<void> resendSignupOtp({required String mobileNumber}) async {
    await ApiClient.instance.post(
      '/auth/commuter/resend-signup-otp',
      body: {'mobileNumber': mobileNumber},
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

  static Future<List<GovernmentIdType>> getIdTypes({
    required String token,
  }) async {
    final json = await ApiClient.instance.get(
      '/auth/commuter/id-types',
      token: token,
    );
    return (json['idTypes'] as List)
        .map((e) => GovernmentIdType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Submits the ID photos, selfie and the dates the app read off the ID.
  /// Throws [ApiException] with code `underage` / `id_expired` when the ID
  /// itself disqualifies the commuter.
  static Future<IdVerificationResult> verifyId({
    required String token,
    required String idTypeCode,
    required String frontPath,
    String? backPath,
    required String selfiePath,
    String? birthDate,
    String? expiryDate,
  }) async {
    final json = await ApiClient.instance.postMultipart(
      '/auth/commuter/verify-id',
      token: token,
      fields: {
        'idTypeCode': idTypeCode,
        if (birthDate != null) 'birthDate': birthDate,
        if (expiryDate != null) 'expiryDate': expiryDate,
      },
      files: {
        'front': frontPath,
        if (backPath != null) 'back': backPath,
        'selfie': selfiePath,
      },
    );
    return IdVerificationResult(
      approved: json['status'] == 'APPROVED',
      reviewReasons: (json['reviewReasons'] as List).cast<String>(),
    );
  }

  static Future<IdStatus> getIdStatus({required String token}) async {
    final json = await ApiClient.instance.get(
      '/auth/commuter/id-status',
      token: token,
    );
    return IdStatus(
      status: json['status'] as String,
      idTypeLabel: json['idTypeLabel'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
    );
  }
}
