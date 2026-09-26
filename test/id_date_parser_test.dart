import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/core/services/id_date_parser.dart';

void main() {
  test('reads labelled birth and expiry dates', () {
    final d = parseIdDates("DRIVER'S LICENSE\nBirth Date\n1990/05/21\nExpiration Date: 2031-08-30");
    expect(toIsoDate(d.birthDate!), '1990-05-21');
    expect(toIsoDate(d.expiryDate!), '2031-08-30');
  });

  test('handles month-name and dd/mm formats', () {
    final d = parseIdDates('Date of Birth: MAY 21, 1990\nValid Until 30/08/2020');
    expect(toIsoDate(d.birthDate!), '1990-05-21');
    expect(toIsoDate(d.expiryDate!), '2020-08-30');
  });

  test('does not guess unlabelled dates', () {
    final d = parseIdDates('Juan Dela Cruz\n1990-05-21');
    expect(d.birthDate, isNull);
    expect(d.expiryDate, isNull);
  });
}
