import 'package:shared_preferences/shared_preferences.dart';

/// Session store for the logged-in commuter.
///
/// Signup/login now go through the backend (see AuthApi) — this class
/// persists whatever that API returns (plus the JWT) to on-device storage
/// via shared_preferences, so it survives closing and reopening the app.
/// Profile edits (SettingsScreen) and change-password are still local-only
/// mocks pending their own endpoints. Consider moving off a raw singleton
/// onto Provider/Riverpod/Bloc so widgets can listen for changes instead of
/// reading a static field once at build time.
class UserSession {
  UserSession._internal();

  static final UserSession instance = UserSession._internal();

  String? fullName;

  /// Always stored/compared in canonical `+63XXXXXXXXXX` form — see
  /// [PhoneUtils.toE164] wherever a raw user-entered number needs
  /// converting before it's compared against this.
  String? mobileNumber;

  DateTime? dateOfBirth;
  String? commuterId;

  /// Local filesystem path to the picked profile photo (from image_picker),
  /// not a remote URL. Once a real backend/auth service exists, this
  /// should probably become an uploaded photo URL instead.
  String? photoPath;

  // Kept for ChangePasswordScreen's local "current password" check, which
  // still runs entirely against this session rather than the backend (no
  // change-password endpoint exists yet). NOT used for login anymore — see
  // [token].
  String? password;

  /// JWT returned by the backend on signup/login (see AuthApi). Send this
  /// as `Authorization: Bearer $token` on any authenticated request.
  String? token;

  static const _kFullName = 'session_fullName';
  static const _kMobileNumber = 'session_mobileNumber';
  static const _kPassword = 'session_password';
  static const _kCommuterId = 'session_commuterId';
  static const _kDateOfBirth = 'session_dateOfBirth';
  static const _kPhotoPath = 'session_photoPath';
  static const _kToken = 'session_token';
  static const _kLoggedInFlag = 'commuterLoggedIn';

  bool get isSignedIn => fullName != null;

  /// Loads whatever was previously persisted into the in-memory fields.
  /// Call this before relying on session data anywhere the app might have
  /// just cold-started (e.g. at the top of login, or on a splash screen
  /// that auto-navigates a "remembered" user straight to the dashboard).
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    fullName = prefs.getString(_kFullName);
    mobileNumber = prefs.getString(_kMobileNumber);
    password = prefs.getString(_kPassword);
    commuterId = prefs.getString(_kCommuterId);
    photoPath = prefs.getString(_kPhotoPath);
    token = prefs.getString(_kToken);
    final dobIso = prefs.getString(_kDateOfBirth);
    dateOfBirth = dobIso != null ? DateTime.tryParse(dobIso) : null;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (fullName != null) await prefs.setString(_kFullName, fullName!);
    if (mobileNumber != null) {
      await prefs.setString(_kMobileNumber, mobileNumber!);
    }
    if (password != null) await prefs.setString(_kPassword, password!);
    if (commuterId != null) await prefs.setString(_kCommuterId, commuterId!);
    if (photoPath != null) {
      await prefs.setString(_kPhotoPath, photoPath!);
    } else {
      await prefs.remove(_kPhotoPath);
    }
    if (dateOfBirth != null) {
      await prefs.setString(_kDateOfBirth, dateOfBirth!.toIso8601String());
    } else {
      await prefs.remove(_kDateOfBirth);
    }
    if (token != null) {
      await prefs.setString(_kToken, token!);
    } else {
      await prefs.remove(_kToken);
    }
  }

  /// Called after a successful sign-up. [mobileNumber] should already be
  /// normalized to `+63XXXXXXXXXX` (PhoneUtils.toE164).
  ///
  /// This always starts the account with no profile photo — a device's
  /// previous account (whoever was signed up before) must never leak its
  /// photo into a brand-new signup. [commuterId] should come from the
  /// backend's signup response (AuthApi.commuterSignUp); a local ID is
  /// only generated as a fallback if none is given.
  Future<void> signUp({
    required String fullName,
    required String mobileNumber,
    required String password,
    String? commuterId,
    String? token,
  }) async {
    this.fullName = fullName;
    this.mobileNumber = mobileNumber;
    this.password = password;
    photoPath = null;
    this.commuterId = commuterId ?? _generateCommuterId();
    if (token != null) this.token = token;
    await _persist();
  }

  /// Called after a successful login against the backend
  /// (AuthApi.commuterLogIn). [fullName]/[commuterId]/[dateOfBirth] should
  /// come from that response so the session reflects the server's record
  /// rather than stale local data.
  Future<void> logIn({
    required String mobileNumber,
    String? fullName,
    String? password,
    String? commuterId,
    String? token,
    DateTime? dateOfBirth,
  }) async {
    this.mobileNumber = mobileNumber;
    if (fullName != null) this.fullName = fullName;
    if (password != null) this.password = password;
    if (dateOfBirth != null) this.dateOfBirth = dateOfBirth;
    this.commuterId = commuterId ?? this.commuterId ?? _generateCommuterId();
    if (token != null) this.token = token;
    await _persist();
  }

  /// Called from SettingsScreen when the user saves profile changes.
  Future<void> updateProfile({
    String? fullName,
    String? mobileNumber,
    DateTime? dateOfBirth,
  }) async {
    if (fullName != null && fullName.isNotEmpty) this.fullName = fullName;
    if (mobileNumber != null) this.mobileNumber = mobileNumber;
    this.dateOfBirth = dateOfBirth;
    await _persist();
  }

  /// Called from SettingsScreen when the user picks/removes a profile
  /// photo. Pass null to remove the current photo.
  Future<void> updatePhoto(String? path) async {
    photoPath = path;
    await _persist();
  }

  /// Returns false if [currentPassword] doesn't match what's on file, so
  /// the caller can show an error instead of silently "succeeding".
  Future<bool> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (password != null && currentPassword != password) {
      return false;
    }
    password = newPassword;
    await _persist();
    return true;
  }

  /// Ends the current session WITHOUT deleting the account. The persisted
  /// profile fields stay on disk (SharedPreferences) so [loadFromPrefs] can
  /// find them again next time someone logs back in — only the in-memory
  /// fields (so `isSignedIn` flips to false right away) and the "logged
  /// in" flag get cleared. Actual credential verification now lives on the
  /// backend, not here, so there's nothing to preserve for a later local
  /// login check.
  Future<void> signOut() async {
    fullName = null;
    mobileNumber = null;
    dateOfBirth = null;
    password = null;
    commuterId = null;
    photoPath = null;
    token = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
  }

  String _generateCommuterId() {
    final suffix = (DateTime.now().millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    return 'CM-$suffix';
  }
}