import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Shared building blocks for keeping a marker on the device's *real, current*
/// GPS position — used by the commuter's dashboard and booking map, and by the
/// driver's live trip tracking, so they all agree on what counts as a usable
/// fix instead of each keeping its own copy of the same permission/accuracy
/// code.

/// A fix whose reported accuracy is worse than this (meters) is a coarse
/// cell-tower/Wi-Fi guess, not a real GPS lock — easily off by hundreds of
/// meters or kilometers. Such a fix is still usable as a stop-gap (better than
/// nothing while GPS warms up) but callers should show it as "still locating"
/// and expect a tighter one to replace it shortly.
const double kPreciseFixMeters = 100;

/// A fix older than this is one the OS handed back from its cache (the last
/// place the phone happened to be), not where the device is right now — the
/// classic reason a marker sits at yesterday's/the previous stop's position.
const Duration kMaxFixAge = Duration(seconds: 30);

/// Whether [position] is a genuinely current reading rather than a cached one.
bool isFreshFix(Position position) {
  return DateTime.now().difference(position.timestamp) <= kMaxFixAge;
}

/// Whether [position] is precise enough to treat as a real GPS lock.
bool isPreciseFix(Position position) => position.accuracy <= kPreciseFixMeters;

/// Why location can't currently be used. [granted] means it can.
enum LocationAccess { granted, serviceDisabled, denied, deniedForever }

/// Checks that device location services are on and this app may use them,
/// asking for permission if that hasn't been decided yet. Never throws.
Future<LocationAccess> ensureLocationAccess() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return LocationAccess.serviceDisabled;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  switch (permission) {
    case LocationPermission.denied:
      return LocationAccess.denied;
    case LocationPermission.deniedForever:
      return LocationAccess.deniedForever;
    case LocationPermission.whileInUse:
    case LocationPermission.always:
    case LocationPermission.unableToDetermine:
      return LocationAccess.granted;
  }
}

/// A human-readable explanation for an unusable [LocationAccess].
String locationAccessMessage(LocationAccess access) {
  switch (access) {
    case LocationAccess.granted:
      return '';
    case LocationAccess.serviceDisabled:
      return 'Location services are off. Turn them on to see where you are.';
    case LocationAccess.denied:
      return 'Location permission was denied.';
    case LocationAccess.deniedForever:
      return 'Location permission is blocked. Enable it in app settings.';
  }
}

/// One fresh, precise reading of where the device is right now — the first
/// fix before a live stream has produced anything. Retries a couple of times
/// for a tighter fix, falling back to the best one seen (a coarse fix beats
/// none while GPS warms up). Null if no fresh reading could be had at all.
/// Assumes [ensureLocationAccess] already succeeded.
Future<Position?> resolveCurrentPosition() async {
  Position? best;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final candidate = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 12 + attempt * 4),
        ),
      );
      if (!isFreshFix(candidate)) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      if (best == null || candidate.accuracy < best.accuracy) best = candidate;
      if (isPreciseFix(candidate)) break;
      await Future.delayed(const Duration(seconds: 1));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }
  return best;
}

/// A continuous stream of the device's position: best-available accuracy,
/// a new event every [distanceFilterMeters] moved, cached readings dropped.
/// This is what makes a map marker actually follow someone who is moving —
/// a one-shot getCurrentPosition() only ever reports where they *were*.
///
/// Pass [foregroundNotification] (Android only) to keep the stream alive
/// while the app is backgrounded/the screen is locked, which a driver's live
/// trip needs — without it Android stops delivering updates shortly after the
/// app leaves the foreground.
Stream<Position> livePositionStream({
  int distanceFilterMeters = 3,
  ForegroundNotificationConfig? foregroundNotification,
}) {
  final LocationSettings settings;
  if (defaultTargetPlatform == TargetPlatform.android) {
    settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: distanceFilterMeters,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: foregroundNotification,
    );
  } else {
    settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: distanceFilterMeters,
    );
  }
  return Geolocator.getPositionStream(locationSettings: settings).where(isFreshFix);
}
