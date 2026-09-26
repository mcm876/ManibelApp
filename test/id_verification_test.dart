import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/core/services/id_date_parser.dart';
import 'package:manibelapp_frontend/core/services/id_verification.dart';

void main() {
  final now = DateTime(2026, 9, 26);

  test('rejects an expired ID', () {
    final dates = IdDates(birthDate: DateTime.utc(1990, 5, 21), expiryDate: DateTime.utc(2020, 1, 1));
    expect(IdVerification.rejectionMessage(dates, hasExpiry: true, now: now), contains('expired'));
  });

  test('an ID is still valid on its expiry date', () {
    final dates = IdDates(birthDate: DateTime.utc(1990, 5, 21), expiryDate: DateTime.utc(2026, 9, 26));
    expect(IdVerification.rejectionMessage(dates, hasExpiry: true, now: now), isNull);
  });

  test('ignores expiry for ID types without one', () {
    final dates = IdDates(birthDate: DateTime.utc(1990, 5, 21), expiryDate: DateTime.utc(2020, 1, 1));
    expect(IdVerification.rejectionMessage(dates, hasExpiry: false, now: now), isNull);
  });

  test('rejects a holder under 18, accepts one who just turned 18', () {
    final under = IdDates(birthDate: DateTime.utc(2008, 9, 27));
    final exactly = IdDates(birthDate: DateTime.utc(2008, 9, 26));
    expect(IdVerification.rejectionMessage(under, hasExpiry: false, now: now), contains('under 18'));
    expect(IdVerification.rejectionMessage(exactly, hasExpiry: false, now: now), isNull);
  });

  test('unreadable dates are not rejected client-side (backend sends to review)', () {
    expect(IdVerification.rejectionMessage(const IdDates(), hasExpiry: true, now: now), isNull);
  });

  test('explains why a submission needs manual review', () {
    expect(IdVerification.reviewExplanation(['FACE_NOT_MATCHED']), contains("didn't match"));
    expect(IdVerification.reviewExplanation([]), isEmpty);
  });
}
