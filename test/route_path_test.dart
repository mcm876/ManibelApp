import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:manibelapp_frontend/core/constants/route_path.dart';

/// The route geometry is Sakay's published shape for DOTR:R_SAKAY_2018_PUJ_657
/// (trip T_SAKAY_2018_1316): one shape that runs Pasig -> Quiapo and back.
/// The expected end points below are that shape's own first point, the point
/// where its outbound leg ends, where its return leg starts, and its last
/// point.
/// Distance in meters from [p] to the closest point on the polyline [path]
/// (measured to the road segments, not just the vertices — the simplified
/// route has few vertices along long straight roads).
double _distanceToPath(List<LatLng> path, LatLng p) {
  const distance = Distance();
  var best = double.infinity;
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final lenSq = dx * dx + dy * dy;
    var t = 0.0;
    if (lenSq > 0) {
      t = (((p.longitude - a.longitude) * dx) + ((p.latitude - a.latitude) * dy)) / lenSq;
      t = t.clamp(0.0, 1.0);
    }
    final closest = LatLng(a.latitude + t * dy, a.longitude + t * dx);
    final d = distance(p, closest);
    if (d < best) best = d;
  }
  return best;
}

/// Fraction (0..path.length-1) of the way along [path] where it comes closest
/// to [p] — used to check the order landmarks are met in.
double _positionAlong(List<LatLng> path, LatLng p) {
  var bestDist = double.infinity;
  var bestPos = 0.0;
  const distance = Distance();
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    final lenSq = dx * dx + dy * dy;
    var t = 0.0;
    if (lenSq > 0) {
      t = (((p.longitude - a.longitude) * dx) + ((p.latitude - a.latitude) * dy)) / lenSq;
      t = t.clamp(0.0, 1.0);
    }
    final d = distance(p, LatLng(a.latitude + t * dy, a.longitude + t * dx));
    if (d < bestDist) {
      bestDist = d;
      bestPos = i + t;
    }
  }
  return bestPos;
}

void main() {
  const distance = Distance();

  group('RoutePath (Sakay DOTR:R_SAKAY_2018_PUJ_657)', () {
    test('Pasig – Quiapo is Sakay\'s outbound leg, Pasig to Arlegui', () {
      final path = RoutePath.pasigToQuiapo;

      expect(path.length, 116);
      expect(path.first, const LatLng(14.559610, 121.083800)); // Caruncho / Market Ave., Pasig
      expect(path.last, const LatLng(14.597200, 120.985010)); // Arlegui, Manila
    });

    test('Quiapo – Pasig is Sakay\'s published return leg, Quiapo back to Pasig', () {
      final path = RoutePath.quiapoToPasig;

      expect(path.length, 97);
      expect(path.first, const LatLng(14.599490, 120.984350)); // Quezon Blvd. / Recto, Quiapo
      expect(path.last, const LatLng(14.557660, 121.084460)); // back at the Pasig terminal
    });

    test('the two directions are cut from one shape with nothing lost or added', () {
      expect(RoutePath.pasigToQuiapo.length + RoutePath.quiapoToPasig.length, 213);
      // The legs meet at Sakay's own join at Quiapo (Arlegui -> Quezon Blvd.),
      // about 260 m apart — the only place the shape jumps between legs.
      expect(
        distance(RoutePath.pasigToQuiapo.last, RoutePath.quiapoToPasig.first),
        closeTo(264, 5),
      );
    });

    test('Quiapo is west of Pasig, so each direction starts and ends on the right side', () {
      // Pasig -> Quiapo: starts east, ends west.
      expect(RoutePath.pasigToQuiapo.first.longitude, greaterThan(121.07));
      expect(RoutePath.pasigToQuiapo.last.longitude, lessThan(120.99));
      // Quiapo -> Pasig: starts west, ends east.
      expect(RoutePath.quiapoToPasig.first.longitude, lessThan(120.99));
      expect(RoutePath.quiapoToPasig.last.longitude, greaterThan(121.07));
    });

    test('both directions run through Victorio Mapa Blvd. and Ramon Magsaysay Blvd.', () {
      const victorioMapa = LatLng(14.59969, 121.01695);
      const ramonMagsaysay = LatLng(14.60227, 121.01027);

      for (final path in [RoutePath.pasigToQuiapo, RoutePath.quiapoToPasig]) {
        expect(_distanceToPath(path, victorioMapa), lessThan(60));
        expect(_distanceToPath(path, ramonMagsaysay), lessThan(60));
      }

      // Pasig -> Quiapo meets VMAPA first, then Ramon Magsaysay Blvd.
      final out = RoutePath.pasigToQuiapo;
      expect(_positionAlong(out, victorioMapa), lessThan(_positionAlong(out, ramonMagsaysay)));

      // Quiapo -> Pasig meets Ramon Magsaysay Blvd. first, then VMAPA.
      final back = RoutePath.quiapoToPasig;
      expect(_positionAlong(back, ramonMagsaysay), lessThan(_positionAlong(back, victorioMapa)));
    });

    test('forRoute selects the direction by its exact name', () {
      expect(RoutePath.forRoute('Pasig – Quiapo'), same(RoutePath.pasigToQuiapo));
      expect(RoutePath.forRoute('Quiapo – Pasig'), same(RoutePath.quiapoToPasig));
      // Unknown / missing falls back to the Pasig -> Quiapo direction.
      expect(RoutePath.forRoute(null), same(RoutePath.pasigToQuiapo));
    });

    test('trailBetween follows the Quiapo – Pasig leg in that direction', () {
      final back = RoutePath.quiapoToPasig;
      final from = back[10];
      final to = back[40];

      final trail = RoutePath.trailBetween(from, to, route: 'Quiapo – Pasig');

      expect(distance(trail.first, back[10]), lessThan(2));
      expect(distance(trail.last, back[40]), lessThan(2));
      for (final p in trail.sublist(1, trail.length - 1)) {
        expect(back.contains(p), isTrue);
      }
    });
  });
}
