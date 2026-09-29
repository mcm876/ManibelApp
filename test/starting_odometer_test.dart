import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/features/driver/widgets/starting_odometer_dialog.dart';

void main() {
  group('parseOdometerKm', () {
    test('accepts whole numbers, decimals and thousands separators', () {
      expect(parseOdometerKm('12543'), 12543);
      expect(parseOdometerKm('12543.5'), 12543.5);
      expect(parseOdometerKm(' 12,543 '), 12543);
      expect(parseOdometerKm('0'), 0);
    });

    test('rejects empty, letters, negatives and malformed numbers', () {
      for (final bad in ['', '  ', 'abc', '12a', '-5', '1.2.3', '.', '5.', '1e5', '12.345']) {
        expect(parseOdometerKm(bad), isNull, reason: 'input "$bad"');
      }
    });

    test('rejects absurdly large values', () {
      expect(parseOdometerKm('10000000'), isNull);
      expect(parseOdometerKm('9999999'), 9999999);
    });
  });

  test('formatOdometerKm drops a trailing .0', () {
    expect(formatOdometerKm(12543), '12543');
    expect(formatOdometerKm(12543.5), '12543.5');
  });
}
