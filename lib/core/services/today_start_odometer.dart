import 'package:shared_preferences/shared_preferences.dart';

import 'driver_operations_log.dart';

/// The odometer reading the driver entered when they started today's FIRST
/// trip (see DriverActiveTrip.startTrip) — kept on the phone so the Daily
/// Operations screen can show it as "Start (km)" straight away, even offline.
/// The backend has the same value on the trip itself
/// (GET /api/driver/today-stats -> startingOdometerToday); this local copy is
/// just the instant one. "Today" is the Manila calendar day, same as the
/// daily log.
class TodayStartOdometer {
  TodayStartOdometer._();

  static const _kValue = 'driver_today_start_odometer';
  static const _kDay = 'driver_today_start_odometer_day';

  static String _todayKey() {
    final d = DriverOperationsLog.manilaToday();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Saves [km] unless a reading was already recorded today — later trips the
  /// same day must not replace the day's starting reading.
  static Future<void> recordIfFirst(double km) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kDay) == _todayKey() && prefs.getDouble(_kValue) != null) {
        return;
      }
      await prefs.setString(_kDay, _todayKey());
      await prefs.setDouble(_kValue, km);
    } catch (_) {
      // Purely a convenience copy — the backend has the real one.
    }
  }

  /// Today's starting odometer, or null if none was recorded today.
  static Future<double?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kDay) != _todayKey()) return null;
      return prefs.getDouble(_kValue);
    } catch (_) {
      return null;
    }
  }
}
