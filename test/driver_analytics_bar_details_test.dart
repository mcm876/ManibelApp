import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:manibelapp_frontend/core/services/driver_operations_log.dart';
import 'package:manibelapp_frontend/features/driver/screens/driver_monthly_analytics_screen.dart';
import 'package:manibelapp_frontend/features/driver/screens/driver_weekly_analytics_screen.dart';
import 'package:manibelapp_frontend/features/driver/widgets/day_expense_chart.dart';

DriverOperationsEntry _entry(
  DateTime day, {
  double earnings = 1000,
  double fuel = 300,
  double other = 100,
}) => DriverOperationsEntry(
  date: day,
  startOdo: 0,
  endOdo: 50,
  totalEarnings: earnings,
  fuelExpense: fuel,
  otherExpenses: other,
);

/// Taps the middle of the bar for [index] out of [count] inside the chart.
Future<void> _tapBar(WidgetTester tester, int index, int count) async {
  final chart = find.byType(DayBarsChart);
  await tester.ensureVisible(chart);
  await tester.pumpAndSettle();
  final rect = tester.getRect(chart);
  final slot = rect.width / count;
  await tester.tapAt(Offset(rect.left + slot * (index + 0.5), rect.bottom - 30));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DayBarsChart', () {
    testWidgets('each bar resolves to its own exact date (31-day month)', (tester) async {
      final selected = <DateTime>[];
      final days = [
        for (var d = 1; d <= 31; d++) DayBarData(date: DateTime(2026, 10, d), entry: null),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DayBarsChart(
                days: days,
                selectedDate: null,
                onSelect: selected.add,
                barWidth: 6,
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(DayBarsChart));
      final slot = rect.width / 31;
      for (var i = 0; i < 31; i++) {
        await tester.tapAt(Offset(rect.left + slot * (i + 0.5), rect.bottom - 20));
      }

      expect(selected.length, 31);
      for (var i = 0; i < 31; i++) {
        expect(selected[i], DateTime(2026, 10, i + 1), reason: 'bar $i');
      }
    });

    testWidgets('dragging across the bars scrubs the selection', (tester) async {
      final selected = <DateTime>[];
      final days = [
        for (var d = 1; d <= 7; d++) DayBarData(date: DateTime(2026, 9, 20 + d), entry: null),
      ];
      DateTime? current;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: DayBarsChart(
                days: days,
                selectedDate: current,
                onSelect: (d) {
                  selected.add(d);
                  setState(() => current = d);
                },
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(DayBarsChart));
      final slot = rect.width / 7;
      // A real drag reports many small moves, not one jump.
      final gesture = await tester.startGesture(Offset(rect.left + slot * 0.5, rect.bottom - 20));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(Offset(slot * 4 / 40, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      // Passed over the days in order and finished on the day under the finger
      // (0.5 + 4 slots -> the 5th bar, Sept 25), never skipping backwards.
      expect(selected.last, DateTime(2026, 9, 25));
      final sorted = [...selected]..sort();
      expect(selected, sorted);
      expect(selected.toSet().length, selected.length, reason: 'no repeated selections while scrubbing');
      expect(selected.first.day, greaterThanOrEqualTo(21));
    });
  });

  group('DayExpenseDetailsCard', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('shows the date, total and the existing categories', (tester) async {
      await tester.pumpWidget(host(
        DayExpenseDetailsCard(
          date: DateTime(2026, 9, 29),
          entry: _entry(DateTime(2026, 9, 29), earnings: 1500, fuel: 400, other: 100),
          isLoading: false,
          loadFailed: false,
          onRetry: () {},
          onClose: () {},
        ),
      ));

      expect(find.text('Tuesday, September 29, 2026'), findsOneWidget);
      expect(find.text('₱500.00'), findsOneWidget); // total expenses
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('₱400.00'), findsOneWidget);
      expect(find.text('Other Expenses'), findsOneWidget);
      expect(find.text('₱100.00'), findsOneWidget);
      expect(find.text('Net Income'), findsOneWidget);
      expect(find.text('₱1,000.00'), findsOneWidget); // 1500 - 400 - 100
    });

    testWidgets('a day with nothing logged says so', (tester) async {
      await tester.pumpWidget(host(
        DayExpenseDetailsCard(
          date: DateTime(2026, 9, 30),
          entry: null,
          isLoading: false,
          loadFailed: false,
          onRetry: () {},
          onClose: () {},
        ),
      ));
      expect(find.text('No expenses recorded for this date.'), findsOneWidget);
      expect(find.textContaining('₱0'), findsNothing);
    });

    testWidgets('loading and failed fetches are never shown as ₱0', (tester) async {
      await tester.pumpWidget(host(
        DayExpenseDetailsCard(
          date: DateTime(2026, 9, 30),
          entry: null,
          isLoading: true,
          loadFailed: false,
          onRetry: () {},
          onClose: () {},
        ),
      ));
      expect(find.text('Loading expense details...'), findsOneWidget);

      var retried = false;
      await tester.pumpWidget(host(
        DayExpenseDetailsCard(
          date: DateTime(2026, 9, 30),
          entry: null,
          isLoading: false,
          loadFailed: true,
          onRetry: () => retried = true,
          onClose: () {},
        ),
      ));
      expect(find.textContaining('Unable to load expense details.'), findsOneWidget);
      expect(find.textContaining('₱0'), findsNothing);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('a logged day with zero expenses shows ₱0.00 and explains it', (tester) async {
      await tester.pumpWidget(host(
        DayExpenseDetailsCard(
          date: DateTime(2026, 9, 28),
          entry: _entry(DateTime(2026, 9, 28), earnings: 800, fuel: 0, other: 0),
          isLoading: false,
          loadFailed: false,
          onRetry: () {},
          onClose: () {},
        ),
      ));
      expect(find.text('No expenses were logged for this day.'), findsOneWidget);
    });
  });

  group('Weekly screen', () {
    testWidgets('tapping a day shows that exact date\'s expenses; other days differ', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final today = DriverOperationsLog.manilaToday();
      final dayA = DateTime(today.year, today.month, today.day - 4);
      final dayB = DateTime(today.year, today.month, today.day - 1);
      await DriverOperationsLog.save(_entry(dayA, earnings: 900, fuel: 250, other: 50));
      await DriverOperationsLog.save(_entry(dayB, earnings: 1200, fuel: 610, other: 90));

      await tester.pumpWidget(const MaterialApp(home: DriverWeeklyAnalyticsScreen()));
      await tester.pumpAndSettle();

      // Window is the 7 days ending today, oldest first: index = 6 - daysAgo.
      await _tapBar(tester, 6 - 4, 7);
      expect(find.text(formatLongDate(dayA)), findsOneWidget);
      expect(find.text('₱300.00'), findsOneWidget); // 250 + 50
      expect(find.text('₱250.00'), findsOneWidget);

      await _tapBar(tester, 6 - 1, 7);
      expect(find.text(formatLongDate(dayB)), findsOneWidget);
      expect(find.text(formatLongDate(dayA)), findsNothing, reason: 'details switched to the new day');
      expect(find.text('₱700.00'), findsOneWidget); // 610 + 90

      // A day in the window with no entry.
      final empty = DateTime(today.year, today.month, today.day - 2);
      await _tapBar(tester, 6 - 2, 7);
      expect(find.text(formatLongDate(empty)), findsOneWidget);
      expect(find.text('No expenses recorded for this date.'), findsOneWidget);

      // Paging to another week drops the selection.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(DayExpenseDetailsCard), findsNothing);
    });
  });

  group('Monthly screen', () {
    testWidgets('tapping a day of the month shows that date\'s expenses', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final today = DriverOperationsLog.manilaToday();
      final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
      final dayOne = DateTime(today.year, today.month, 1);
      final dayFifteen = DateTime(today.year, today.month, 15);
      await DriverOperationsLog.save(_entry(dayOne, earnings: 700, fuel: 111, other: 22));
      await DriverOperationsLog.save(_entry(dayFifteen, earnings: 1400, fuel: 333, other: 44));

      await tester.pumpWidget(const MaterialApp(home: DriverMonthlyAnalyticsScreen()));
      await tester.pumpAndSettle();

      await _tapBar(tester, 14, daysInMonth); // the 15th
      expect(find.text(formatLongDate(dayFifteen)), findsOneWidget);
      expect(find.text('₱377.00'), findsOneWidget); // 333 + 44
      expect(find.text('₱333.00'), findsOneWidget);

      await _tapBar(tester, 0, daysInMonth); // the 1st
      expect(find.text(formatLongDate(dayOne)), findsOneWidget);
      expect(find.text('₱133.00'), findsOneWidget); // 111 + 22

      // A day nothing was logged on (picked so it can't collide with the
      // entries other tests in this file logged relative to today).
      final emptyDay = [
        for (var d = 2; d <= daysInMonth; d++) DateTime(today.year, today.month, d),
      ].firstWhere((d) => DriverOperationsLog.forDate(d) == null);
      await _tapBar(tester, emptyDay.day - 1, daysInMonth);
      expect(find.text(formatLongDate(emptyDay)), findsOneWidget);
      expect(find.text('No expenses recorded for this date.'), findsOneWidget);

      // The existing weekly-bucket chart and totals are still there.
      expect(find.text('Net Income by Week'), findsOneWidget);
      expect(find.text('Net Income by Day'), findsOneWidget);
    });
  });

  group('Manila date handling', () {
    test('today is derived from the Manila calendar, not the device timezone', () {
      final today = DriverOperationsLog.manilaToday();
      final manilaNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      expect(today, DateTime(manilaNow.year, manilaNow.month, manilaNow.day));
    });
  });
}
