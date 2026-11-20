/// Client-side limits for GPS-verified boarding, in one place.
///
/// The distance / accuracy / freshness thresholds that decide whether boarding
/// is CONFIRMED live on the server (admin-editable SystemSetting rows, see
/// backend/src/lib/settings.ts) — the app never decides that. These are only
/// the timeouts that guarantee the commuter's screen can't wait forever.
class BoardingConfig {
  const BoardingConfig({
    this.permissionTimeout = const Duration(seconds: 10),
    this.firstFixTimeout = const Duration(seconds: 12),
    this.requestTimeout = const Duration(seconds: 15),
    this.readingInterval = const Duration(seconds: 2),
    // Shorter than the server's request TTL (boardingRequestTtlSeconds, 60 by
    // default) so the app gives up — and cancels — before the server does.
    this.overallTimeout = const Duration(seconds: 45),
    this.maxConsecutiveNetworkErrors = 3,
    this.confirmedDisplay = const Duration(milliseconds: 900),
  });

  /// Location-services check + permission prompt.
  final Duration permissionTimeout;

  /// Waiting for the first GPS fix after location access was granted.
  final Duration firstFixTimeout;

  /// One boarding API call. Shorter than ApiClient's general 25 s timeout so a
  /// dead connection is noticed while the commuter is still watching.
  final Duration requestTimeout;

  /// How often a fresh reading is sent while verifying.
  final Duration readingInterval;

  /// Hard ceiling for the whole attempt, start to finish.
  final Duration overallTimeout;

  final int maxConsecutiveNetworkErrors;

  /// How long the "confirmed" state is shown before the dialog closes.
  final Duration confirmedDisplay;
}

/// Messages shown to the commuter, kept together so they stay consistent.
class BoardingMessages {
  const BoardingMessages._();

  static const checkingLocation = 'Checking your location...';
  static const verifyingJeepney = 'Verifying nearby jeepney...';
  static const confirmed = 'Boarding confirmed. You are now counted as a passenger.';
  static const tooFar = 'You are too far from the jeepney to confirm boarding.';
  static const locationUnavailable = 'Unable to verify your location. Please try again.';
  static const timedOut = 'Boarding verification timed out. You may retry.';
  static const connectionLost = 'Connection lost, so boarding was not confirmed. You may retry.';
  static const generic = "Boarding couldn't be confirmed. Please try again.";
}
