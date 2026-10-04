import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/widgets/rolling_road_loader.dart';
import '../../../core/services/driver_operations_log.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/services/user_session.dart';
import '../../auth/screens/about_app_screen.dart';
import '../../auth/screens/role_selection_screen.dart';
import '../../commuter/screens/commuter_dashboard_screen.dart';
import '../../commuter/screens/commuter_history_screen.dart';
import '../../commuter/screens/notifications_screen.dart';
import '../../driver/screens/driver_dashboard_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  /// The logo stays up at least this long — but the saved session is restored
  /// while it shows, not after it (it used to sit through a fixed 3 seconds
  /// first and only then start loading).
  static const Duration _minSplash = Duration(milliseconds: 1500);
  late final Future<void> _minVisible = Future<void>.delayed(_minSplash);

  void _navigateToNextScreen() {
    // Wrapped in an overall timeout — a platform call below (most likely a
    // secure-storage read; FlutterSecureStorage's Android Keystore backing is
    // known to hang on some devices/OS states) never resolving must never
    // leave the app stuck on this screen forever. A late completion is a
    // no-op once `mounted` is false (this screen is already gone by then).
    () async {
      try {
        await _resolveSessionAndNavigate().timeout(const Duration(seconds: 20));
      } catch (_) {
        // Something slow/failed while restoring the session. A saved login
        // must NOT be mistaken for "signed out" — go to its dashboard if one
        // is on hand, and only fall back to role selection with no session.
        final Widget fallback;
        if (DriverSession.instance.hasRememberedSession) {
          fallback = const DriverDashboardScreen();
        } else if (UserSession.instance.hasRememberedSession) {
          fallback = const CommuterDashboardScreen();
        } else {
          fallback = const RoleSelectionScreen();
        }
        await _go(fallback);
      }
    }();
  }

  /// Leaves the splash for [screen] once the logo has been visible long enough.
  Future<void> _go(Widget screen) async {
    await _minVisible;
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen));
  }

  /// False only when the backend positively rejects the saved token (401/403).
  /// Network errors and timeouts count as "still valid" — being offline at app
  /// start must not log anyone out — and the wait is short: a rejected token
  /// is also caught by whichever screen makes the first request (SessionGuard),
  /// so a slow network never holds the app on the splash.
  Future<bool> _sessionStillValid(String path, String? token) async {
    if (token == null) return false;
    try {
      await ApiClient.get(path, token: token).timeout(const Duration(milliseconds: 2500));
      return true;
    } on ApiException catch (e) {
      return !(e.statusCode == 401 || e.statusCode == 403);
    } catch (_) {
      return true;
    }
  }

  Future<void> _resolveSessionAndNavigate() async {
    // Checks for a saved session first (driver, then commuter — a device could
    // in theory have both, though that's rare) and skips straight to that
    // dashboard if found. Otherwise, a commuter who closed the app
    // mid-verification lands back on AboutAppScreen instead of role selection
    // — see UserSession.pendingVerificationMobileNumber.
    await Future.wait([
      DriverSession.instance.loadFromPrefs(),
      UserSession.instance.loadFromPrefs(),
    ]);
    if (!mounted) return;

    if (DriverSession.instance.hasRememberedSession) {
      // Ask the backend whether this saved token is still good, while the
      // local data the dashboard needs loads alongside. A rejected token has
      // already been signed out and sent to the start screen by SessionGuard;
      // an unreachable server is NOT a reason to sign anyone out, so the
      // cached session is used offline.
      final results = await Future.wait<Object?>([
        _sessionStillValid('/api/driver/me', DriverSession.instance.authToken),
        DriverOperationsLog.loadFromPrefs(),
      ]);
      if (results.first != true || !mounted) return;
      unawaited(DriverOperationsLog.syncFromBackend());
      await _go(const DriverDashboardScreen());
      return;
    }

    if (UserSession.instance.hasRememberedSession) {
      final results = await Future.wait<Object?>([
        _sessionStillValid('/api/commuter/me', UserSession.instance.authToken),
        CommuterHistoryScreen.loadFromPrefs(),
        NotificationsScreen.loadFromPrefs(),
      ]);
      if (results.first != true || !mounted) return;
      unawaited(CommuterHistoryScreen.syncFromBackend());
      await _go(const CommuterDashboardScreen());
      return;
    }

    final isPendingVerification = UserSession.instance.pendingVerificationMobileNumber != null;
    await _go(isPendingVerification ? const AboutAppScreen() : const RoleSelectionScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start, // Pushes content upward
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 80), // Controls top offset for logo position

              // Jeepney Graphic
              Image.asset(
                AppAssets.jeepneyLogo,
                width: 140,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.directions_bus_filled_rounded,
                    size: 100,
                    color: AppColors.logoBlue,
                  );
                },
              ),
              
              // Reduced spacing to bring text closer to the logo
              const SizedBox(height: 2),

              // "ManibelApp" Dual Color Title
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  children: [
                    TextSpan(
                      text: 'Manibel',
                      style: TextStyle(color: AppColors.logoBlue),
                    ),
                    TextSpan(
                      text: 'App',
                      style: TextStyle(color: AppColors.logoRed),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // A jeepney riding a dashed road instead of a generic spinner
              // — the wordmark alone gave no sign the app was actually
              // doing anything for the full 3 seconds, same gap the admin
              // website's own loading screen had before it got one.
              const RollingRoadLoader(),

              const SizedBox(height: 14),
              const Text(
                'Getting your ride ready…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}