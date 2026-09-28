import 'package:latlong2/latlong.dart';

/// A fixed, real road-following polyline of the officially-registered
/// Pasig-Quiapo PUJ route (DOTr/Sakay route DOTR:R_SAKAY_2018_PUJ_657 —
/// https://explore.sakay.ph/routes/DOTR:R_SAKAY_2018_PUJ_657): Caruncho
/// Ave./Market Ave., Pasig <-> Arlegui / Quiapo, Manila via Shaw Blvd.,
/// Victorio Mapa Blvd. (VMAPA) and Ramon Magsaysay Blvd.
///
/// Sakay publishes this route as ONE trip shape (T_SAKAY_2018_1316) that runs
/// Pasig -> Quiapo and then back to Pasig, and that shape is stored here once,
/// exactly as published (vertices simplified with Douglas-Peucker at ~3 m,
/// nothing added or re-traced). Both directions are cut from it, so there is a
/// single source of truth:
///  - the first [_pasigToQuiapoPointCount] points are the Pasig -> Quiapo leg
///    (ending at Arlegui);
///  - the rest are the Quiapo -> Pasig leg (starting on Quezon Blvd./Recto).
/// The return leg follows the same corridor (Ramon Magsaysay Blvd. <-> VMAPA
/// <-> Shaw Blvd.) but is NOT a mechanical reversal of the outbound leg:
/// Sakay's own return trip differs from it in four short places where one-way
/// streets force a different block (downtown Quiapo/Recto-Legarda, the Old
/// Sta. Mesa / Reposo St. approach to VMAPA, and the Pasig terminal loop). A
/// jeepney cannot drive those against traffic, so the published return leg is
/// used as-is. Kept identical to the admin site's admin/src/lib/routePath.ts.
/// Used only to draw the route line and a visual "trail" on the maps (see
/// [trailBetween]); it plays no part in the ETA numbers themselves, which
/// stay the server's own straight-line estimate (see GET
/// /commuter/nearby-jeepneys' own doc comment).
class RoutePath {
  RoutePath._();

  static const List<LatLng> _sakayShape = [
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
    LatLng(14.599490, 120.984350),
    LatLng(14.601210, 120.984670),
    LatLng(14.601430, 120.984790),
    LatLng(14.601920, 120.984930),
    LatLng(14.602860, 120.985130),
    LatLng(14.602950, 120.985200),
    LatLng(14.602980, 120.985300),
    LatLng(14.600320, 120.990960),
    LatLng(14.600940, 120.991650),
    LatLng(14.601440, 120.992560),
    LatLng(14.601500, 120.992750),
    LatLng(14.601470, 120.993040),
    LatLng(14.601230, 120.993880),
    LatLng(14.600570, 120.995790),
    LatLng(14.600500, 120.996280),
    LatLng(14.600780, 120.997120),
    LatLng(14.601060, 120.998530),
    LatLng(14.601190, 121.000400),
    LatLng(14.601730, 121.006060),
    LatLng(14.601920, 121.008690),
    LatLng(14.602270, 121.011760),
    LatLng(14.602490, 121.014490),
    LatLng(14.602670, 121.015540),
    LatLng(14.602660, 121.015770),
    LatLng(14.602540, 121.015950),
    LatLng(14.600260, 121.016710),
    LatLng(14.600150, 121.016810),
    LatLng(14.599880, 121.015970),
    LatLng(14.597490, 121.016730),
    LatLng(14.597660, 121.017600),
    LatLng(14.597570, 121.017650),
    LatLng(14.597420, 121.017850),
    LatLng(14.595940, 121.019900),
    LatLng(14.595930, 121.019980),
    LatLng(14.596160, 121.020460),
    LatLng(14.594190, 121.025560),
    LatLng(14.594100, 121.025690),
    LatLng(14.593640, 121.026950),
    LatLng(14.593660, 121.027090),
    LatLng(14.593230, 121.028120),
    LatLng(14.592750, 121.029040),
    LatLng(14.592260, 121.029840),
    LatLng(14.590400, 121.033990),
    LatLng(14.590050, 121.034590),
    LatLng(14.589410, 121.035390),
    LatLng(14.589550, 121.039840),
    LatLng(14.589480, 121.040430),
    LatLng(14.589090, 121.042000),
    LatLng(14.588970, 121.042060),
    LatLng(14.588890, 121.042260),
    LatLng(14.588960, 121.042400),
    LatLng(14.588060, 121.044750),
    LatLng(14.587360, 121.046260),
    LatLng(14.586990, 121.046770),
    LatLng(14.584880, 121.049360),
    LatLng(14.583490, 121.050920),
    LatLng(14.574960, 121.060920),
    LatLng(14.573890, 121.062110),
    LatLng(14.570310, 121.066390),
    LatLng(14.570150, 121.066460),
    LatLng(14.569740, 121.066470),
    LatLng(14.563750, 121.065380),
    LatLng(14.563440, 121.065380),
    LatLng(14.563240, 121.065510),
    LatLng(14.563130, 121.065740),
    LatLng(14.562920, 121.066520),
    LatLng(14.562830, 121.067240),
    LatLng(14.562880, 121.068070),
    LatLng(14.563110, 121.068780),
    LatLng(14.563370, 121.069180),
    LatLng(14.564310, 121.069780),
    LatLng(14.565210, 121.070210),
    LatLng(14.566000, 121.070450),
    LatLng(14.566250, 121.071110),
    LatLng(14.566280, 121.071290),
    LatLng(14.566250, 121.072000),
    LatLng(14.566020, 121.075650),
    LatLng(14.565930, 121.075650),
    LatLng(14.565910, 121.075930),
    LatLng(14.565730, 121.075940),
    LatLng(14.565710, 121.076070),
    LatLng(14.564340, 121.075800),
    LatLng(14.562550, 121.076080),
    LatLng(14.561940, 121.076290),
    LatLng(14.561420, 121.076530),
    LatLng(14.560790, 121.076560),
    LatLng(14.560660, 121.077380),
    LatLng(14.560720, 121.077540),
    LatLng(14.560820, 121.077600),
    LatLng(14.559730, 121.080610),
    LatLng(14.559080, 121.080450),
    LatLng(14.559010, 121.080560),
    LatLng(14.557520, 121.084640),
    LatLng(14.557780, 121.084740),
    LatLng(14.557800, 121.084690),
    LatLng(14.557850, 121.084540),
    LatLng(14.557660, 121.084460),
  ];

  /// How many points at the start of [_sakayShape] belong to the
  /// Pasig -> Quiapo leg.
  static const int _pasigToQuiapoPointCount = 116;

  /// Pasig -> Quiapo (Sakay's outbound leg).
  static final List<LatLng> pasigToQuiapo = List<LatLng>.unmodifiable(
    _sakayShape.sublist(0, _pasigToQuiapoPointCount),
  );

  /// Quiapo -> Pasig (Sakay's published return leg — see the class comment for
  /// why this is not simply [pasigToQuiapo] reversed).
  static final List<LatLng> quiapoToPasig = List<LatLng>.unmodifiable(
    _sakayShape.sublist(_pasigToQuiapoPointCount),
  );

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
