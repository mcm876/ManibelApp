import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/core/constants/qr_constants.dart';
import 'package:manibelapp_frontend/features/commuter/screens/scan_driver_qr_screen.dart';

void main() {
  test('driverTokenFromQr extracts the token from a driver QR', () {
    expect(driverTokenFromQr('${kDriverQrPrefix}abc123'), 'abc123');
    expect(driverTokenFromQr('  ${kDriverQrPrefix}abc123\n'), 'abc123');
  });

  test('driverTokenFromQr rejects anything that is not a driver QR', () {
    for (final bad in ['', 'https://example.com', 'abc123', kDriverQrPrefix, '$kDriverQrPrefix  ']) {
      expect(driverTokenFromQr(bad), isNull, reason: 'input "$bad"');
    }
  });
}
