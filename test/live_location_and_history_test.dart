import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:manibelapp_frontend/core/utils/live_location.dart';
import 'package:manibelapp_frontend/features/commuter/screens/commuter_history_screen.dart';

Position _fix({required DateTime at, double accuracy = 5}) => Position(
  latitude: 14.6,
  longitude: 121.0,
  timestamp: at,
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  group('live location filters', () {
    test('a reading from moments ago is fresh', () {
      expect(isFreshFix(_fix(at: DateTime.now().subtract(const Duration(seconds: 3)))), isTrue);
    });

    test('a cached reading from minutes ago is rejected', () {
      expect(isFreshFix(_fix(at: DateTime.now().subtract(const Duration(minutes: 5)))), isFalse);
    });

    test('accuracy decides whether a fix counts as a real GPS lock', () {
      final now = DateTime.now();
      expect(isPreciseFix(_fix(at: now, accuracy: 8)), isTrue);
      expect(isPreciseFix(_fix(at: now, accuracy: kPreciseFixMeters)), isTrue);
      expect(isPreciseFix(_fix(at: now, accuracy: 1500)), isFalse);
    });
  });

  group('TripHistoryStatus', () {
    test('maps the backend status', () {
      expect(TripHistoryStatus.fromBackend('CANCELLED'), TripHistoryStatus.cancelled);
      expect(TripHistoryStatus.fromBackend('BOARDED'), TripHistoryStatus.inProgress);
      expect(TripHistoryStatus.fromBackend('COMPLETED'), TripHistoryStatus.completed);
    });

    test('an older backend / stored entry with no status reads as completed', () {
      expect(TripHistoryStatus.fromBackend(null), TripHistoryStatus.completed);
      expect(TripHistoryStatus.fromStored(null), TripHistoryStatus.completed);
      expect(TripHistoryStatus.fromStored('cancelled'), TripHistoryStatus.cancelled);
    });

    test('a cancelled item is identifiable and labeled', () {
      final trip = TripHistoryItem(
        boardingId: 'b1',
        tripId: 't1',
        driverName: 'Juan',
        plateNumber: 'ABC123',
        route: 'Pasig – Quiapo',
        riders: 1,
        dateTime: 'Sep 28, 2026 · 3:45 PM',
        boardedAt: DateTime(2026, 9, 28, 15, 45),
        status: TripHistoryStatus.cancelled,
      );

      expect(trip.isCancelled, isTrue);
      expect(trip.status.label, 'Cancelled');
      expect(
        TripHistoryItem(
          boardingId: 'b2',
          tripId: 't2',
          driverName: 'Juan',
          plateNumber: 'ABC123',
          route: 'Pasig – Quiapo',
          riders: 1,
          dateTime: '',
          boardedAt: DateTime(2026, 9, 28),
        ).status,
        TripHistoryStatus.completed,
      );
    });
  });
}
