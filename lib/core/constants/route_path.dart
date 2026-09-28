import 'package:latlong2/latlong.dart';

/// A fixed, real road-following polyline of the officially-registered
/// Pasig-Quiapo PUJ route (DOTr/Sakay route DOTR:R_SAKAY_2018_PUJ_657 —
/// https://explore.sakay.ph/routes/DOTR:R_SAKAY_2018_PUJ_657): Caruncho
/// Ave./Market Ave., Pasig <-> Arlegui / Quezon Blvd., Manila via Shaw
/// Blvd., Victorio Mapa Blvd. and Ramon Magsaysay Blvd. The Pasig -> Quiapo
/// path is the shape Sakay publishes for the route's outbound trip
/// (T_SAKAY_2018_1316), simplified with Douglas-Peucker at ~3 m, and is the
/// single source of truth for the corridor; Quiapo -> Pasig is derived from
/// it by reversing (see [quiapoToPasig]). Kept identical to the admin
/// site's admin/src/lib/routePath.ts.
/// Used only to draw a visual "trail" on the booking map (see
/// [trailBetween]); it plays no part in the ETA numbers themselves, which
/// stay the server's own straight-line estimate (see GET
/// /commuter/nearby-jeepneys' own doc comment).
class RoutePath {
  RoutePath._();

  /// Pasig -> Quiapo (trip T_SAKAY_2018_1316).
  static const List<LatLng> pasigToQuiapo = [
    LatLng(14.559610, 121.083800),
    LatLng(14.560670, 121.080950),
    LatLng(14.559830, 121.080650),
    LatLng(14.560970, 121.077560),
    LatLng(14.560790, 121.077480),
    LatLng(14.560750, 121.077360),
    LatLng(14.560860, 121.076640),
    LatLng(14.561920, 121.076730),
    LatLng(14.563940, 121.076550),
    LatLng(14.563850, 121.077350),
    LatLng(14.563890, 121.077440),
    LatLng(14.564670, 121.077480),
    LatLng(14.564870, 121.077390),
    LatLng(14.564510, 121.076550),
    LatLng(14.564710, 121.076450),
    LatLng(14.565250, 121.075990),
    LatLng(14.565260, 121.076100),
    LatLng(14.565520, 121.076640),
    LatLng(14.565940, 121.077300),
    LatLng(14.565760, 121.077390),
    LatLng(14.565940, 121.077300),
    LatLng(14.566120, 121.077660),
    LatLng(14.566240, 121.077120),
    LatLng(14.566090, 121.076140),
    LatLng(14.566350, 121.072070),
    LatLng(14.566380, 121.071280),
    LatLng(14.566340, 121.071010),
    LatLng(14.566110, 121.070470),
    LatLng(14.566110, 121.070270),
    LatLng(14.565320, 121.070050),
    LatLng(14.564480, 121.069680),
    LatLng(14.564640, 121.069480),
    LatLng(14.564460, 121.069430),
    LatLng(14.564280, 121.069570),
    LatLng(14.563480, 121.069060),
    LatLng(14.563170, 121.068700),
    LatLng(14.562960, 121.068120),
    LatLng(14.562880, 121.067430),
    LatLng(14.562940, 121.066720),
    LatLng(14.563250, 121.065680),
    LatLng(14.563350, 121.065540),
    LatLng(14.563500, 121.065470),
    LatLng(14.563840, 121.065470),
    LatLng(14.564960, 121.065680),
    LatLng(14.566000, 121.065810),
    LatLng(14.566090, 121.066180),
    LatLng(14.566230, 121.066200),
    LatLng(14.566160, 121.065840),
    LatLng(14.567880, 121.066140),
    LatLng(14.567880, 121.066280),
    LatLng(14.567920, 121.066310),
    LatLng(14.567990, 121.066290),
    LatLng(14.568030, 121.066170),
    LatLng(14.570030, 121.066550),
    LatLng(14.570220, 121.066530),
    LatLng(14.570360, 121.066460),
    LatLng(14.573300, 121.062970),
    LatLng(14.574360, 121.061780),
    LatLng(14.574530, 121.061710),
    LatLng(14.574800, 121.061360),
    LatLng(14.574830, 121.061230),
    LatLng(14.577900, 121.057610),
    LatLng(14.579400, 121.055960),
    LatLng(14.581780, 121.053220),
    LatLng(14.583050, 121.051690),
    LatLng(14.583560, 121.050970),
    LatLng(14.584560, 121.049790),
    LatLng(14.586250, 121.047650),
    LatLng(14.587290, 121.046430),
    LatLng(14.588030, 121.044920),
    LatLng(14.588960, 121.042400),
    LatLng(14.589480, 121.040430),
    LatLng(14.589550, 121.039840),
    LatLng(14.589410, 121.035390),
    LatLng(14.589540, 121.035180),
    LatLng(14.590000, 121.034660),
    LatLng(14.590360, 121.034070),
    LatLng(14.592260, 121.029840),
    LatLng(14.592930, 121.028720),
    LatLng(14.593230, 121.028120),
    LatLng(14.593640, 121.027120),
    LatLng(14.593730, 121.027000),
    LatLng(14.594180, 121.025720),
    LatLng(14.594170, 121.025600),
    LatLng(14.596160, 121.020460),
    LatLng(14.595930, 121.019980),
    LatLng(14.595970, 121.019830),
    LatLng(14.597590, 121.017630),
    LatLng(14.599690, 121.016950),
    LatLng(14.600840, 121.016640),
    LatLng(14.603020, 121.015890),
    LatLng(14.602850, 121.015580),
    LatLng(14.602680, 121.014960),
    LatLng(14.602270, 121.010270),
    LatLng(14.602310, 121.010070),
    LatLng(14.602240, 121.009880),
    LatLng(14.602160, 121.008590),
    LatLng(14.601910, 121.006560),
    LatLng(14.601350, 121.000500),
    LatLng(14.601270, 121.000150),
    LatLng(14.600910, 120.999390),
    LatLng(14.601140, 120.998850),
    LatLng(14.601160, 120.998470),
    LatLng(14.600960, 120.997350),
    LatLng(14.600580, 120.996270),
    LatLng(14.600640, 120.995850),
    LatLng(14.601520, 120.993130),
    LatLng(14.601580, 120.992850),
    LatLng(14.601560, 120.992650),
    LatLng(14.600990, 120.991610),
    LatLng(14.600280, 120.990810),
    LatLng(14.597750, 120.989560),
    LatLng(14.597490, 120.989510),
    LatLng(14.596760, 120.989540),
    LatLng(14.596530, 120.989480),
    LatLng(14.597200, 120.985010),
  ];

  /// Quiapo -> Pasig: [pasigToQuiapo] walked in the opposite direction, so
  /// the two directions can never drift apart (same road, Ramon Magsaysay
  /// Blvd. and Victorio Mapa Blvd. included) and there is only one
  /// polyline to keep in sync with the admin site.
  static final List<LatLng> quiapoToPasig =
      List<LatLng>.unmodifiable(pasigToQuiapo.reversed);

  /// Picks the direction matching one of the app's two exact route strings
  /// ('Pasig – Quiapo' / 'Quiapo – Pasig', see kDriverRoutes in
  /// driver_start_trip_screen.dart) — anything else (null, an
  /// unrecognized value) falls back to the Pasig→Quiapo ordering.
  static List<LatLng> forRoute(String? route) {
    if (route == 'Quiapo – Pasig') return quiapoToPasig;
    return pasigToQuiapo;
  }

  /// How far along [path] (as a fractional segment index — e.g. 4.3 means
  /// 30% of the way from point 4 to point 5) [point]'s closest spot on the
  /// route is. Treats the corridor as locally flat (plain lat/lng
  /// distance, no spherical correction) — at this route's ~13km span that's
  /// within a few percent, plenty accurate for a visual trail.
  static double _projectFraction(LatLng point, List<LatLng> path) {
    var bestDistSq = double.infinity;
    var bestFraction = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final lenSq = dx * dx + dy * dy;
      var t = 0.0;
      if (lenSq > 0) {
        t = (((point.longitude - a.longitude) * dx) +
                ((point.latitude - a.latitude) * dy)) /
            lenSq;
        t = t.clamp(0.0, 1.0);
      }
      final px = a.longitude + t * dx;
      final py = a.latitude + t * dy;
      final distSq = (point.longitude - px) * (point.longitude - px) +
          (point.latitude - py) * (point.latitude - py);
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestFraction = i + t;
      }
    }
    return bestFraction;
  }

  static LatLng _pointAtFraction(double fraction, List<LatLng> path) {
    final i = fraction.floor().clamp(0, path.length - 2);
    final t = fraction - i;
    final a = path[i];
    final b = path[i + 1];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// The stretch of the Pasig–Quiapo corridor between wherever [from] and
  /// [to] each sit closest to it — e.g. a jeepney's live position and the
  /// waiting commuter's own position — as its own polyline, snapped exactly
  /// onto the route rather than jumping to the nearest vertex. Used to draw
  /// each nearby jeepney's approach as a real road-shaped trail instead of
  /// a straight line, alongside the ETA already shown for that option.
  static List<LatLng> trailBetween(LatLng from, LatLng to, {String? route}) {
    final path = forRoute(route);
    final fFrom = _projectFraction(from, path);
    final fTo = _projectFraction(to, path);
    final lo = fFrom < fTo ? fFrom : fTo;
    final hi = fFrom < fTo ? fTo : fFrom;

    final points = <LatLng>[_pointAtFraction(lo, path)];
    for (var i = lo.ceil(); i <= hi.floor(); i++) {
      if (i > lo && i < hi) points.add(path[i]);
    }
    points.add(_pointAtFraction(hi, path));
    return points;
  }
}
