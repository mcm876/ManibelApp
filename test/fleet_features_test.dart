import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/core/services/api_client.dart';
import 'package:manibelapp_frontend/core/services/fleet_api.dart';
import 'package:manibelapp_frontend/features/driver/widgets/driver_status_banner.dart';
import 'package:manibelapp_frontend/features/driver/widgets/restriction_notice.dart';

void main() {
  group('TripOccupancy.fromJson', () {
    test('reads app + manual + total, capacity, seats left and the status', () {
      final occ = TripOccupancy.fromJson({
        'appPassengers': 8,
        'manualPassengers': 10,
        'totalPassengers': 18,
        'seatingCapacity': 20,
        'remainingSeats': 2,
        'status': 'NEARLY_FULL',
      });
      expect(occ.appPassengers, 8);
      expect(occ.manualPassengers, 10);
      expect(occ.totalPassengers, 18);
      expect(occ.seatingCapacity, 20);
      expect(occ.remainingSeats, 2);
      expect(occ.level, OccupancyLevel.nearlyFull);
    });

    test('FULL and an unknown capacity are told apart', () {
      expect(TripOccupancy.fromJson({'status': 'FULL'}).level, OccupancyLevel.full);
      final unknown = TripOccupancy.fromJson({'status': 'UNKNOWN', 'seatingCapacity': null});
      expect(unknown.level, OccupancyLevel.unknown);
      expect(unknown.seatingCapacity, isNull);
      expect(unknown.remainingSeats, isNull);
    });
  });

  group('DriverVehicle', () {
    test('a jeepney with no registered capacity cannot start a trip', () {
      final v = DriverVehicle.fromJson({'id': 'v1', 'plateNumber': 'ABC123', 'seatingCapacity': null, 'inUse': false});
      expect(v.canStart, isFalse);
    });

    test('capacity is per-vehicle and a jeepney already in use cannot be started', () {
      final a = DriverVehicle.fromJson({'id': 'a', 'plateNumber': 'ABC123', 'seatingCapacity': 20});
      final b = DriverVehicle.fromJson({'id': 'b', 'plateNumber': 'XYZ567', 'seatingCapacity': 18, 'inUse': true});
      expect(a.seatingCapacity, 20);
      expect(b.seatingCapacity, 18);
      expect(a.canStart, isTrue);
      expect(b.canStart, isFalse);
    });
  });

  test('isOfflineError only for requests that never reached the server', () {
    expect(isOfflineError(const ApiException('x')), isTrue);
    expect(isOfflineError(const ApiException('x', statusCode: 409)), isFalse);
    expect(isOfflineError(Exception('x')), isFalse);
  });

  group('restriction notice', () {
    TripRestriction restriction() => TripRestriction(
          reason: '3 short-tripping occurrences on record (limit 3).',
          startsAt: DateTime.now().subtract(const Duration(minutes: 10)),
          expiresAt: DateTime.now().add(const Duration(minutes: 50)),
          durationMinutes: 60,
        );

    testWidgets('shows the reason, when it started and when it ends', (tester) async {
      final r = restriction();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: RestrictionNotice(restriction: r))));
      expect(find.text('Trip start temporarily restricted'), findsOneWidget);
      expect(find.textContaining('3 short-tripping occurrences'), findsOneWidget);
      expect(find.textContaining('Started: ${formatRestrictionTime(r.startsAt)}'), findsOneWidget);
      expect(find.textContaining('Ends: ${formatRestrictionTime(r.expiresAt)}'), findsOneWidget);
    });

    testWidgets('banner shows nothing for a driver in good standing', (tester) async {
      const status = DriverStatusInfo(restriction: null, disciplinaryStatus: 'NONE', pendingExplanations: 0);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriverStatusBanner(status: status, onOpenIncidents: () {}))));
      expect(find.byType(RestrictionNotice), findsNothing);
      expect(find.textContaining('explanation'), findsNothing);
    });

    testWidgets('banner asks for outstanding explanations and opens them on tap', (tester) async {
      var opened = false;
      const status = DriverStatusInfo(restriction: null, disciplinaryStatus: 'NONE', pendingExplanations: 2);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DriverStatusBanner(status: status, onOpenIncidents: () => opened = true))),
      );
      expect(find.textContaining('2 passenger reports need your explanation'), findsOneWidget);
      await tester.tap(find.textContaining('need your explanation'));
      expect(opened, isTrue);
    });

    testWidgets('banner explains a suspension', (tester) async {
      const status = DriverStatusInfo(restriction: null, disciplinaryStatus: 'SUSPENDED', pendingExplanations: 0);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriverStatusBanner(status: status, onOpenIncidents: () {}))));
      expect(find.textContaining('suspended'), findsOneWidget);
    });
  });
}
