import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/live_location.dart';
import 'boarding_config.dart';

/// IDLE → PENDING → VALIDATING → CONFIRMED | FAILED.
///
/// * [idle]       nothing in flight (also where a cancelled attempt ends up).
/// * [pending]    Board was pressed; getting this phone's own GPS fix.
/// * [validating] the request is open on the server, which is comparing fresh
///                readings from this phone with the jeepney's position.
/// * [confirmed]  the SERVER said CONFIRMED — the only state that counts the
///                commuter as a passenger. The app never decides this itself.
/// * [failed]     could not be verified, timed out, or the server refused; the
///                commuter is not counted and may retry with [start].
enum BoardingState { idle, pending, validating, confirmed, failed }

class BoardingOutcome {
  const BoardingOutcome({required this.tripId, required this.boardingId});
  final String? tripId;
  final String? boardingId;
}

typedef BoardingPost = Future<Map<String, dynamic>> Function(String path, Map<String, dynamic> body);

/// Drives one commuter's boarding attempt. Pure Dart (no widgets) so the
/// timeout / retry / cancel behaviour can be unit-tested.
///
/// Guarantees:
/// * every await is bounded (permission, first fix, each API call, and the
///   whole attempt), so the attempt always ends in [BoardingState.failed] or
///   [BoardingState.confirmed] — never an endless spinner;
/// * [start] while an attempt is running is ignored (rapid taps);
/// * a superseded / cancelled attempt can never change the state of a newer one
///   (each run carries a token);
/// * the location subscription is always cancelled, whatever the outcome.
class BoardingFlow extends ChangeNotifier {
  BoardingFlow({
    this.tripId,
    this.qrToken,
    required this.riders,
    BoardingPost? post,
    Future<LocationAccess> Function()? ensureAccess,
    Stream<Position> Function()? positions,
    this.config = const BoardingConfig(),
    String Function()? newRequestKey,
  })  : _post = post ?? _defaultPost,
        _ensureAccess = ensureAccess ?? ensureLocationAccess,
        _positions = positions ?? (() => livePositionStream(distanceFilterMeters: 0)),
        _newRequestKey = newRequestKey ?? _defaultKey;

  final String? tripId;
  final String? qrToken;
  final int riders;
  final BoardingConfig config;

  final BoardingPost _post;
  final Future<LocationAccess> Function() _ensureAccess;
  final Stream<Position> Function() _positions;
  final String Function() _newRequestKey;

  static Future<Map<String, dynamic>> _defaultPost(String path, Map<String, dynamic> body) =>
      ApiClient.post(path, body, token: UserSession.instance.authToken);

  static String _defaultKey() => 'b-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  BoardingState _state = BoardingState.idle;
  String _message = '';
  int _confirmedReadings = 0;
  int _requiredReadings = 3;
  BoardingOutcome? _outcome;

  BoardingState get state => _state;

  /// What to show the commuter for the current state.
  String get message => _message;
  int get confirmedReadings => _confirmedReadings;
  int get requiredReadings => _requiredReadings;
  BoardingOutcome? get outcome => _outcome;

  /// True while an attempt is in flight (the Board / Try Again button should be
  /// disabled only during this).
  bool get busy => _running;

  bool _running = false;
  bool _disposed = false;
  int _run = 0;
  int _startedRun = -1;

  StreamSubscription<Position>? _sub;
  Position? _latest;
  DateTime? _latestAt;
  String? _requestId;

  bool _current(int run) => !_disposed && run == _run;

  void _set(BoardingState s, String message) {
    _state = s;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  void _stopLocation() {
    final sub = _sub;
    _sub = null;
    // Never await a platform subscription's cancel on the UI path.
    if (sub != null) unawaited(sub.cancel().timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((_) {}));
  }

  void _cancelServerRequest() {
    final id = _requestId;
    _requestId = null;
    if (id == null) return;
    // Best effort: an unconfirmed request counts for nothing either way and the
    // server expires it on its own.
    unawaited(_post('/api/commuter/board/requests/$id/cancel', {}).timeout(config.requestTimeout).then((_) {}).catchError((_) {}));
  }

  void _fail(int run, String message) {
    if (!_current(run)) return;
    _stopLocation();
    _set(BoardingState.failed, message);
  }

  Map<String, dynamic>? _readingPayload() {
    final p = _latest;
    final at = _latestAt;
    if (p == null || at == null) return null;
    return {
      'lat': p.latitude,
      'lng': p.longitude,
      'accuracy': p.accuracy,
      // Age is measured from when THIS app received the fix — a phone with a
      // wrong clock would make the fix's own timestamp meaningless.
      'fixAgeSeconds': DateTime.now().difference(at).inMilliseconds / 1000.0,
    };
  }

  /// Begins (or retries) boarding. A no-op while an attempt is already running.
  Future<void> start() async {
    if (_disposed || _running) return;
    _running = true;
    final run = ++_run;
    _startedRun = run;
    _requestId = null;
    _outcome = null;
    _confirmedReadings = 0;
    _latest = null;
    _latestAt = null;
    _set(BoardingState.pending, BoardingMessages.checkingLocation);

    try {
      await _execute(run).timeout(config.overallTimeout);
    } on TimeoutException {
      if (_current(run)) {
        _cancelServerRequest();
        _fail(run, BoardingMessages.timedOut);
      }
    } on ApiException catch (e) {
      _fail(run, e.statusCode == null ? BoardingMessages.connectionLost : e.message);
    } catch (_) {
      _fail(run, BoardingMessages.generic);
    } finally {
      // Invalidate anything still running from this attempt (e.g. after the
      // overall timeout) and always release the lock so the commuter can retry.
      // (A cancel() or newer start() already took over if _startedRun moved on.)
      if (_startedRun == run) {
        if (run == _run) _run++;
        _stopLocation();
        _running = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _execute(int run) async {
    // 1. Location access.
    LocationAccess access;
    try {
      access = await _ensureAccess().timeout(config.permissionTimeout);
    } on TimeoutException {
      _fail(run, BoardingMessages.locationUnavailable);
      return;
    } catch (_) {
      _fail(run, BoardingMessages.locationUnavailable);
      return;
    }
    if (!_current(run)) return;
    if (access != LocationAccess.granted) {
      _fail(run, locationAccessMessage(access));
      return;
    }

    // 2. A fresh fix from this phone.
    _stopLocation();
    _sub = _positions().listen(
      (p) {
        _latest = p;
        _latestAt = DateTime.now();
      },
      onError: (_) {},
    );
    final deadline = DateTime.now().add(config.firstFixTimeout);
    while (_latest == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_current(run)) return;
    }
    if (_latest == null) {
      _fail(run, BoardingMessages.locationUnavailable);
      return;
    }

    // 3. Open the request; the server now compares us with the jeepney.
    _set(BoardingState.validating, BoardingMessages.verifyingJeepney);
    var response = await _post('/api/commuter/board', {
      if (tripId != null) 'tripId': tripId,
      if (qrToken != null) 'qrToken': qrToken,
      'riders': riders,
      'clientRequestId': _newRequestKey(),
      ...?_readingPayload(),
    }).timeout(config.requestTimeout);

    var networkErrors = 0;
    while (true) {
      if (!_current(run)) return;
      final status = response['status']?.toString();
      _requestId = response['requestId']?.toString() ?? _requestId;
      _requiredReadings = (response['requiredReadings'] as num?)?.toInt() ?? _requiredReadings;

      if (status == 'CONFIRMED') {
        _stopLocation();
        _requestId = null; // nothing left to cancel
        _outcome = BoardingOutcome(
          tripId: response['tripId']?.toString(),
          boardingId: response['boardingId']?.toString(),
        );
        _set(BoardingState.confirmed, BoardingMessages.confirmed);
        return;
      }
      if (status == 'FAILED' || status == 'CANCELLED') {
        _requestId = null;
        _fail(run, _failureMessage(response));
        return;
      }

      _confirmedReadings = (response['confirmedReadings'] as num?)?.toInt() ?? 0;
      if (!_disposed) notifyListeners();

      await Future<void>.delayed(config.readingInterval);
      if (!_current(run)) return;

      final id = _requestId;
      if (id == null) {
        _fail(run, BoardingMessages.generic);
        return;
      }
      try {
        response = await _post(
          '/api/commuter/board/requests/$id/readings',
          // No fix at all is sent as an unusable reading so the server keeps
          // the request honest instead of the app going quiet.
          _readingPayload() ?? {'lat': 0, 'lng': 0, 'accuracy': 9999, 'fixAgeSeconds': 9999},
        ).timeout(config.requestTimeout);
        networkErrors = 0;
      } on ApiException catch (e) {
        if (e.statusCode == null && ++networkErrors <= config.maxConsecutiveNetworkErrors) continue;
        _fail(run, e.statusCode == null ? BoardingMessages.connectionLost : e.message);
        return;
      } on TimeoutException {
        if (++networkErrors <= config.maxConsecutiveNetworkErrors) continue;
        _fail(run, BoardingMessages.timedOut);
        return;
      }
    }
  }

  String _failureMessage(Map<String, dynamic> response) {
    final code = response['failureCode']?.toString();
    if (code == 'TOO_FAR') return BoardingMessages.tooFar;
    if (code == 'VERIFICATION_TIMEOUT') return BoardingMessages.timedOut;
    final message = response['message']?.toString();
    return (message == null || message.isEmpty) ? BoardingMessages.generic : message;
  }

  /// The commuter backed out. Returns immediately — it never waits on the
  /// network or the GPS plugin — and leaves them uncounted.
  void cancel() {
    if (_disposed) return;
    final wasConfirmed = _state == BoardingState.confirmed;
    _run++; // orphan any in-flight work
    _startedRun = -1;
    _running = false;
    _stopLocation();
    if (!wasConfirmed) {
      _cancelServerRequest();
      _set(BoardingState.idle, '');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_state == BoardingState.pending || _state == BoardingState.validating) _cancelServerRequest();
    _disposed = true;
    _run++;
    _stopLocation();
    super.dispose();
  }
}
