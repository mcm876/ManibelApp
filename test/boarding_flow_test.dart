import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:manibelapp_frontend/core/services/api_client.dart';
import 'package:manibelapp_frontend/core/utils/live_location.dart';
import 'package:manibelapp_frontend/features/commuter/services/boarding_config.dart';
import 'package:manibelapp_frontend/features/commuter/services/boarding_flow.dart';

Position _pos() => Position(
      longitude: 121.0,
      latitude: 14.5,
      timestamp: DateTime.now(),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

const _fast = BoardingConfig(
  permissionTimeout: Duration(milliseconds: 150),
  firstFixTimeout: Duration(milliseconds: 300),
  requestTimeout: Duration(milliseconds: 200),
  readingInterval: Duration(milliseconds: 20),
  overallTimeout: Duration(milliseconds: 1500),
  maxConsecutiveNetworkErrors: 2,
  confirmedDisplay: Duration(milliseconds: 10),
);

class _Server {
  _Server(this.handler);
  final FutureOr<Map<String, dynamic>> Function(String path, Map<String, dynamic> body, int call) handler;
  final calls = <String>[];
  int get boardPosts => calls.where((c) => c == '/api/commuter/board').length;
  int get cancelPosts => calls.where((c) => c.endsWith('/cancel')).length;

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    calls.add(path);
    return handler(path, body, calls.length);
  }
}

Map<String, dynamic> _pending([int ok = 0]) =>
    {'requestId': 'r1', 'status': 'PENDING', 'confirmedReadings': ok, 'requiredReadings': 3};
Map<String, dynamic> _confirmed() =>
    {'requestId': 'r1', 'status': 'CONFIRMED', 'tripId': 't1', 'boardingId': 'b1', 'boarded': true};
Map<String, dynamic> _failed(String code, String message) =>
    {'requestId': 'r1', 'status': 'FAILED', 'failureCode': code, 'message': message};

BoardingFlow _flow(
  _Server server, {
  Future<LocationAccess> Function()? access,
  Stream<Position> Function()? positions,
  BoardingConfig config = _fast,
}) {
  var n = 0;
  return BoardingFlow(
    tripId: 't1',
    riders: 1,
    post: server.post,
    ensureAccess: access ?? () async => LocationAccess.granted,
    positions: positions ?? () => Stream<Position>.periodic(const Duration(milliseconds: 20), (_) => _pos()),
    config: config,
    newRequestKey: () => 'key-${n++}',
  );
}

void main() {
  group('BoardingFlow', () {
    test('1. near the jeepney: goes PENDING -> VALIDATING -> CONFIRMED, only from the server', () async {
      final seen = <BoardingState>[];
      final server = _Server((path, body, call) => path == '/api/commuter/board' ? _pending() : (call < 4 ? _pending(1) : _confirmed()));
      final flow = _flow(server)..addListener(() {});
      flow.addListener(() => seen.add(flow.state));
      expect(flow.state, BoardingState.idle);
      await flow.start();
      expect(flow.state, BoardingState.confirmed);
      expect(flow.outcome?.boardingId, 'b1');
      expect(seen, containsAllInOrder([BoardingState.pending, BoardingState.validating, BoardingState.confirmed]));
      expect(flow.message, BoardingMessages.confirmed);
      flow.dispose();
    });

    test('Board alone is never CONFIRMED: a server that keeps saying PENDING ends FAILED (timed out), not confirmed', () async {
      final server = _Server((p, b, c) => _pending());
      final flow = _flow(server, config: const BoardingConfig(
        permissionTimeout: Duration(milliseconds: 150),
        firstFixTimeout: Duration(milliseconds: 300),
        requestTimeout: Duration(milliseconds: 200),
        readingInterval: Duration(milliseconds: 20),
        overallTimeout: Duration(milliseconds: 400),
      ));
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.outcome, isNull);
      expect(flow.message, BoardingMessages.timedOut);
      expect(server.cancelPosts, 1, reason: 'the open request is cancelled server-side');
      expect(flow.busy, isFalse);
      flow.dispose();
    });

    test('2. too far from the jeepney -> FAILED with the too-far message, not counted', () async {
      final server = _Server((p, b, c) => _failed('TOO_FAR', 'server text'));
      final flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.message, BoardingMessages.tooFar);
      expect(flow.outcome, isNull);
      flow.dispose();
    });

    test('3. GPS unavailable (location off / denied) -> FAILED, request never sent', () async {
      final server = _Server((p, b, c) => _confirmed());
      final flow = _flow(server, access: () async => LocationAccess.serviceDisabled);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(server.calls, isEmpty);
      expect(flow.busy, isFalse);
      flow.dispose();
    });

    test('3b. the location plugin throwing does not leave a spinner', () async {
      final server = _Server((p, b, c) => _confirmed());
      final flow = _flow(server, access: () async => throw StateError('platform channel exploded'));
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.message, BoardingMessages.locationUnavailable);
      flow.dispose();
    });

    test('6. GPS timeouts: permission prompt that never returns, and no fix ever arriving', () async {
      final server = _Server((p, b, c) => _confirmed());
      var flow = _flow(server, access: () => Completer<LocationAccess>().future);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.message, BoardingMessages.locationUnavailable);
      flow.dispose();

      flow = _flow(server, positions: () => const Stream<Position>.empty());
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.message, BoardingMessages.locationUnavailable);
      expect(server.calls, isEmpty, reason: 'no GPS fix, so no request was opened');
      flow.dispose();
    });

    test('7. backend never answers the first request -> times out, retry allowed', () async {
      final hang = Completer<Map<String, dynamic>>();
      final server = _Server((p, b, c) => hang.future);
      final flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.message, BoardingMessages.timedOut);
      expect(flow.busy, isFalse);
      flow.dispose();
    });

    test('7b. brief connection blips are tolerated, a long outage fails with a retry message', () async {
      var readings = 0;
      var server = _Server((path, b, c) {
        if (path == '/api/commuter/board') return _pending();
        readings++;
        if (readings == 1) throw const ApiException('offline');
        return _confirmed();
      });
      var flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.confirmed, reason: 'one dropped reading must not fail boarding');
      flow.dispose();

      server = _Server((path, b, c) {
        if (path == '/api/commuter/board') return _pending();
        throw const ApiException('offline');
      });
      flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.message, BoardingMessages.connectionLost);
      flow.dispose();
    });

    test('8. rapid taps while running start exactly one request', () async {
      final server = _Server((path, b, c) => path == '/api/commuter/board' ? _pending() : _confirmed());
      final flow = _flow(server);
      final runs = [flow.start(), flow.start(), flow.start(), flow.start()];
      await Future.wait(runs);
      expect(server.boardPosts, 1);
      expect(flow.state, BoardingState.confirmed);
      flow.dispose();
    });

    test('9. already on board this trip: server answers CONFIRMED without a request id, still one outcome', () async {
      final server = _Server((p, b, c) => {'requestId': null, 'status': 'CONFIRMED', 'boarded': true, 'tripId': 't1', 'boardingId': 'b1'});
      final flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.confirmed);
      expect(flow.outcome?.boardingId, 'b1');
      expect(server.calls.length, 1);
      flow.dispose();
    });

    test('10. cancelling a pending request returns at once, cancels it on the server, leaves nobody counted', () async {
      final server = _Server((path, b, c) => path.endsWith('/cancel') ? {'status': 'CANCELLED'} : _pending());
      final flow = _flow(server);
      final running = flow.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(flow.state, BoardingState.validating);
      final sw = Stopwatch()..start();
      flow.cancel();
      expect(sw.elapsedMilliseconds, lessThan(50));
      expect(flow.state, BoardingState.idle);
      await running;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(flow.state, BoardingState.idle, reason: 'the orphaned run must not flip the state again');
      expect(server.cancelPosts, 1);
      expect(flow.outcome, isNull);
      flow.cancel(); // idempotent
      expect(server.cancelPosts, 1);
      flow.dispose();
    });

    test('14/15. a second attempt after a failure, and after a success, works', () async {
      var attempt = 0;
      final server = _Server((path, b, c) {
        if (path == '/api/commuter/board') {
          attempt++;
          return attempt == 1 ? _failed('TOO_FAR', 'x') : _pending();
        }
        return _confirmed();
      });
      final flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.busy, isFalse);
      await flow.start();
      expect(flow.state, BoardingState.confirmed);
      await flow.start(); // and again after success
      expect(flow.state, BoardingState.confirmed);
      expect(server.boardPosts, 3);
      flow.dispose();
    });

    test('a garbled server reply fails cleanly instead of throwing out of the flow', () async {
      final server = _Server((p, b, c) => {'status': 12345, 'requestId': {'oops': true}});
      final flow = _flow(server);
      await flow.start();
      expect(flow.state, BoardingState.failed);
      expect(flow.busy, isFalse);
      flow.dispose();
    });

    test('17. disposing mid-attempt cancels the request, stops the GPS stream and never notifies afterwards', () async {
      final cancelled = Completer<void>();
      final controller = StreamController<Position>(onCancel: () => cancelled.complete());
      Timer.periodic(const Duration(milliseconds: 20), (t) {
        if (controller.isClosed) {
          t.cancel();
        } else if (controller.hasListener) {
          controller.add(_pos());
        }
      });
      final server = _Server((path, b, c) => path.endsWith('/cancel') ? {'status': 'CANCELLED'} : _pending());
      final flow = _flow(server, positions: () => controller.stream);
      final running = flow.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      flow.dispose();
      await running;
      await cancelled.future.timeout(const Duration(seconds: 2));
      await controller.close();
      expect(server.cancelPosts, 1);
    });
  });
}
