import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/core/services/today_start_odometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing recorded -> null', () async {
    expect(await TodayStartOdometer.read(), isNull);
  });

  test('first trip of the day sets it; later trips do not replace it', () async {
    await TodayStartOdometer.recordIfFirst(12543);
    expect(await TodayStartOdometer.read(), 12543);
    await TodayStartOdometer.recordIfFirst(12600.5);
    expect(await TodayStartOdometer.read(), 12543);
  });

  test("a reading from another day is ignored", () async {
    SharedPreferences.setMockInitialValues({
      'driver_today_start_odometer': 999.0,
      'driver_today_start_odometer_day': '2000-1-1',
    });
    expect(await TodayStartOdometer.read(), isNull);
    await TodayStartOdometer.recordIfFirst(5000);
    expect(await TodayStartOdometer.read(), 5000);
  });
}
