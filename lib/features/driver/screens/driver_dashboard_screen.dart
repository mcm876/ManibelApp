import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/map_config.dart';
import '../../../core/constants/route_path.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_operations_log.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/utils/location_settings.dart';
import '../../../core/widgets/logout_confirmation_sheet.dart';
import '../../../core/widgets/signing_out_screen.dart';
import '../../auth/screens/driver_login_screen.dart';
import '../widgets/passenger_info_sheet.dart';
import 'driver_daily_operations_screen.dart';
import 'driver_history_screen.dart';
import 'driver_menu_drawer.dart';
import 'driver_monthly_analytics_screen.dart';
import 'driver_notifications_screen.dart';
import 'driver_qr_code_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_start_trip_screen.dart';
import 'driver_trip_in_progress_screen.dart';
import 'driver_weekly_analytics_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

/// A trip currently in progress — exists only in memory between "Start
/// Trip" and "End Trip", same as everything else in this mocked app. No
/// passenger tracking here on purpose — drivers shouldn't be interacting
/// with the phone while driving.
class _ActiveTrip {
  final String route;
  final String plateNumber;
  final DateTime startTime;

  const _ActiveTrip({
    required this.route,
    required this.plateNumber,
    required this.startTime,
  });
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Seeded from the local driver session, which signup/login write into.
  // Once a real backend/auth service exists, replace this with a proper
  // fetch of the authenticated driver's profile.
  String _driverName = DriverSession.instance.fullName ?? 'Driver';
  String _driverId = DriverSession.instance.driverId ?? '—';
  String? _photoUrl = DriverSession.instance.photoUrl;

  // Trip state — "online" now just means "currently on a trip" instead of a
  // manually-flipped switch, since Start/End Trip is what actually drives
  // it.
  _ActiveTrip? _activeTrip;

  // Backend-sourced today's-stats — authoritative across devices, and the
  // only source for Today's Trips (shows 0 until this resolves, rather
  // than a locally-cached guess). Earnings falls back to
  // DriverOperationsLog's local store if this hasn't loaded yet/fails.
  int? _tripsTodayRemote;

  // Net income for today — what was taken in minus the fuel and other
  // expenses the driver logged (see GET /driver/today-stats). This is what
  // the "Earnings Today" card shows, not gross revenue.
  double? _netIncomeTodayRemote;

  // null | 'PENDING' | 'APPROVED' | 'REJECTED' — see
  // DriverSession.refreshLicenseStatus. Gates Start Trip (see
  // _handleStartTrip) and drives the "not verified yet" note below the
  // profile header; refetched fresh every time this screen loads rather
  // than trusted from whatever was last cached, since an admin can
  // approve/reject at any time from outside the app.
  String? _licenseStatus;

  bool get _isOnline => _activeTrip != null;

  // Fallback used only if GPS is unavailable/denied — San Juan City, Metro
  // Manila. Mirrors the commuter dashboard's real-map setup exactly.
  static const LatLng _fallbackLocation = LatLng(14.6019, 121.0355);

  // A fix worse than this (in meters) is treated as "still warming up"
  // rather than accepted outright — see _resolveCurrentLocation.
  static const double _acceptableAccuracyMeters = 100;

  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  bool _locatingInProgress = true;
  String? _locationError;
  bool _locationErrorIsServiceDisabled = false;
  bool _locationErrorCanRetryPrompt = false;

  // Separate, non-interactive controller for the small dashboard preview —
  // kept apart from _mapController (used by the expanded modal) so each
  // FlutterMap instance owns exactly one controller for its whole lifetime.
  final MapController _previewMapController = MapController();

  /// Re-fetches notifications on a timer so the bell badge picks up
  /// admin-initiated events (e.g. a short-trip review) that happen
  /// entirely outside this app while the driver is just sitting on the
  /// dashboard — without this, nothing here would learn about them until
  /// some other action happened to call fetchRemote() again. Same cadence
  /// the admin site's own notification bell polls at.
  Timer? _notificationPollTimer;

  // Clustered demand-signal pings (see GET /api/driver/demand-signals and
  // DemandSignal's doc comment in schema.prisma) — where passengers have
  // tapped "Request a ride here" recently, grouped into map-cell clusters
  // the same way admin's Passenger Live Map groups them, so a driver sees
  // the same clusters admin does from the same underlying data.
  List<_WaitingStop> _demandStops = [];
  Timer? _demandPollTimer;

  // An admin can approve/reject this driver's license at any moment while
  // they're just sitting on this screen (not just when they happen to
  // visit Settings) — polled the same way notifications are, so the
  // "not verified yet" note and the sidebar badge don't go stale.
  Timer? _licenseStatusPollTimer;

  // A cold-start GPS fix commonly takes longer than the 3 attempts inside
  // _resolveCurrentLocation are willing to wait for (radio still warming
  // up) — without this, a driver who opens the dashboard right after
  // installing/rebooting sees a stale "could not get your location" error
  // (and the map sitting on _fallbackLocation) indefinitely, with no
  // indication anything will ever change unless they notice and tap
  // retry themselves. This silently retries a few more times in the
  // background and self-corrects the moment a real fix comes through.
  // Only for the generic timeout/unknown-error case — permission-denied
  // and services-disabled failures need the driver to actually do
  // something, so retrying automatically wouldn't help there.
  Timer? _autoLocationRetryTimer;
  int _autoLocationRetryCount = 0;
  static const int _maxAutoLocationRetries = 4;

  @override
  void initState() {
    super.initState();
    _resolveCurrentLocation();
    // So the bell badge reflects real unread notifications right away,
    // not just after the bell is tapped.
    DriverNotificationsScreen.fetchRemote().then((_) {
      if (mounted) setState(() {});
    });
    _fetchTodayStats();
    _refreshLicenseStatus();
    _restoreActiveTrip();
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      DriverNotificationsScreen.fetchRemote().then((_) {
        if (mounted) setState(() {});
      });
    });
    _licenseStatusPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isCovered) return;
      _refreshLicenseStatus();
    });
    _fetchDemandSignals();
    _demandPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isCovered) return;
      _fetchDemandSignals();
    });
  }

  /// True while the Start Trip or live trip screen is on top of this one —
  /// both poll the same demand signals themselves, so polling from underneath
  /// just doubled the requests and battery use. (Not tied to "any screen is on
  /// top": the expanded-map sheet is also a route and needs live data.)
  bool _tripScreenOpen = false;

  bool get _isCovered => !mounted || _tripScreenOpen;

  /// Pulls raw demand-signal pings from the last hour and clusters them
  /// into map cells (~100m) client-side — the driver-side twin of admin's
  /// own clustering in LiveMap.tsx, so both surfaces agree on where
  /// passengers actually are from the same raw rows. Deliberately shows
  /// nothing at all until this driver has actually started a trip — before
  /// that there's no route to filter by, and "waiting passengers" isn't
  /// actionable for a driver who isn't running a route right now anyway
  /// (contrast with DriverStartTripScreen, which shows this on purpose as
  /// a preview of what a route looks like before committing to it).
  Future<void> _fetchDemandSignals() async {
    if (_activeTrip == null) {
      if (_demandStops.isNotEmpty) setState(() => _demandStops = []);
      return;
    }
    final token = DriverSession.instance.authToken;
    if (token == null) return;
    try {
      // Filtered to this trip's route — someone waiting for the opposite
      // direction shouldn't show up here (see the route param's doc
      // comment in driver.ts).
      final route = _activeTrip!.route;
      final response = await ApiClient.get(
        '/api/driver/demand-signals?route=${Uri.encodeQueryComponent(route)}',
        token: token,
      );
      if (!mounted) return;
      final raw = response['signals'] as List<dynamic>? ?? const [];
      final pings = raw.map((s) {
        final map = s as Map<String, dynamic>;
        return _DemandPing(
          point: LatLng(
            (map['lat'] as num).toDouble(),
            (map['lng'] as num).toDouble(),
          ),
          partySize: (map['partySize'] as num?)?.toInt() ?? 1,
        );
      }).toList();
      setState(() => _demandStops = _clusterDemandSignals(pings));
    } catch (_) {
      // Best-effort — the map just keeps showing whatever it last had.
    }
  }

  /// Picks a trip back up that is still running but isn't on screen — the app
  /// was closed or killed mid-trip, or this dashboard was rebuilt. The trip
  /// keeps running on the backend either way, and it only stays visible to
  /// commuters while the driver's phone keeps reporting its position, so
  /// re-attaching (and resuming those reports) is what keeps the jeepney on
  /// the map. Best-effort; a failure just leaves the dashboard as it was.
  Future<void> _restoreActiveTrip() async {
    final tracker = DriverActiveTrip.instance;

    // Tracking survived in this process (dashboard rebuilt) — just reflect it.
    if (tracker.isActive) {
      if (!mounted) return;
      setState(
        () => _activeTrip = _ActiveTrip(
          route: tracker.route ?? '—',
          plateNumber:
              tracker.plateNumber ?? DriverSession.instance.plateNumber ?? '—',
          startTime: tracker.startTime ?? DateTime.now(),
        ),
      );
      _fetchDemandSignals();
      return;
    }

    final token = DriverSession.instance.authToken;
    if (token == null) return;
    try {
      final response = await ApiClient.get(
        '/api/driver/trips/active',
        token: token,
      );
      final trip = response['trip'] as Map<String, dynamic>?;
      if (trip == null || !mounted) return;
      // A trip was started from this screen while the request was in flight.
      if (tracker.isActive || _activeTrip != null) return;

      final route = trip['route'] as String?;
      final plate = DriverSession.instance.plateNumber ?? '—';
      final startedAt =
          DateTime.tryParse(trip['startedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now();
      final lat = (trip['currentLat'] as num?)?.toDouble();
      final lng = (trip['currentLng'] as num?)?.toDouble();

      await tracker.adoptExisting(
        backendTripId: trip['id'] as String,
        route: route,
        plateNumber: plate,
        startTime: startedAt,
        lastKnownLocation: lat != null && lng != null ? LatLng(lat, lng) : null,
      );
      if (!mounted) return;
      setState(
        () => _activeTrip = _ActiveTrip(
          route: route ?? '—',
          plateNumber: plate,
          startTime: startedAt,
        ),
      );
      _fetchDemandSignals();
    } catch (_) {
      // Best-effort — no trip banner if this fails.
    }
  }

  /// Best-effort pull of today's trip count / net income from the backend —
  /// authoritative across devices, unlike the local stores this falls
  /// back to. Never blocks the UI; a failure just leaves the fallback in
  /// place.
  Future<void> _fetchTodayStats() async {
    final token = DriverSession.instance.authToken;
    if (token == null) return;
    try {
      final response = await ApiClient.get(
        '/api/driver/today-stats',
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _tripsTodayRemote = response['tripsToday'] as int?;
        final netIncome = response['netIncomeToday'];
        _netIncomeTodayRemote = netIncome == null
            ? null
            : (netIncome as num).toDouble();
      });
    } catch (_) {
      // Keep whatever's currently shown (local fallback).
    }
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _licenseStatusPollTimer?.cancel();
    _demandPollTimer?.cancel();
    _autoLocationRetryTimer?.cancel();
    _mapController.dispose();
    _previewMapController.dispose();
    super.dispose();
  }

  Future<void> _resolveCurrentLocation({bool showErrors = false}) async {
    setState(() {
      _locatingInProgress = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const _LocationFailure(
          'Location services are off. Tap to turn them on.',
          isServiceDisabled: true,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Still just "denied", not "denied forever" — the OS will show
          // the Allow/Deny dialog again on the next attempt, so this is
          // worth a retry button rather than sending the user to Settings.
          throw const _LocationFailure(
            'Location permission was denied.',
            canRetryPrompt: true,
          );
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure(
          'Location permission denied. Tap to open app settings.',
          isServiceDisabled: false,
        );
      }

      // A fresh install's very first fix is the most likely to time out
      // (GPS radio hasn't warmed up yet) — one retry here is the
      // difference between "first open lands on the fallback location"
      // and just taking a couple seconds longer.
      //
      // The fused provider can also *succeed* immediately with a coarse
      // network/cell-tower fix — easily off by kilometers — before GPS has
      // had time to lock in, which is what actually makes the map look
      // like it opened to someone else's location rather than a timeout
      // or error. So a fix that comes back worse than
      // [_acceptableAccuracyMeters] still gets accepted as a last resort,
      // but only after retrying for a tighter one first.
      Position? position;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final candidate = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12 + attempt * 4),
            ),
          );
          position = candidate;
          if (candidate.accuracy <= _acceptableAccuracyMeters || attempt == 2) break;
          await Future.delayed(const Duration(seconds: 1));
        } catch (_) {
          if (attempt == 2) rethrow;
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (!mounted) return;
      final resolved = LatLng(position!.latitude, position.longitude);
      _autoLocationRetryTimer?.cancel();
      _autoLocationRetryCount = 0;
      setState(() {
        _currentLocation = resolved;
        _locatingInProgress = false;
      });
      _mapController.move(resolved, 16);
    } on _LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _currentLocation ??= _fallbackLocation;
        _locatingInProgress = false;
        _locationError = failure.message;
        _locationErrorIsServiceDisabled = failure.isServiceDisabled;
        _locationErrorCanRetryPrompt = failure.canRetryPrompt;
      });
      if (showErrors) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentLocation ??= _fallbackLocation;
        _locatingInProgress = false;
        _locationError = 'Could not get your current location.';
        _locationErrorIsServiceDisabled = false;
        _locationErrorCanRetryPrompt = false;
      });
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your current location.')),
        );
      }
      _scheduleAutoLocationRetry();
    }
  }

  void _scheduleAutoLocationRetry() {
    if (_autoLocationRetryCount >= _maxAutoLocationRetries) return;
    _autoLocationRetryCount++;
    _autoLocationRetryTimer?.cancel();
    _autoLocationRetryTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _resolveCurrentLocation();
    });
  }

  void _recenterMap() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
    }
    _resolveCurrentLocation(showErrors: true);
  }

  // Tapping a waiting-passenger pin on the expanded live map shows just
  // distance + ETA to that cluster — no Navigate/Accept/Track/Request
  // action, per the spec this feature was built from (drivers shouldn't be
  // interacting with the phone beyond a glance). Uses the same real-routed
  // GET /driver/route-to-passenger the trip-in-progress screen's own
  // waiting-stop pins call.
  void _showPassengerInfo(_WaitingStop stop) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PassengerInfoSheet(
        origin: _currentLocation ?? _fallbackLocation,
        destination: stop.point,
        count: stop.count,
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showLogoutConfirmationSheet(context);
    if (!confirmed || !mounted) return;

    // SigningOutScreen does the actual sign-out work itself (see its own
    // doc comment) — trip history and notifications persist across
    // logout, same as the rest of the account data
    // DriverSession.signOut() already keeps on disk.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SigningOutScreen(
          signOut: DriverSession.instance.signOut,
          destinationBuilder: (_) => const DriverLoginScreen(),
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push<DriverSettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSettingsScreen(
          initialFullName: _driverName,
          initialMobileNumber: DriverSession.instance.mobileNumber,
        ),
      ),
    );

    // Refreshed unconditionally, even if result is null (e.g. the driver
    // only visited Settings -> License Number and came straight back
    // without saving a profile change) — otherwise the "not verified yet"
    // note and the sidebar badge would keep showing a stale status after
    // a driver submits/gets reviewed.
    await _refreshLicenseStatus();

    if (result == null) return;

    setState(() {
      if (result.fullName.isNotEmpty) _driverName = result.fullName;
      _photoUrl = result.photoUrl;
    });
  }

  Future<void> _refreshLicenseStatus() async {
    await DriverSession.instance.refreshLicenseStatus();
    if (mounted)
      setState(
        () => _licenseStatus = DriverSession.instance.licenseVerificationStatus,
      );
  }

  void _openQrCode() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverQrCodeScreen()),
    );
  }

  // Fetches first so mark-read covers anything that arrived since the
  // last fetch, then marks everything read (clearing the bell badge)
  // right away, rather than waiting for the feed screen to fully open.
  Future<void> _openNotifications() async {
    await DriverNotificationsScreen.fetchRemote();
    await DriverNotificationsScreen.markAllRead();
    if (!mounted) return;
    setState(() {});
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverNotificationsScreen()),
    );
  }

  Future<void> _openTripHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
    );
    // Today's Trips comes from the backend (see _fetchTodayStats) — re-pull
    // it once the driver's back, in case anything changed while this
    // screen was open.
    _fetchTodayStats();
  }

  Future<void> _openDailyOperations() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverDailyOperationsScreen()),
    );
    // The Earnings stat card reads DriverOperationsLog.todayEntry live, so
    // just refresh the build once the driver's back from logging today's
    // numbers — and re-pull the backend figure too, since that's what the
    // card prefers when available.
    if (mounted) setState(() {});
    _fetchTodayStats();
  }

  void _openWeeklyAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverWeeklyAnalyticsScreen()),
    );
  }

  void _openMonthlyAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DriverMonthlyAnalyticsScreen()),
    );
  }

  // ===================================================================
  // START / END TRIP
  // ===================================================================

  Future<void> _handleStartTrip() async {
    if (_licenseStatus != 'APPROVED') {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('License Not Verified'),
          content: Text(switch (_licenseStatus) {
            'PENDING' =>
              "Your license is still being reviewed by an admin. You'll be able to start a trip once it's verified.",
            'REJECTED' =>
              "Your license submission was rejected, so you can't start a trip yet. Go to Settings > License Number to submit clearer photos.",
            _ =>
              "You need to submit your license for verification before you can start a trip. Go to Settings > License Number to upload it.",
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
      return;
    }

    _tripScreenOpen = true;
    final result = await Navigator.push<DriverStartTripResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverStartTripScreen(
          currentLocation: _currentLocation ?? _fallbackLocation,
          hasRealFix: _currentLocation != null && _locationError == null,
        ),
      ),
    );
    _tripScreenOpen = false;

    if (result == null || !mounted) return;

    final trip = _ActiveTrip(
      route: result.route,
      plateNumber: result.plateNumber,
      startTime: DriverActiveTrip.instance.startTime ?? DateTime.now(),
    );
    setState(() => _activeTrip = trip);
    _fetchDemandSignals();

    // Start Trip immediately hands off to the dedicated live-tracking
    // screen — the vehicle marker actually moves there, and that's also
    // the only place "End Trip" lives once a trip is underway. That
    // screen is what actually calls the backend's /trips/start (see
    // DriverTripInProgressScreen._initializeTrip), which is what
    // triggers the real "Trip Started" notification — no local push
    // needed here anymore.
    await _openTripInProgress(trip);
  }

  Future<void> _openTripInProgress(_ActiveTrip trip) async {
    _tripScreenOpen = true;
    final ended = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverTripInProgressScreen(
          route: trip.route,
          plateNumber: trip.plateNumber,
          startTime: trip.startTime,
          initialLocation: _currentLocation ?? _fallbackLocation,
          hasRealFix: _currentLocation != null && _locationError == null,
        ),
      ),
    );

    _tripScreenOpen = false;
    if (!mounted) return;
    if (ended == true) {
      // The backend already has this trip (POST /trips/:id/end already
      // ran) — re-pull today's-stats so the Today's Trips card reflects
      // it, and clear the active-trip state.
      setState(() => _activeTrip = null);
      _fetchTodayStats();
      _fetchDemandSignals();
      // Ending the trip also fired a "Trip Completed" notification
      // server-side (see driver.ts's /trips/:id/end) — without this, the
      // bell badge stays stale until the driver opens Notifications
      // manually (which does its own fresh fetch) or logs out and back in.
      DriverNotificationsScreen.fetchRemote().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// "₱1,250", or "-₱120" when today's expenses exceeded what came in.
  String _formatPesoSigned(double amount) {
    final rounded = amount.round();
    final digits = rounded.abs().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${rounded < 0 ? '-' : ''}₱$digits';
  }

  String _timeOfDay(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  void _openFullMapRoute() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildExpandedMapModal(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No PopScope wrapper here on purpose — driver login now reaches this
    // screen via pushAndRemoveUntil, so it's already the root route and
    // there's nothing left underneath for the back button to reveal.
    // Logout only ever happens through the explicit confirm sheet in the
    // drawer.
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF9FAFB),

      drawer: DriverMenuDrawer(
        driverName: _driverName,
        driverId: _driverId,
        photoUrl: _photoUrl,
        licenseVerificationStatus: _licenseStatus,
        onSettingsTap: _openSettings,
        onQrCodeTap: _openQrCode,
        onTripHistoryTap: _openTripHistory,
        onLogoutTap: _handleLogout,
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // A floating pill instead of a circle — icon and label side by
      // side read faster at a glance than stacked text inside a small
      // circle, and there's room for genuinely readable text size
      // (see the 2026-08-21 design audit).
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: _activeTrip == null ? AppColors.primary : AppColors.logoBlue,
          borderRadius: BorderRadius.circular(32),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: _activeTrip == null
                ? _handleStartTrip
                : () => _openTripInProgress(_activeTrip!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _activeTrip == null
                        ? Icons.directions_bus_filled_rounded
                        : Icons.map_rounded,
                    color: _activeTrip == null
                        ? AppColors.onPrimary
                        : Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _activeTrip == null ? 'Start Trip' : 'View Trip',
                    style: TextStyle(
                      color: _activeTrip == null
                          ? AppColors.onPrimary
                          : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar — round white icon buttons, matching the
              // commuter dashboard's floating menu/notifications pair.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundIconButton(
                    icon: Icons.menu,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Sans-Serif',
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
                  _RoundIconButton(
                    icon: Icons.notifications_none_rounded,
                    badgeCount: DriverNotificationsScreen.unreadCount,
                    onTap: _openNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Driver Profile Header Card — same yellow gradient banner
              // convention used across the commuter side.
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, Color(0xFFFFDE7A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Background texture — a faint jeepney watermark tucked
                      // into the bottom-right corner, low-opacity so it reads
                      // as depth/dimension rather than competing with the
                      // avatar/name/status content on top.
                      Positioned(
                        bottom: -6,
                        right: -6,
                        child: Transform.rotate(
                          angle: -0.1,
                          child: Icon(
                            Icons.directions_bus_filled_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            AppAvatar(
                              // 52px avatar + 3px white ring each side,
                              // matching the original CircleAvatar(radius:
                              // 26) inside its 3px padding wrapper.
                              size: 58,
                              photoUrl: _photoUrl,
                              border: Border.all(color: Colors.white, width: 3),
                              fallback: const Icon(
                                Icons.person,
                                size: 32,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _driverName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Driver ID: $_driverId',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Online/Offline status — reflects whether a trip is
                            // actually active, no longer a manual toggle.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isOnline
                                      ? Colors.green
                                      : AppColors.errorRed,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 4,
                                    backgroundColor: _isOnline
                                        ? Colors.green
                                        : AppColors.errorRed,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isOnline ? 'On Trip' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _isOnline
                                          ? Colors.green.shade800
                                          : AppColors.errorRed,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (_activeTrip != null) ...[
                _buildActiveTripCard(),
                const SizedBox(height: 16),
              ],

              // Live Map Preview — a real, pannable OpenStreetMap view (via
              // flutter_map), not a painted placeholder.
              GestureDetector(
                onTap: _openFullMapRoute,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Where Passengers Are Waiting',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 4,
                                  backgroundColor: _locatingInProgress
                                      ? Colors.orange
                                      : (_locationError != null
                                            ? AppColors.logoRed
                                            : Colors.green),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _locatingInProgress
                                      ? 'Locating…'
                                      : (_locationError != null
                                            ? 'Location error'
                                            : 'Live'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _locatingInProgress
                                        ? Colors.orange.shade800
                                        : (_locationError != null
                                              ? AppColors.logoRed
                                              : Colors.green),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: Stack(
                            children: [
                              IgnorePointer(
                                child: _buildDriverMap(
                                  mapController: _previewMapController,
                                  interactive: false,
                                ),
                              ),
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _activeTrip != null
                                        ? 'Route: ${_activeTrip!.route}'
                                        : 'Tap to view live map',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.logoBlue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.zoom_out_map,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Tap to Expand',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Dynamic 2-Card Stats Row (Today's Trips & Earnings) — now
              // driven by persisted trip history / operations log, not
              // fake constructor defaults or session-only counters.
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.directions_bus_filled,
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: AppColors.logoBlue,
                      title: "Today's Trips",
                      value: '${_tripsTodayRemote ?? 0}',
                      subtitle: 'Trips',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.account_balance_wallet,
                      iconBg: AppColors.qrTileBg,
                      iconColor: AppColors.qrIconColor,
                      // Net, not gross: earnings minus the fuel/other
                      // expenses logged today — so a day that cost more
                      // than it brought in shows as a loss, not as revenue.
                      title: 'Net Income',
                      value: _formatPesoSigned(
                        _netIncomeTodayRemote ??
                            DriverOperationsLog.todayEntry?.netIncome ??
                            0,
                      ),
                      subtitle: 'Today',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildNavigationCard(
                icon: Icons.local_gas_station,
                iconBg: AppColors.settingsTileBg,
                iconColor: AppColors.settingsIconColor,
                title: 'Daily Operations Dashboard',
                subtitle:
                    'Check if your revenue is higher than your gas expense',
                onTap: _openDailyOperations,
              ),
              const SizedBox(height: 12),

              _buildNavigationCard(
                icon: Icons.bar_chart_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: AppColors.logoBlue,
                title: 'Weekly Analytics Report',
                subtitle: 'See your earnings, expenses, and net income trend',
                onTap: _openWeeklyAnalytics,
              ),
              const SizedBox(height: 12),

              _buildNavigationCard(
                icon: Icons.insights_rounded,
                iconBg: AppColors.qrTileBg,
                iconColor: AppColors.qrIconColor,
                title: 'Monthly Analytics & Performance',
                subtitle: 'Review this month\'s totals and your best day',
                onTap: _openMonthlyAnalytics,
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ===================================================================
  // ACTIVE TRIP CARD — route, plate/start time, live passenger stepper.
  // ===================================================================

  Widget _buildActiveTripCard() {
    final trip = _activeTrip!;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openTripInProgress(trip),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.logoBlue.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppColors.logoBlue,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.directions_bus_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trip.route,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 3, backgroundColor: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${trip.plateNumber} · Started ${_timeOfDay(trip.startTime)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.map_rounded, size: 12, color: AppColors.logoBlue),
                SizedBox(width: 4),
                Text(
                  'Tap to view live map and end trip',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.logoBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Stat Card Widget Builder
  Widget _buildStatCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Navigation Option Builder
  Widget _buildNavigationCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.logoBlue,
            ),
          ],
        ),
      ),
    );
  }

  /// Where the small preview map was last centered — see _buildDriverMap.
  LatLng? _lastPreviewCenter;

  /// The dashboard's map (small preview and expanded modal). While a trip is
  /// running it shows the trip's own live position — kept current by
  /// DriverActiveTrip, not the one-time fix taken when this screen opened —
  /// and the route being driven; otherwise the driver's own position.
  Widget _buildDriverMap({
    required MapController mapController,
    required bool interactive,
    VoidCallback? onRecenter,
    ValueChanged<_WaitingStop>? onTapWaitingStop,
  }) {
    final tracker = DriverActiveTrip.instance;
    return ValueListenableBuilder<int>(
      valueListenable: tracker.updateNotifier,
      builder: (context, _, _) {
        final onTrip = _activeTrip != null && tracker.isActive;
        final tripLocation = onTrip ? tracker.currentLocation : null;

        // FlutterMap only honors initialCenter once, at first build — so the
        // non-interactive preview (which nobody can pan) would stay on
        // wherever it first opened (the fallback area, before the first
        // fix) instead of showing the driver. Re-center it whenever the
        // position it should show changes.
        if (!interactive) {
          final shown = tripLocation ?? _currentLocation;
          if (shown != null && shown != _lastPreviewCenter) {
            _lastPreviewCenter = shown;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              try {
                mapController.move(shown, 15);
              } catch (_) {
                // Preview not laid out yet — it opens on this point anyway.
              }
            });
          }
        }

        return _DriverLiveMap(
          mapController: mapController,
          currentLocation:
              tripLocation ?? _currentLocation ?? _fallbackLocation,
          hasRealFix: tripLocation != null
              ? tracker.hasRealFix
              : (_currentLocation != null && _locationError == null),
          onRecenter: onRecenter,
          interactive: interactive,
          waitingStops: _demandStops,
          onTapWaitingStop: onTapWaitingStop,
          routePoints: _activeTrip == null
              ? null
              : RoutePath.forRoute(_activeTrip!.route),
        );
      },
    );
  }

  // Expanded, fully interactive live map modal.
  Widget _buildExpandedMapModal(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeTrip != null
                          ? _activeTrip!.route
                          : 'Where Passengers Are Waiting',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: _locationError == null
                          ? null
                          : (_locationErrorCanRetryPrompt
                                // Still just "denied", not "denied
                                // forever" — asking again actually shows
                                // the OS Allow/Deny dialog, so retry
                                // before sending the driver to Settings.
                                ? () => _resolveCurrentLocation(showErrors: true)
                                : () => openRelevantLocationSettings(
                                    isServiceDisabled:
                                        _locationErrorIsServiceDisabled,
                                  )),
                      child: Text(
                        _locationError ??
                            'Your position and nearby waiting passengers',
                        style: TextStyle(
                          fontSize: 10,
                          color: _locationError == null
                              ? AppColors.textSecondary
                              : AppColors.logoRed,
                          decoration: _locationError == null
                              ? TextDecoration.none
                              : TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildDriverMap(
              mapController: _mapController,
              interactive: true,
              onRecenter: _recenterMap,
              onTapWaitingStop: _showPassengerInfo,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFailure {
  final String message;

  /// Whether tapping the resulting banner should open the device's
  /// Location Services settings (true) or this app's own permission
  /// page (false) — see [openRelevantLocationSettings].
  final bool isServiceDisabled;

  /// Whether asking again would actually show the OS "Allow Location?"
  /// dialog — true only for a plain first-time denial. Once the OS has
  /// moved to "denied forever" (or location services are off entirely),
  /// calling requestPermission() again is a silent no-op with no dialog;
  /// the only real fix at that point is the Settings app, not a retry.
  final bool canRetryPrompt;

  const _LocationFailure(
    this.message, {
    this.isServiceDisabled = false,
    this.canRetryPrompt = false,
  });
}

// Round white icon button — same look as the commuter dashboard's floating
// menu/notifications buttons.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, size: 24, color: Colors.black87),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFE23F3F),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 9 ? '9+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// REAL LIVE MAP — OpenStreetMap tiles via flutter_map, same pattern as the
// commuter dashboard's map. `interactive: false` renders a static preview
// (used in the small dashboard card); the expanded modal gets full
// pan/zoom plus a recenter button.
// ===========================================================================

class _DriverLiveMap extends StatelessWidget {
  final MapController mapController;
  final LatLng currentLocation;
  final bool hasRealFix;
  final VoidCallback? onRecenter;
  final bool interactive;

  /// Clustered demand-signal pings — see
  /// _DriverDashboardScreenState._fetchDemandSignals.
  final List<_WaitingStop> waitingStops;

  /// Tapping a waiting-passenger pin — null (no tap affordance) on the
  /// small dashboard preview, which is wrapped in an IgnorePointer anyway;
  /// wired up only on the expanded, fully interactive map.
  final ValueChanged<_WaitingStop>? onTapWaitingStop;

  /// The route this driver's active trip is running, origin to destination —
  /// null when no trip is running.
  final List<LatLng>? routePoints;

  const _DriverLiveMap({
    required this.mapController,
    required this.currentLocation,
    required this.hasRealFix,
    this.onRecenter,
    this.interactive = true,
    this.waitingStops = const [],
    this.onTapWaitingStop,
    this.routePoints,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: currentLocation,
            initialZoom: 15,
            minZoom: 3,
            maxZoom: 19,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: MapConfig.tileUrlTemplate,
              userAgentPackageName: 'com.manibel.app',
              maxZoom: 19,
            ),
            if (interactive)
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    MapConfig.attribution,
                    onTap: () {},
                  ),
                ],
              ),
            if (routePoints != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints!,
                    strokeWidth: 4,
                    color: AppColors.primary,
                    borderStrokeWidth: 2,
                    borderColor: AppColors.onPrimary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // Only shown once a real GPS fix comes through — no marker
                // at all (not even a greyed-out one) while sitting on
                // _fallbackLocation, so the map never implies a position
                // that isn't actually real.
                if (hasRealFix)
                  Marker(
                    point: currentLocation,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.logoBlue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.logoBlue.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.directions_bus_filled_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                for (final stop in waitingStops)
                  Marker(
                    point: stop.point,
                    width: 34,
                    height: 34,
                    child: onTapWaitingStop == null
                        ? _WaitingStopPin(count: stop.count)
                        : GestureDetector(
                            onTap: () => onTapWaitingStop!(stop),
                            child: _WaitingStopPin(count: stop.count),
                          ),
                  ),
              ],
            ),
          ],
        ),
        if (interactive && onRecenter != null)
          Positioned(
            right: 12,
            bottom: 20,
            child: _RoundIconButton(
              icon: Icons.my_location_rounded,
              onTap: onRecenter!,
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// DEMAND SIGNALS — clustered "passengers waiting here" pings. Dart port of
// admin's clusterDemandSignals() (see admin/src/components/LiveMap.tsx),
// kept in sync deliberately: same ~100m grid-cell bucketing, so a driver
// and admin looking at the same raw rows see the same clusters.
// ===========================================================================

class _WaitingStop {
  final LatLng point;
  final int count;
  const _WaitingStop({required this.point, required this.count});
}

/// One raw demand-signal ping — position plus how many people that
/// commuter is requesting a ride for (see DemandSignal.partySize's doc
/// comment in schema.prisma).
class _DemandPing {
  final LatLng point;
  final int partySize;
  const _DemandPing({required this.point, required this.partySize});
}

class _DemandBucket {
  double latSum = 0;
  double lngSum = 0;
  int pingCount = 0;
  int partySizeSum = 0;
}

/// Buckets raw pings into ~0.001°-square cells (~100m at this latitude)
/// and collapses each cell into one marker centered on its pings' average
/// position — same reasoning as a map heatmap: individual pings are noisy
/// and privacy-sensitive on their own (see DemandSignal's doc comment in
/// schema.prisma), a cluster is a stable, honest "demand is around here."
/// The marker's displayed count is the *sum* of party sizes, not the
/// number of pings — a group of 4 booked from one account reads as 4
/// waiting, not 1. Position averaging still uses ping count, not party
/// size, since that's about geometric centering, not headcount.
List<_WaitingStop> _clusterDemandSignals(List<_DemandPing> pings) {
  const cellSize = 0.001;
  final buckets = <String, _DemandBucket>{};

  for (final ping in pings) {
    final cellLat = (ping.point.latitude / cellSize).floor();
    final cellLng = (ping.point.longitude / cellSize).floor();
    final key = '$cellLat:$cellLng';
    final bucket = buckets.putIfAbsent(key, () => _DemandBucket());
    bucket.latSum += ping.point.latitude;
    bucket.lngSum += ping.point.longitude;
    bucket.pingCount += 1;
    bucket.partySizeSum += ping.partySize;
  }

  return buckets.values
      .map(
        (b) => _WaitingStop(
          point: LatLng(b.latSum / b.pingCount, b.lngSum / b.pingCount),
          count: b.partySizeSum,
        ),
      )
      .toList();
}

/// A passenger-icon pin for a demand-signal cluster — red when several
/// pings are stacked in one cell (worth prioritizing), yellow (brand color)
/// for a lone ping, so a driver can tell "busy stop" from "one person
/// waiting" at a glance. The count badge always shows how many.
class _WaitingStopPin extends StatelessWidget {
  final int count;
  const _WaitingStopPin({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = count > 1 ? const Color(0xFFE23F3F) : AppColors.primary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.person_rounded,
            size: 17,
            color: Colors.white,
          ),
        ),
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 1.2),
            ),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
