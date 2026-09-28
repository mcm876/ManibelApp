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
Future<void> _tapBar(WidgetTester tester, int index, int count, {Type chartType = DayBarsChart}) async {
  final chart = find.byType(chartType);
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
    DriverOperationsLog.resetForTesting();
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

  group('summarizeMonthWeeks', () {
    final sept = DateTime(2026, 9, 1);

    test('weeks are fixed 7-day blocks from the 1st, with a short last week', () {
      final weeks = summarizeMonthWeeks(sept, const []);

      expect(weeks.length, 5); // September has 30 days
      expect([for (final w in weeks) '${w.start.day}-${w.end.day}'], ['1-7', '8-14', '15-21', '22-28', '29-30']);
      expect(weeks.last.rangeLabel, 'September 29 – 30');
      expect(weeks.first.rangeLabel, 'September 1 – 7');
      expect(weeks.every((w) => !w.hasData), isTrue);
    });

    test('the number of weeks follows the real length of the month', () {
      expect(summarizeMonthWeeks(DateTime(2026, 2, 1), const []).length, 4); // 28 days
      final leap = summarizeMonthWeeks(DateTime(2028, 2, 1), const []); // 29 days
      expect(leap.length, 5);
      expect('${leap.last.start.day}-${leap.last.end.day}', '29-29');
      expect(summarizeMonthWeeks(DateTime(2026, 10, 1), const []).length, 5); // 31 days
    });

    test('each entry lands in exactly the week its date belongs to', () {
      final weeks = summarizeMonthWeeks(sept, [
        _entry(DateTime(2026, 9, 1), earnings: 100, fuel: 10, other: 1), // week 1 (first day)
        _entry(DateTime(2026, 9, 7), earnings: 200, fuel: 20, other: 2), // week 1 (last day)
        _entry(DateTime(2026, 9, 8), earnings: 300, fuel: 30, other: 3), // week 2 (first day)
        _entry(DateTime(2026, 9, 28), earnings: 400, fuel: 40, other: 4), // week 4 (last day)
        _entry(DateTime(2026, 9, 29), earnings: 500, fuel: 50, other: 5), // week 5 (first day)
        _entry(DateTime(2026, 9, 30), earnings: 600, fuel: 60, other: 6), // week 5 (last day)
      ]);

      expect(weeks[0].revenue, 300);
      expect(weeks[0].fuel, 30);
      expect(weeks[0].otherExpenses, 3);
      expect(weeks[0].loggedDays, 2);
      expect(weeks[1].revenue, 300);
      expect(weeks[1].loggedDays, 1);
      expect(weeks[2].hasData, isFalse); // nothing logged in week 3
      expect(weeks[3].revenue, 400);
      expect(weeks[4].revenue, 1100);
      expect(weeks[4].fuel, 110);
      expect(weeks[4].loggedDays, 2);
    });

    test('net income is revenue minus expenses, per week — never a share of the month', () {
      final entries = [
        _entry(DateTime(2026, 9, 3), earnings: 5000, fuel: 1500, other: 500),
        _entry(DateTime(2026, 9, 20), earnings: 800, fuel: 900, other: 0),
      ];
      final weeks = summarizeMonthWeeks(sept, entries);

      expect(weeks[0].net, 3000); // 5000 - (1500 + 500)
      expect(weeks[0].expenses, 2000);
      expect(weeks[2].net, -100); // a losing week is negative
      // The weeks add back up to the month — nothing lost, nothing double counted.
      final monthNet = entries.fold<double>(0, (s, e) => s + e.netIncome);
      expect(weeks.fold<double>(0, (s, w) => s + w.net), monthNet);
    });

    test('records from the neighbouring months are never counted', () {
      final weeks = summarizeMonthWeeks(sept, [
        _entry(DateTime(2026, 8, 31), earnings: 9999, fuel: 1, other: 1), // last day of August
        _entry(DateTime(2026, 10, 1), earnings: 8888, fuel: 1, other: 1), // first day of October
        _entry(DateTime(2026, 9, 15), earnings: 100, fuel: 10, other: 0),
      ]);

      expect(weeks.fold<double>(0, (s, w) => s + w.revenue), 100);
      expect(weeks.fold<int>(0, (s, w) => s + w.loggedDays), 1);
      expect(weeks[0].hasData, isFalse, reason: 'Aug 31 must not leak into Week 1');
      expect(weeks[4].hasData, isFalse, reason: 'Oct 1 must not leak into Week 5');
    });

    test('a logged week that nets exactly zero is distinct from a week with no records', () {
      final weeks = summarizeMonthWeeks(sept, [
        _entry(DateTime(2026, 9, 2), earnings: 500, fuel: 400, other: 100),
      ]);

      expect(weeks[0].hasData, isTrue);
      expect(weeks[0].net, 0);
      expect(weeks[1].hasData, isFalse);
    });
  });

  group('WeekDetailsCard', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    final week = summarizeMonthWeeks(DateTime(2026, 9, 1), [
      _entry(DateTime(2026, 9, 9), earnings: 5000, fuel: 1500, other: 500),
    ])[1];

    testWidgets('shows the exact range, revenue, expenses, breakdown and net', (tester) async {
      await tester.pumpWidget(host(
        WeekDetailsCard(week: week, isLoading: false, loadFailed: false, onRetry: () {}, onClose: () {}),
      ));

      expect(find.text('Week 2'), findsOneWidget);
      expect(find.text('September 8 – 14, 2026'), findsOneWidget);
      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('₱5,000.00'), findsOneWidget);
      expect(find.text('Total Expenses'), findsOneWidget);
      expect(find.text('₱2,000.00'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('₱1,500.00'), findsOneWidget);
      expect(find.text('Other Expenses'), findsOneWidget);
      expect(find.text('₱500.00'), findsOneWidget);
      expect(find.text('Net Income'), findsOneWidget);
      expect(find.text('₱3,000.00'), findsOneWidget);
      expect(find.text('1 of 7 days logged'), findsOneWidget);
    });

    testWidgets('empty week, loading and failed states never show a made-up ₱0', (tester) async {
      final empty = summarizeMonthWeeks(DateTime(2026, 9, 1), const [])[2];

      await tester.pumpWidget(host(
        WeekDetailsCard(week: empty, isLoading: false, loadFailed: false, onRetry: () {}, onClose: () {}),
      ));
      expect(find.text('No revenue or expenses recorded for this week.'), findsOneWidget);
      expect(find.textContaining('₱'), findsNothing);

      await tester.pumpWidget(host(
        WeekDetailsCard(week: empty, isLoading: true, loadFailed: false, onRetry: () {}, onClose: () {}),
      ));
      expect(find.text('Loading weekly details...'), findsOneWidget);

      var retried = false;
      await tester.pumpWidget(host(
        WeekDetailsCard(week: empty, isLoading: false, loadFailed: true, onRetry: () => retried = true, onClose: () {}),
      ));
      expect(find.textContaining('Unable to load weekly details.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });
  });

  group('Monthly screen', () {
    testWidgets('shows Net Income by Week (not by day) and each week bar opens that week', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final today = DriverOperationsLog.manilaToday();
      final month = DateTime(today.year, today.month, 1);
      // Week 1 and Week 2 get known values; Week 3 stays empty.
      await DriverOperationsLog.save(_entry(DateTime(today.year, today.month, 3), earnings: 5000, fuel: 1500, other: 500));
      await DriverOperationsLog.save(_entry(DateTime(today.year, today.month, 4), earnings: 1000, fuel: 200, other: 0));
      await DriverOperationsLog.save(_entry(DateTime(today.year, today.month, 10), earnings: 2000, fuel: 700, other: 100));

      await tester.pumpWidget(const MaterialApp(home: DriverMonthlyAnalyticsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Net Income by Week'), findsOneWidget);
      expect(find.text('Net Income by Day'), findsNothing);
      final weeks = summarizeMonthWeeks(month, DriverOperationsLog.allEntries);
      expect(find.byType(WeekBarsChart), findsOneWidget);
      for (final w in weeks) {
        expect(find.text('Week ${w.number}'), findsWidgets);
      }

      final count = weeks.length;
      await _tapBar(tester, 0, count, chartType: WeekBarsChart); // Week 1
      expect(find.text('${weeks[0].rangeLabel}, ${month.year}'), findsOneWidget);
      expect(find.text('₱6,000.00'), findsOneWidget); // revenue 5000 + 1000
      expect(find.text('₱2,200.00'), findsOneWidget); // expenses 1500+500+200
      expect(find.text('₱1,700.00'), findsOneWidget); // fuel 1500 + 200
      expect(find.text('₱3,800.00'), findsOneWidget); // net 6000 - 2200

      await _tapBar(tester, 1, count, chartType: WeekBarsChart); // Week 2 — everything changes
      expect(find.text('${weeks[1].rangeLabel}, ${month.year}'), findsOneWidget);
      expect(find.text('₱2,000.00'), findsOneWidget); // revenue
      expect(find.text('₱800.00'), findsOneWidget); // expenses 700 + 100
      expect(find.text('₱1,200.00'), findsOneWidget); // net
      expect(find.text('₱3,800.00'), findsNothing, reason: 'Week 1 details are gone');

      await _tapBar(tester, 2, count, chartType: WeekBarsChart); // Week 3 — nothing logged
      expect(find.text('No revenue or expenses recorded for this week.'), findsOneWidget);

      // Paging to another month drops the selection.
      await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(WeekDetailsCard), findsNothing);
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
