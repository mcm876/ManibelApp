import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:manibelapp_frontend/core/constants/route_path.dart';

void main() {
  group('RoutePath', () {
    test('Pasig – Quiapo is the reference route and is unchanged', () {
      final path = RoutePath.pasigToQuiapo;

      expect(path.length, 116);
      expect(path.first, const LatLng(14.559610, 121.083800)); // Pasig end
      expect(path.last, const LatLng(14.597200, 120.985010)); // Quiapo end
    });

    test('Quiapo – Pasig is exactly Pasig – Quiapo in reverse', () {
      final forward = RoutePath.pasigToQuiapo;
      final back = RoutePath.quiapoToPasig;

      expect(back.length, forward.length);
      for (var i = 0; i < forward.length; i++) {
        expect(back[i], forward[forward.length - 1 - i], reason: 'point $i');
      }
    });

    test('Quiapo – Pasig starts at Quiapo and ends at Pasig', () {
      final back = RoutePath.quiapoToPasig;

      expect(back.first, RoutePath.pasigToQuiapo.last);
      expect(back.last, RoutePath.pasigToQuiapo.first);
      // Quiapo is west of Pasig (smaller longitude).
      expect(back.first.longitude, lessThan(back.last.longitude));
    });

    test('both directions run through Ramon Magsaysay Blvd. and Victorio Mapa Blvd.', () {
      // Approximate vertices of the two corridors, taken from the route the
      // app already draws for Pasig – Quiapo.
      const victorioMapa = LatLng(14.59969, 121.01695);
      const ramonMagsaysay = LatLng(14.60227, 121.01027);

      bool passesNear(List<LatLng> path, LatLng target) {
        const distance = Distance();
        return path.any((p) => distance(p, target) < 60);
      }

      for (final path in [RoutePath.pasigToQuiapo, RoutePath.quiapoToPasig]) {
        expect(passesNear(path, victorioMapa), isTrue);
        expect(passesNear(path, ramonMagsaysay), isTrue);
      }

      // Traveling Quiapo -> Pasig meets Ramon Magsaysay before Victorio Mapa.
      const distance = Distance();
      int indexNear(List<LatLng> path, LatLng target) =>
          path.indexWhere((p) => distance(p, target) < 60);
      final back = RoutePath.quiapoToPasig;
      expect(
        indexNear(back, ramonMagsaysay),
        lessThan(indexNear(back, victorioMapa)),
      );
    });

    test('forRoute selects the direction by its exact name', () {
      expect(RoutePath.forRoute('Pasig – Quiapo'), same(RoutePath.pasigToQuiapo));
      expect(RoutePath.forRoute('Quiapo – Pasig'), same(RoutePath.quiapoToPasig));
      // Unknown / missing falls back to the reference direction.
      expect(RoutePath.forRoute(null), same(RoutePath.pasigToQuiapo));
    });

    test('trailBetween follows the reversed path in the Quiapo – Pasig direction', () {
      final back = RoutePath.quiapoToPasig;
      final from = back[10];
      final to = back[40];

      final trail = RoutePath.trailBetween(from, to, route: 'Quiapo – Pasig');

      expect(trail.first.latitude, closeTo(back[10].latitude, 1e-6));
      expect(trail.last.latitude, closeTo(back[40].latitude, 1e-6));
      // Every intermediate trail point is a real vertex of the route.
      for (final p in trail.sublist(1, trail.length - 1)) {
        expect(back.contains(p), isTrue);
      }
    });
  });
}
