/// One direction of a jeepney route: where it starts, where it ends, and the
/// stops in between, in travel order.
class RouteDirection {
  /// The exact string riders/drivers pick and the backend + admin site match on,
  /// e.g. "Pasig – Quiapo" (en dash, not a hyphen).
  final String name;
  final String origin;
  final String destination;
  final List<String> stops;

  const RouteDirection({
    required this.name,
    required this.origin,
    required this.destination,
    required this.stops,
  });

  /// Short "A → B" label for cards and chips.
  String get terminalsLabel => '$origin → $destination';
}

/// Pasig - Quiapo (PUJ), from the DOTr/Sakay route data:
/// https://explore.sakay.ph/routes/DOTR:R_SAKAY_2018_PUJ_657
/// Runs 6:00 AM – 11:00 PM daily. Sakay lists the fare as ₱13.00 for the
/// first 4 km + ₱1.80 per succeeding km; the app itself still charges the
/// flat fares in fare_calculator.dart.
class JeepneyRoutes {
  const JeepneyRoutes._();

  static const pasigToQuiapo = RouteDirection(
    name: 'Pasig – Quiapo',
    origin: 'Caruncho Ave. / Market Ave., Pasig',
    destination: 'Arlegui, Manila',
    stops: [
      'Caruncho Ave. / Market Ave. Intersection',
      'Sabater Hospital',
      'Caruncho Ave. / F. Manalo Intersection',
      'Pasig City Library',
      'A. Luna St. / Caruncho Ave. Intersection',
      'UCPB',
      'A. Mabini St. / Blumentritt St.',
      'C. Raymundo / Pasig Blvd. Ext.',
      'Bagong Ilog - URC',
      'Rizal Medical Center',
      'Nice Hotel, Shaw Blvd.',
      'BDO Shaw / Danny Floro',
      'Capitol Commons',
      'Shaw Blvd. / Pioneer',
      'S. Laurel / Shaw Blvd.',
      'Shaw Blvd. / Luna Mencias',
      'Shaw Blvd. / Acacia Ln.',
      'M. Yulo / Shaw Blvd.',
      'Lawson / Shaw Blvd.',
      'Kalentong / Shaw Blvd.',
      'Our Lady of Lourdes Hospital',
      'Victorio Mapa Blvd.',
      'Ramon Magsaysay Blvd.',
      'Jollibee Figueras / Bustillos',
      'Legarda',
      'Arlegui',
    ],
  );

  static const quiapoToPasig = RouteDirection(
    name: 'Quiapo – Pasig',
    origin: 'Quezon Blvd., Manila',
    destination: 'Caruncho Ave., Pasig',
    stops: [
      'Claro M. Recto Ave. / Quezon Blvd. Intersection',
      'Claro M. Recto Ave. / Nicanor Reyes St. Intersection',
      'Jollibee Figueras / Legarda / Bustillos Intersection',
      'Ramon Magsaysay Blvd.',
      'Pureza Extension / Ramon Magsaysay Blvd. Intersection',
      'Paltok / Ramon Magsaysay Blvd. Intersection',
      'Old Sta. Mesa',
      'Reposo St. cor. Old Santa Mesa St.',
      'Valenzuela Extension / Victorio Mapa Blvd.',
      'Our Lady of Lourdes Hospital',
      'Shaw Blvd.',
      'Pasig Blvd.',
      'A. Mabini St. / Blumentritt St.',
      'A. Luna St. / Caruncho Ave. Intersection',
      'Pasig City Library, Caruncho Ave.',
      'Caruncho Ave.',
    ],
  );

  /// Every route the app services, in display order.
  static const all = [pasigToQuiapo, quiapoToPasig];

  static List<String> get names => [for (final r in all) r.name];

  /// The route with this display [name], or null (e.g. for old saved trips).
  static RouteDirection? byName(String name) {
    for (final r in all) {
      if (r.name == name) return r;
    }
    return null;
  }
}
