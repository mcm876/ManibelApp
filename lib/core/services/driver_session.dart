import 'package:shared_preferences/shared_preferences.dart';

/// Session store for the logged-in driver. Mirrors [UserSession] (the
/// commuter equivalent) but keeps its own prefs keys/prefix so a driver
/// account never collides with a commuter account on the same device.
/// Login goes through the backend (see AuthApi.driverLogIn) — drivers don't
/// self-register in the app; accounts are provisioned out-of-band (see
/// backend/prisma/seed.ts for the local demo account).
class DriverSession {
  DriverSession._internal();

  static final DriverSession instance = DriverSession._internal();

  String? fullName;

  /// Always stored/compared in canonical `+63XXXXXXXXXX` form — see
  /// [PhoneUtils.toE164] wherever a raw user-entered number needs
  /// converting before it's compared against this.
  String? mobileNumber;

  String? driverId;

  /// The vehicle plate assigned to this driver. Set once when the account
  /// is created (by an operator/admin, in the real system) — never
  /// editable by the driver themselves, unlike name/mobile number.
  String? plateNumber;

  /// Local filesystem path to the picked profile photo (from image_picker),
  /// not a remote URL. Once a real backend/auth service exists, this
  /// should probably become an uploaded photo URL instead.
  String? photoPath;

  // Kept for DriverChangePasswordScreen's local "current password" check,
  // which still runs entirely against this session rather than the backend
  // (no change-password endpoint exists yet). NOT used for login anymore —
  // see [token].
  String? password;

  /// JWT returned by the backend on login (see AuthApi). Send this as
  /// `Authorization: Bearer $token` on any authenticated request.
  String? token;

  static const _kFullName = 'driver_session_fullName';
  static const _kMobileNumber = 'driver_session_mobileNumber';
  static const _kPassword = 'driver_session_password';
  static const _kDriverId = 'driver_session_driverId';
  static const _kPlateNumber = 'driver_session_plateNumber';
  static const _kPhotoPath = 'driver_session_photoPath';
  static const _kToken = 'driver_session_token';
  static const _kLoggedInFlag = 'driverLoggedIn';

  bool get isSignedIn => fullName != null;

  /// Loads whatever was previously persisted into the in-memory fields.
  /// Call this before relying on session data anywhere the app might have
  /// just cold-started.
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    fullName = prefs.getString(_kFullName);
    mobileNumber = prefs.getString(_kMobileNumber);
    password = prefs.getString(_kPassword);
    driverId = prefs.getString(_kDriverId);
    plateNumber = prefs.getString(_kPlateNumber);
    photoPath = prefs.getString(_kPhotoPath);
    token = prefs.getString(_kToken);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (fullName != null) await prefs.setString(_kFullName, fullName!);
    if (mobileNumber != null) {
      await prefs.setString(_kMobileNumber, mobileNumber!);
    }
    if (password != null) await prefs.setString(_kPassword, password!);
    if (driverId != null) await prefs.setString(_kDriverId, driverId!);
    if (plateNumber != null) await prefs.setString(_kPlateNumber, plateNumber!);
    if (photoPath != null) {
      await prefs.setString(_kPhotoPath, photoPath!);
    } else {
      await prefs.remove(_kPhotoPath);
    }
    if (token != null) {
      await prefs.setString(_kToken, token!);
    } else {
      await prefs.remove(_kToken);
    }
  }

  /// Called from DriverSettingsScreen when the driver saves profile
  /// changes.
  Future<void> updateProfile({
    String? fullName,
    String? mobileNumber,
  }) async {
    if (fullName != null && fullName.isNotEmpty) this.fullName = fullName;
    if (mobileNumber != null) this.mobileNumber = mobileNumber;
    await _persist();
  }

  /// Called from DriverSettingsScreen when the driver picks/removes a
  /// profile photo. Pass null to remove the current photo.
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

  /// Called after a successful login against the backend
  /// (AuthApi.driverLogIn). [fullName]/[driverId]/[plateNumber] should come
  /// from that response so the session reflects the server's record rather
  /// than stale or invented local data.
  Future<void> logIn({
    required String mobileNumber,
    String? fullName,
    String? driverId,
    String? plateNumber,
    String? token,
  }) async {
    this.mobileNumber = mobileNumber;
    if (fullName != null) this.fullName = fullName;
    this.driverId = driverId ?? this.driverId ?? _generateDriverId();
    this.plateNumber = plateNumber ?? this.plateNumber ?? _generatePlateNumber();
    if (token != null) this.token = token;
    await _persist();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, true);
  }

  /// Ends the current session WITHOUT deleting the account. Only the
  /// in-memory fields (so [isSignedIn] flips to false right away) and the
  /// "logged in" flag get cleared — credential verification lives on the
  /// backend now, not here.
  Future<void> signOut() async {
    fullName = null;
    mobileNumber = null;
    password = null;
    driverId = null;
    plateNumber = null;
    photoPath = null;
    token = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedInFlag, false);
  }

  String _generateDriverId() {
    final suffix = (DateTime.now().millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    return 'DR-$suffix';
  }

  String _generatePlateNumber() {
    final suffix = (DateTime.now().millisecondsSinceEpoch % 10000)
        .toString()
        .padLeft(4, '0');
    return 'NGP-$suffix';
  }
}
