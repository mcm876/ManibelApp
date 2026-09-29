import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/map_config.dart';
import '../../../core/constants/route_path.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/live_location.dart';
import '../../../core/utils/location_settings.dart';
import '../widgets/passenger_info_sheet.dart';

/// ---------------------------------------------------------------------------
/// ACTIVE TRIP CONTROLLER
/// ---------------------------------------------------------------------------
///
/// This controller owns the active trip instead of the trip screen.
///
/// That means:
/// - Leaving the trip screen does NOT end the trip.
/// - GPS tracking continues while navigating around the app.
/// - The Dashboard can check DriverActiveTrip.isActive.
/// - The driver can return to the trip later.
/// - Only "End Trip" stops the active trip.
///
/// This is an in-memory controller. If the app is completely killed,
/// the active trip will not survive the process being terminated.
/// ---------------------------------------------------------------------------

class DriverActiveTrip {
  DriverActiveTrip._();

  static final DriverActiveTrip instance = DriverActiveTrip._();

  StreamSubscription<Position>? _positionSubscription;
  Timer? _elapsedTimer;

  /// Re-sends the current position on a fixed beat while a trip is active,
  /// whether or not the jeepney has moved. The position stream below only
  /// fires when the driver moves a few meters, so a jeepney waiting at the
  /// terminal — exactly where a trip usually starts — would otherwise go
  /// completely silent, and the backend hides a trip whose last ping is more
  /// than 5 minutes old from commuters (see NEARBY_STALENESS_MS in
  /// commuter.ts). That is what made a started, still-active jeepney vanish
  /// from the booking map.
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 10);

  String? route;
  String? plateNumber;
  DateTime? startTime;

  LatLng? currentLocation;

  bool isActive = false;
  bool hasRealFix = false;

  /// Set when live tracking can't start or drops out mid-trip (location
  /// services turned off, permission revoked) — null while tracking is
  /// healthy. Previously this failed completely silently: the driver's
  /// live position would just stop updating on the admin map with no
  /// indication anything was wrong. See [isLocationErrorServiceDisabled]
  /// for which settings screen fixes it.
  String? locationError;
  bool isLocationErrorServiceDisabled = false;

  /// The backend Trip this local trip is mirrored to — null if the
  /// start-trip call failed (bad connectivity shouldn't block a driver
  /// from working locally) or hasn't happened yet. Location pings and
  /// the end-trip call are no-ops without one; there's simply nothing on
  /// the backend to update in that case.
  String? _backendTripId;
  DateTime? _lastLocationPingAt;

  /// The real backend Trip id this active trip is mirrored to, if the
  /// start-trip call succeeded — read this before calling [endTrip], which
  /// clears it. Null means there's nothing on the backend to reference
  /// (e.g. the start call failed while offline).
  String? get backendTripId => _backendTripId;

  final ValueNotifier<int> updateNotifier = ValueNotifier<int>(0);

  Duration get elapsed {
    if (startTime == null) {
      return Duration.zero;
    }

    return DateTime.now().difference(startTime!);
  }

  /// Start a new trip.
  ///
  /// [initialLocationIsReal] says whether [initialLocation] is an actual GPS
  /// fix or just the map's fallback center — only a real one is ever sent to
  /// the backend, so commuters are never shown a jeepney at a made-up place.
  Future<void> startTrip({
    required String route,
    required String plateNumber,
    required DateTime startTime,
    required LatLng initialLocation,
    bool initialLocationIsReal = false,
  }) async {
    // If a trip is already active, don't start another one.
    if (isActive) {
      return;
    }

    this.route = route;
    this.plateNumber = plateNumber;
    this.startTime = startTime;

    currentLocation = initialLocation;
    hasRealFix = initialLocationIsReal;
    isActive = true;
    _backendTripId = null;
    _lastLocationPingAt = null;

    updateNotifier.value++;

    _startElapsedTimer();
    await _startLocationTracking();

    // Best-effort — a failed call here shouldn't stop the driver from
    // working locally; the heartbeat below keeps retrying it, so the trip
    // still reaches the admin live map and commuters' booking map as soon as
    // connectivity is back (see _backendTripId's doc comment).
    await _registerWithBackend();
    _startHeartbeat();
  }

  /// Re-attaches to a trip that is still ACTIVE on the backend but no longer
  /// exists in this process — the app was closed or killed mid-trip. Without
  /// this the trip keeps running server-side with nobody pinging it, so its
  /// location goes stale and the jeepney drops off commuters' maps even though
  /// the driver never ended the trip.
  Future<void> adoptExisting({
    required String backendTripId,
    required String? route,
    required String plateNumber,
    required DateTime startTime,
    LatLng? lastKnownLocation,
  }) async {
    if (isActive) return;

    this.route = route;
    this.plateNumber = plateNumber;
    this.startTime = startTime;

    // The backend's last position may be minutes old — shown for orientation
    // only (grey marker) and never re-sent; the first live fix replaces it.
    currentLocation = lastKnownLocation;
    hasRealFix = false;
    isActive = true;
    _backendTripId = backendTripId;
    _lastLocationPingAt = null;

    updateNotifier.value++;

    _startElapsedTimer();
    await _startLocationTracking();
    _startHeartbeat();
  }

  /// Creates (or, if one already exists, re-fetches) this driver's backend
  /// Trip. Seeds it with the current position when that is a real GPS fix, so
  /// the jeepney is on commuters' maps from the first second instead of only
  /// once it starts moving.
  Future<void> _registerWithBackend() async {
    final here = currentLocation;
    final sendLocation = hasRealFix && here != null;
    try {
      final response = await ApiClient.post('/api/driver/trips/start', {
        'route': route,
        if (sendLocation) 'lat': here.latitude,
        if (sendLocation) 'lng': here.longitude,
      }, token: DriverSession.instance.authToken);
      _backendTripId =
          (response['trip'] as Map<String, dynamic>)['id'] as String?;
      if (sendLocation) _lastLocationPingAt = DateTime.now();
    } catch (_) {
      _backendTripId = null;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeat());
  }

  Future<void> _heartbeat() async {
    if (!isActive) return;

    // The start call never made it (offline at the time) — keep trying.
    if (_backendTripId == null) {
      await _registerWithBackend();
      return;
    }

    final here = currentLocation;
    if (!hasRealFix || here == null) return;

    // A movement ping just went out — no need to double up.
    final last = _lastLocationPingAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return;
    }
    await _sendLocationToBackend(here);
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isActive) return;

      updateNotifier.value++;
    });
  }

  /// Re-attempts starting live tracking after the driver has (hopefully)
  /// fixed whatever [locationError] described — e.g. after tapping the
  /// in-app banner to open Location Settings and returning to the app.
  Future<void> retryLocationTracking() => _startLocationTracking();

  Future<void> _startLocationTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        locationError = 'Location services are off. Tap to turn them on.';
        isLocationErrorServiceDisabled = true;
        updateNotifier.value++;
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        locationError = 'Location permission denied. Tap to open app settings.';
        isLocationErrorServiceDisabled = false;
        updateNotifier.value++;
        return;
      }

      // Prevent duplicate subscriptions.
      await _positionSubscription?.cancel();

      locationError = null;
      updateNotifier.value++;

      _positionSubscription =
          livePositionStream(
            distanceFilterMeters: 3,
            // Keeps position updates flowing while the driver's phone is
            // locked or another app is in front — without this Android stops
            // delivering them shortly after the app leaves the foreground,
            // which silently freezes the jeepney on every commuter's map.
            foregroundNotification: const ForegroundNotificationConfig(
              notificationTitle: 'Trip in progress',
              notificationText:
                  'ManibelaApp is sharing your jeepney\'s live location.',
              notificationChannelName: 'Trip tracking',
              enableWakeLock: true,
              setOngoing: true,
            ),
          ).listen(
            (position) {
              if (!isActive) return;

              currentLocation = LatLng(position.latitude, position.longitude);

              hasRealFix = true;
              locationError = null;

              updateNotifier.value++;
              _pingLocationToBackend(position);
            },
            onError: (_) {
              // The stream itself failed mid-trip (e.g. location services
              // got switched off after tracking had already started) —
              // surface it the same way an initial failure would be, rather
              // than leaving the driver's last-known position silently
              // stale with no explanation.
              locationError = 'Lost your location. Tap to check your settings.';
              isLocationErrorServiceDisabled = true;
              updateNotifier.value++;
            },
          );
    } catch (_) {
      // If live tracking isn't available,
      // the initial location is still retained.
    }
  }

  /// Reports the driver's current position to the backend so the admin
  /// live map and commuters' booking map reflect it — throttled to at most
  /// once per 4 seconds (GPS updates fire far more often than that, and the
  /// map doesn't need finer resolution than "where roughly is this jeepney
  /// now"). Standing still is covered separately by the heartbeat.
  Future<void> _pingLocationToBackend(Position position) async {
    if (_backendTripId == null) return;

    final now = DateTime.now();
    if (_lastLocationPingAt != null &&
        now.difference(_lastLocationPingAt!) < const Duration(seconds: 4)) {
      return;
    }
    await _sendLocationToBackend(LatLng(position.latitude, position.longitude));
  }

  Future<void> _sendLocationToBackend(LatLng point) async {
    final tripId = _backendTripId;
    if (tripId == null) return;
    _lastLocationPingAt = DateTime.now();

    try {
      await ApiClient.patch(
        '/api/driver/trips/$tripId/location',
        {'lat': point.latitude, 'lng': point.longitude},
        token: DriverSession.instance.authToken,
      );
    } catch (_) {
      // Best-effort, same reasoning as startTrip's backend call.
    }
  }

  /// End the current trip.
  ///
  /// This is the ONLY method that should stop the active trip.
  ///
  /// Returns the backend's trip record from the /end response — this is
  /// what carries isShortTrip/flagReason, which only the backend ever
  /// computes (see computeShortTripFlag in driver.ts). Null if there was
  /// no backend trip id to end, or the call failed (best-effort, same as
  /// startTrip) — Trip History reads this trip fresh from the backend on
  /// its own next load, so there's nothing to reconcile here.
  Future<Map<String, dynamic>?> endTrip() async {
    isActive = false;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    Map<String, dynamic>? tripJson;
    if (_backendTripId != null) {
      try {
        final response = await ApiClient.post(
          '/api/driver/trips/$_backendTripId/end',
          {},
          token: DriverSession.instance.authToken,
        );
        tripJson = response['trip'] as Map<String, dynamic>?;
      } catch (_) {
        // Best-effort, same reasoning as startTrip's backend call.
      }
      _backendTripId = null;
    }

    updateNotifier.value++;
    return tripJson;
  }

  /// Reconnect GPS tracking if needed.
  ///
  /// Useful when the driver returns to the trip screen.
  Future<void> resumeTracking() async {
    if (!isActive) return;

    if (_positionSubscription != null) {
      return;
    }

    await _startLocationTracking();
  }

  String get elapsedLabel {
    final duration = elapsed;

    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;

    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');

    if (h > 0) {
      return '${h}h ${mm}m';
    }

    return '$mm:$ss';
  }
}

/// ---------------------------------------------------------------------------
/// DRIVER TRIP IN PROGRESS SCREEN
/// ---------------------------------------------------------------------------

class DriverTripInProgressScreen extends StatefulWidget {
  final String route;
  final String plateNumber;
  final DateTime startTime;
  final LatLng initialLocation;

  /// Whether [initialLocation] is a real GPS fix (vs. the map's fallback
  /// center) — see DriverActiveTrip.startTrip.
  final bool hasRealFix;

  const DriverTripInProgressScreen({
    super.key,
    required this.route,
    required this.plateNumber,
    required this.startTime,
    required this.initialLocation,
    this.hasRealFix = false,
  });

  @override
  State<DriverTripInProgressScreen> createState() =>
      _DriverTripInProgressScreenState();
}

class _DriverTripInProgressScreenState
    extends State<DriverTripInProgressScreen> {
  final MapController _mapController = MapController();

  DriverActiveTrip get _activeTrip => DriverActiveTrip.instance;

  // Keeps the camera on the jeepney as it drives, so the driver never ends up
  // looking at an empty stretch of map while their marker (and the route
  // ahead) moves off-screen. Turns itself off the moment the driver pans the
  // map by hand, and back on with the recenter button.
  bool _followingDriver = true;
  LatLng? _lastFollowedLocation;

  void _recenterOnDriver() {
    final location = _activeTrip.currentLocation ?? widget.initialLocation;
    setState(() => _followingDriver = true);
    _lastFollowedLocation = location;
    try {
      _mapController.move(location, 16);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();

    _initializeTrip();
    _fetchDemandSignals();
    _demandPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchDemandSignals(),
    );
  }

  Future<void> _initializeTrip() async {
    // If this is a brand-new trip, start it.
    if (!_activeTrip.isActive) {
      await _activeTrip.startTrip(
        route: widget.route,
        plateNumber: widget.plateNumber,
        startTime: widget.startTime,
        initialLocation: widget.initialLocation,
        initialLocationIsReal: widget.hasRealFix,
      );
    } else {
      // If the trip is already active,
      // we are simply returning to the trip screen.
      await _activeTrip.resumeTracking();
    }

    if (!mounted) return;

    final location = _activeTrip.currentLocation ?? widget.initialLocation;

    try {
      _mapController.move(location, 16);
    } catch (_) {}
  }

  @override
  void dispose() {
    // IMPORTANT:
    //
    // DO NOT stop the trip here.
    //
    // The trip controller owns the GPS subscription.
    // Therefore navigating back to Dashboard will NOT end the trip.
    _demandPollTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // WAITING STOPS — clustered demand-signal pings (see GET
  // /api/driver/demand-signals and DemandSignal's doc comment in
  // schema.prisma), same real data and clustering as the dashboard's own
  // map — this screen used to show fixed, made-up pins here instead.
  // -------------------------------------------------------------------------

  List<_WaitingStop> _demandStops = [];
  Timer? _demandPollTimer;

  Future<void> _fetchDemandSignals() async {
    final token = DriverSession.instance.authToken;
    if (token == null) return;
    try {
      // Filtered to the route this trip is actually running — someone
      // waiting for the opposite direction shouldn't show up here (see the
      // route param's doc comment in driver.ts).
      final route = _activeTrip.route ?? widget.route;
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

  // Tapping a waiting-passenger pin shows just distance + ETA to that
  // cluster — no Navigate/Accept/Track/Request action, per the spec this
  // feature was built from (drivers shouldn't be interacting with the
  // phone beyond a glance while driving).
  void _showPassengerInfo(_WaitingStop stop, LatLng currentLocation) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PassengerInfoSheet(
        origin: currentLocation,
        destination: stop.point,
        count: stop.count,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // FORMATTING
  // -------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    return '${minutes}m';
  }

  // -------------------------------------------------------------------------
  // BACK TO DASHBOARD
  // -------------------------------------------------------------------------

  void _handleBackToDashboard() {
    // IMPORTANT:
    //
    // We are NOT calling:
    //   _activeTrip.endTrip();
    //
    // We are simply leaving this screen.
    //
    // The active trip controller continues tracking GPS.
    Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------------
  // END TRIP
  // -------------------------------------------------------------------------

  Future<void> _handleEndTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'End this trip?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'You are about to stop broadcasting '
            '${_activeTrip.route ?? widget.route}.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'End Trip',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final now = DateTime.now();

    final startTime = _activeTrip.startTime ?? widget.startTime;

    final route = _activeTrip.route ?? widget.route;

    final plateNumber = _activeTrip.plateNumber ?? widget.plateNumber;

    final durationLabel = _formatDuration(now.difference(startTime));

    // Stop the active trip — this is also what tells the backend the trip
    // ended, which is what triggers the real "Trip Completed" notification
    // (see DriverNotificationsScreen.fetchRemote(), polled elsewhere) — no
    // local notification needed here anymore. Trip History reads this trip
    // straight from the backend on its own next load, so nothing needs to
    // be recorded locally either.
    await _activeTrip.endTrip();

    if (!mounted) return;

    // Show completed dialog.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return _TripCompletedDialog(
          route: route,
          plateNumber: plateNumber,
          duration: durationLabel,
        );
      },
    );

    if (!mounted) return;

    // Now that the trip has actually ended,
    // return to Dashboard.
    Navigator.of(context).pop(true);
  }

  // -------------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _activeTrip.updateNotifier,
      builder: (context, _, __) {
        final currentLocation =
            _activeTrip.currentLocation ?? widget.initialLocation;

        final route = _activeTrip.route ?? widget.route;

        final plateNumber = _activeTrip.plateNumber ?? widget.plateNumber;

        // The route this trip is running — the one line the driver is meant
        // to follow, in the direction they picked (Quiapo – Pasig is the
        // Pasig – Quiapo path in reverse; see RoutePath).
        final routePoints = RoutePath.forRoute(route);

        if (_followingDriver &&
            _activeTrip.hasRealFix &&
            currentLocation != _lastFollowedLocation) {
          _lastFollowedLocation = currentLocation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_followingDriver) return;
            try {
              _mapController.move(currentLocation, _mapController.camera.zoom);
            } catch (_) {}
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFE5E7EB),
          body: Stack(
            children: [
              // =============================================================
              // MAP
              // =============================================================
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: currentLocation,
                    initialZoom: 16,
                    minZoom: 3,
                    maxZoom: 19,
                    onPositionChanged: (camera, hasGesture) {
                      // The driver dragged/zoomed the map themselves — stop
                      // pulling the camera back to the jeepney.
                      if (hasGesture && _followingDriver) {
                        setState(() => _followingDriver = false);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: MapConfig.tileUrlTemplate,
                      userAgentPackageName: 'com.manibel.app',
                      maxZoom: 19,
                    ),

                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          MapConfig.attribution,
                          onTap: () {},
                        ),
                      ],
                    ),

                    // The route to follow, origin to destination — drawn under
                    // every marker so the jeepney and waiting-passenger pins
                    // always sit on top of it.
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 5,
                          color: AppColors.primary,
                          borderStrokeWidth: 2,
                          borderColor: AppColors.onPrimary,
                        ),
                      ],
                    ),

                    MarkerLayer(
                      markers: [
                        // Where this direction begins and ends.
                        Marker(
                          point: routePoints.first,
                          width: 26,
                          height: 26,
                          child: const _RouteEndpointPin(
                            icon: Icons.trip_origin_rounded,
                            color: Color(0xFF15803D),
                          ),
                        ),
                        Marker(
                          point: routePoints.last,
                          width: 26,
                          height: 26,
                          child: const _RouteEndpointPin(
                            icon: Icons.flag_rounded,
                            color: Color(0xFFDC2626),
                          ),
                        ),

                        // Waiting passenger stops — tap for distance + ETA
                        // (see _showPassengerInfo).
                        for (final stop in _demandStops)
                          Marker(
                            point: stop.point,
                            width: 34,
                            height: 34,
                            child: GestureDetector(
                              onTap: () => _showPassengerInfo(stop, currentLocation),
                              child: _WaitingStopPin(count: stop.count),
                            ),
                          ),

                        // Driver vehicle.
                        Marker(
                          point: currentLocation,
                          width: 40,
                          height: 40,
                          child: _VehicleMarker(
                            hasRealFix: _activeTrip.hasRealFix,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // =============================================================
              // TOP BAR
              // =============================================================
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ---------------------------------------------------
                        // BACK BUTTON
                        // ---------------------------------------------------
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _handleBackToDashboard,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.textPrimary,
                            ),
                            tooltip: 'Back to Dashboard',
                          ),
                        ),

                        const SizedBox(width: 10),

                        // ---------------------------------------------------
                        // TRIP STATUS
                        // ---------------------------------------------------
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        route,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        plateNumber,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircleAvatar(
                                        radius: 3,
                                        backgroundColor: Colors.green,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _activeTrip.elapsedLabel,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
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
              ),

              // =============================================================
              // LOCATION WARNING — otherwise this fails completely
              // silently: the driver's live position just stops updating
              // on the admin map with zero indication anything is wrong.
              // =============================================================
              if (_activeTrip.locationError != null)
                Positioned(
                  top: 130,
                  left: 16,
                  right: 16,
                  child: SafeArea(
                    bottom: false,
                    child: Material(
                      color: const Color(0xFFFFF1F1),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => openRelevantLocationSettings(
                          isServiceDisabled:
                              _activeTrip.isLocationErrorServiceDisabled,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_off_rounded,
                                color: Color(0xFFE23F3F),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _activeTrip.locationError!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF7A1F1F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // =============================================================
              // RECENTER — back onto the jeepney after panning away
              // =============================================================
              if (!_followingDriver)
                Positioned(
                  right: 16,
                  bottom: 96,
                  child: SafeArea(
                    top: false,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _recenterOnDriver,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.my_location_rounded,
                            size: 22,
                            color: AppColors.logoBlue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // =============================================================
              // END TRIP BUTTON
              // =============================================================
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _handleEndTrip,
                      icon: const Icon(
                        Icons.stop_circle_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'End Trip',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.errorRed,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===========================================================================
// ROUTE ENDPOINT PIN — the start/end of the route being driven
// ===========================================================================

class _RouteEndpointPin extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _RouteEndpointPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 15, color: color),
    );
  }
}

// ===========================================================================
// VEHICLE MARKER
// ===========================================================================

class _VehicleMarker extends StatelessWidget {
  final bool hasRealFix;

  const _VehicleMarker({required this.hasRealFix});

  @override
  Widget build(BuildContext context) {
    final markerColor = hasRealFix ? AppColors.logoBlue : Colors.black38;

    return Container(
      decoration: BoxDecoration(
        color: markerColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: markerColor.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_bus_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

// ===========================================================================
// WAITING STOP
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

/// Buckets raw demand-signal pings into ~0.001°-square cells (~100m at
/// this latitude) — same logic as the dashboard's own copy in
/// driver_dashboard_screen.dart (kept duplicated rather than shared since
/// each is a private, file-scoped class) and admin's clusterDemandSignals
/// (admin/src/components/LiveMap.tsx), so every surface agrees on where
/// passengers are from the same raw rows. The marker's displayed count
/// sums party sizes, not ping count.
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

// ===========================================================================
// WAITING STOP PIN
// ===========================================================================

class _WaitingStopPin extends StatelessWidget {
  final int count;

  const _WaitingStopPin({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = count > 1 ? AppColors.logoRed : AppColors.primary;
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
            size: 18,
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

// ===========================================================================
// TRIP COMPLETED DIALOG
// ===========================================================================

class _TripCompletedDialog extends StatelessWidget {
  final String route;
  final String plateNumber;
  final String duration;

  const _TripCompletedDialog({
    required this.route,
    required this.plateNumber,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.qrTileBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.qrIconColor,
                size: 28,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Trip Completed',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 8),

            _DetailRow(label: 'Route', value: route),

            const SizedBox(height: 4),

            _DetailRow(label: 'Vehicle', value: plateNumber),

            const SizedBox(height: 4),

            _DetailRow(label: 'Duration', value: duration),

            const SizedBox(height: 10),

            const Text(
              'Tap outside to dismiss',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// DETAIL ROW
// ===========================================================================

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(width: 6),

        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
