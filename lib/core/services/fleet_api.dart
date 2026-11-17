import 'api_client.dart';
import 'driver_session.dart';

/// A jeepney this driver is authorized to drive (GET /api/driver/vehicles).
class DriverVehicle {
  final String id;
  final String plateNumber;

  /// Registered seating capacity; null until an operator enters it — such a
  /// vehicle can't start a trip.
  final int? seatingCapacity;
  final bool inUse;
  final bool inUseByMe;

  const DriverVehicle({
    required this.id,
    required this.plateNumber,
    required this.seatingCapacity,
    required this.inUse,
    required this.inUseByMe,
  });

  factory DriverVehicle.fromJson(Map<String, dynamic> json) => DriverVehicle(
        id: json['id'] as String,
        plateNumber: json['plateNumber'] as String,
        seatingCapacity: (json['seatingCapacity'] as num?)?.toInt(),
        inUse: json['inUse'] as bool? ?? false,
        inUseByMe: json['inUseByMe'] as bool? ?? false,
      );

  bool get canStart => seatingCapacity != null && !inUse;
}

enum OccupancyLevel { normal, nearlyFull, full, unknown }

/// Live passenger count for one trip (server-computed; see lib/occupancy.ts).
class TripOccupancy {
  final int appPassengers;
  final int manualPassengers;
  final int totalPassengers;
  final int? seatingCapacity;
  final int? remainingSeats;
  final OccupancyLevel level;

  const TripOccupancy({
    required this.appPassengers,
    required this.manualPassengers,
    required this.totalPassengers,
    required this.seatingCapacity,
    required this.remainingSeats,
    required this.level,
  });

  factory TripOccupancy.fromJson(Map<String, dynamic> json) => TripOccupancy(
        appPassengers: (json['appPassengers'] as num?)?.toInt() ?? 0,
        manualPassengers: (json['manualPassengers'] as num?)?.toInt() ?? 0,
        totalPassengers: (json['totalPassengers'] as num?)?.toInt() ?? 0,
        seatingCapacity: (json['seatingCapacity'] as num?)?.toInt(),
        remainingSeats: (json['remainingSeats'] as num?)?.toInt(),
        level: switch (json['status']) {
          'NORMAL' => OccupancyLevel.normal,
          'NEARLY_FULL' => OccupancyLevel.nearlyFull,
          'FULL' => OccupancyLevel.full,
          _ => OccupancyLevel.unknown,
        },
      );
}

/// A temporary trip-start restriction (judged by the server's clock).
class TripRestriction {
  final String reason;
  final DateTime startsAt;
  final DateTime expiresAt;
  final int durationMinutes;

  const TripRestriction({
    required this.reason,
    required this.startsAt,
    required this.expiresAt,
    required this.durationMinutes,
  });

  factory TripRestriction.fromJson(Map<String, dynamic> json) => TripRestriction(
        reason: json['reason'] as String? ?? '',
        startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      );
}

class DriverStatusInfo {
  final TripRestriction? restriction;
  final String disciplinaryStatus;
  final int pendingExplanations;

  const DriverStatusInfo({
    required this.restriction,
    required this.disciplinaryStatus,
    required this.pendingExplanations,
  });

  bool get suspended => disciplinaryStatus == 'SUSPENDED';
}

class ShortTripIncidentInfo {
  final String id;
  final String? route;
  final String? intendedDestination;
  final DateTime occurredAt;
  final String? description;
  final String status;
  final String? explanation;
  final String? reviewNote;
  final bool canExplain;

  const ShortTripIncidentInfo({
    required this.id,
    required this.route,
    required this.intendedDestination,
    required this.occurredAt,
    required this.description,
    required this.status,
    required this.explanation,
    required this.reviewNote,
    required this.canExplain,
  });

  factory ShortTripIncidentInfo.fromJson(Map<String, dynamic> json) => ShortTripIncidentInfo(
        id: json['id'] as String,
        route: json['route'] as String?,
        intendedDestination: json['intendedDestination'] as String?,
        occurredAt: DateTime.parse(json['occurredAt'] as String).toLocal(),
        description: json['description'] as String?,
        status: json['status'] as String,
        explanation: json['explanation'] as String?,
        reviewNote: json['reviewNote'] as String?,
        canExplain: json['canExplain'] as bool? ?? false,
      );

  String get statusLabel => switch (status) {
        'PENDING_EXPLANATION' => 'Explanation needed',
        'EXPLAINED' => 'Explanation sent',
        'UNDER_REVIEW' => 'Under review',
        'CONFIRMED' => 'Confirmed',
        'DISMISSED' => 'Dismissed',
        _ => status,
      };
}

/// True when [e] means the request never reached the server.
bool isOfflineError(Object e) => e is ApiException && e.statusCode == null;

/// Driver-side calls for the vehicle / passenger-count / discipline features.
/// Every function throws [ApiException] on failure — callers show the
/// backend's own message and never report success unless these return.
class FleetApi {
  const FleetApi._();

  static String? get _token => DriverSession.instance.authToken;

  static Future<List<DriverVehicle>> fetchVehicles() async {
    final response = await ApiClient.get('/api/driver/vehicles', token: _token);
    final raw = response['vehicles'] as List<dynamic>? ?? const [];
    return raw.map((v) => DriverVehicle.fromJson(v as Map<String, dynamic>)).toList();
  }

  static Future<DriverStatusInfo> fetchStatus() async {
    final response = await ApiClient.get('/api/driver/me/restriction', token: _token);
    final restriction = response['restriction'] as Map<String, dynamic>?;
    return DriverStatusInfo(
      restriction: restriction == null ? null : TripRestriction.fromJson(restriction),
      disciplinaryStatus: response['disciplinaryStatus'] as String? ?? 'NONE',
      pendingExplanations: (response['pendingExplanations'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<TripOccupancy?> fetchOccupancy(String tripId) async {
    final response = await ApiClient.get('/api/driver/trips/$tripId/occupancy', token: _token);
    final occ = response['occupancy'] as Map<String, dynamic>?;
    return occ == null ? null : TripOccupancy.fromJson(occ);
  }

  /// +1 / -1 for a passenger who isn't using the app. [requestId] makes a
  /// double tap or a retry count once.
  static Future<TripOccupancy> adjustManual(String tripId, int delta, {required String requestId}) async {
    final response = await ApiClient.post(
      '/api/driver/trips/$tripId/passengers',
      {'delta': delta, 'clientRequestId': requestId},
      token: _token,
    );
    return TripOccupancy.fromJson(response['occupancy'] as Map<String, dynamic>);
  }

  static Future<TripOccupancy> undoManual(String tripId) async {
    final response = await ApiClient.post('/api/driver/trips/$tripId/passengers/undo', {}, token: _token);
    return TripOccupancy.fromJson(response['occupancy'] as Map<String, dynamic>);
  }

  static Future<List<ShortTripIncidentInfo>> fetchIncidents() async {
    final response = await ApiClient.get('/api/driver/short-trip-incidents', token: _token);
    final raw = response['incidents'] as List<dynamic>? ?? const [];
    return raw.map((i) => ShortTripIncidentInfo.fromJson(i as Map<String, dynamic>)).toList();
  }

  static Future<ShortTripIncidentInfo> submitExplanation(String incidentId, String explanation) async {
    final response = await ApiClient.patch(
      '/api/driver/short-trip-incidents/$incidentId/explanation',
      {'explanation': explanation},
      token: _token,
    );
    return ShortTripIncidentInfo.fromJson(response['incident'] as Map<String, dynamic>);
  }
}
