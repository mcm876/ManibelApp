import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manibelapp_frontend/features/commuter/widgets/boarding_verification_dialog.dart';

void main() {
  testWidgets('dialog never blocks the screen: GPS failure shows retry/cancel, Cancel closes it once and the page is usable again',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            ElevatedButton(onPressed: () => taps++, child: const Text('Page button')),
            ElevatedButton(
              onPressed: () => showBoardingVerification(context, tripId: 't1', riders: 1),
              child: const Text('Board'),
            ),
          ]),
        ),
      ),
    ));

    // Rapid double tap on Board: still a single dialog.
    await tester.tap(find.text('Board'));
    await tester.pump();
    await tester.tap(find.text('Board'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsOneWidget);

    // No location plugin in tests -> access check fails -> FAILED, not a spinner.
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Boarding not confirmed'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.text('Page button'));
    expect(taps, 1, reason: 'nothing is left covering the page');

    // And boarding can be attempted again afterwards.
    await tester.tap(find.text('Board'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dialog), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
