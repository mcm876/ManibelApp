import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_operations_log.dart';

/// Shared by the Weekly and Monthly analytics screens: a one-bar-per-day net
/// income chart whose bars can be tapped (or scrubbed across) to pick a day,
/// and the details card that shows that exact day's expenses.

const List<String> kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Tuesday, September 29, 2026".
String formatLongDate(DateTime d) =>
    '${kWeekdayNames[d.weekday - 1]}, ${kMonthNames[d.month - 1]} ${d.day}, ${d.year}';

/// "₱1,250.00", with a leading "-" when negative.
String formatPeso(double amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${negative ? '-' : ''}₱$whole.${parts[1]}';
}

/// True when [a] and [b] are the same calendar day (ignores time of day).
bool isSameDay(DateTime? a, DateTime? b) =>
    a != null &&
    b != null &&
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day;

/// One bar: the calendar day it stands for, that day's logged entry (null if
/// nothing was logged), and the label drawn under it (empty = no label).
class DayBarData {
  final DateTime date;
  final DriverOperationsEntry? entry;
  final String label;

  const DayBarData({required this.date, required this.entry, this.label = ''});
}

/// What one bar needs to be drawn, whatever period it stands for: its label,
/// its net income (null = nothing logged, drawn as a flat grey stub), and an
/// optional quick-info tooltip (hover on the web, long-press on a phone).
class _BarSpec {
  final String label;
  final double? net;
  final String? tooltip;

  const _BarSpec({required this.label, required this.net, this.tooltip});
}

/// The tappable bar row shared by the day chart and the week chart. A tap
/// resolves to a bar *index*, and each caller maps that index to the date /
/// week the bar stands for — so nothing about a selection is inferred from
/// anything but the bar that was hit. Dragging a finger across the bars
/// scrubs the selection.
class _BarsRow extends StatelessWidget {
  final List<_BarSpec> bars;
  final int? selectedIndex;
  final ValueChanged<int> onSelectIndex;
  final double barWidth;
  final double height;

  const _BarsRow({
    required this.bars,
    required this.selectedIndex,
    required this.onSelectIndex,
    required this.barWidth,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return SizedBox(height: height);

    final maxMagnitude = bars.fold<double>(0, (max, b) {
      final net = b.net?.abs() ?? 0;
      return net > max ? net : max;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / bars.length;

        int indexAt(double dx) => (dx / slotWidth).floor().clamp(0, bars.length - 1);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onTapUp (not onTapDown): only a real tap selects, so starting a
          // scroll of the page over the chart doesn't.
          onTapUp: (details) => onSelectIndex(indexAt(details.localPosition.dx)),
          onHorizontalDragUpdate: (details) {
            final index = indexAt(details.localPosition.dx);
            if (index != selectedIndex) onSelectIndex(index);
          },
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++)
                  SizedBox(
                    width: slotWidth,
                    child: _BarSlot(
                      spec: bars[i],
                      maxMagnitude: maxMagnitude,
                      barWidth: barWidth,
                      selected: i == selectedIndex,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Net-income-by-day bars (Weekly Analytics). Every bar knows its own date,
/// so a tap resolves to that exact date.
class DayBarsChart extends StatelessWidget {
  final List<DayBarData> days;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelect;
  final double barWidth;
  final double height;

  const DayBarsChart({
    super.key,
    required this.days,
    required this.selectedDate,
    required this.onSelect,
    this.barWidth = 18,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = days.indexWhere((d) => isSameDay(d.date, selectedDate));
    return _BarsRow(
      bars: [
        for (final d in days) _BarSpec(label: d.label, net: d.entry?.netIncome),
      ],
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      onSelectIndex: (i) => onSelect(days[i].date),
      barWidth: barWidth,
      height: height,
    );
  }
}

class _BarSlot extends StatelessWidget {
  final _BarSpec spec;
  final double maxMagnitude;
  final double barWidth;
  final bool selected;

  const _BarSlot({
    required this.spec,
    required this.maxMagnitude,
    required this.barWidth,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final net = spec.net ?? 0;
    final ratio = maxMagnitude > 0
        ? (net.abs() / maxMagnitude).clamp(0.05, 1.0)
        : 0.0;
    final barHeight = spec.net == null ? 4.0 : (ratio * 100).clamp(4.0, 100.0);
    final barColor = net >= 0 ? AppColors.logoBlue : const Color(0xFFE23F3F);

    final slot = Container(
      // The selected bar's whole column is tinted, so it reads as selected
      // even when its bar is only a few pixels tall.
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withValues(alpha: 0.28) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: barWidth,
            height: barHeight,
            decoration: BoxDecoration(
              color: spec.net == null ? const Color(0xFFE6E6E7) : barColor,
              borderRadius: BorderRadius.circular(barWidth > 10 ? 6 : 3),
              border: selected
                  ? Border.all(color: AppColors.textPrimary, width: 1.5)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 12,
            child: Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? AppColors.textPrimary : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );

    final tooltip = spec.tooltip;
    return tooltip == null
        ? slot
        : Tooltip(message: tooltip, triggerMode: TooltipTriggerMode.longPress, child: slot);
  }
}

// ---------------------------------------------------------------------------
// MONTHLY: NET INCOME BY WEEK
// ---------------------------------------------------------------------------

/// One week of the selected month, with everything its bar and its details
/// card show — computed once, here, so the chart value and the details can
/// never disagree.
///
/// Weeks follow the convention the Monthly screen has always used: fixed
/// 7-day blocks counted from the 1st of the month (Week 1 = days 1–7, Week 2
/// = 8–14, …), with a shorter final week when the month doesn't divide evenly.
/// They are not Monday/Sunday-aligned calendar weeks, so a week never
/// reaches into the previous or next month — records outside the selected
/// month are simply never counted.
class WeekSummary {
  /// 1-based ("Week 1").
  final int number;
  final DateTime start;
  final DateTime end;
  final double revenue;
  final double fuel;
  final double otherExpenses;

  /// How many days in this week have a logged entry (0 = nothing recorded —
  /// distinct from a week that was logged and netted exactly ₱0).
  final int loggedDays;

  const WeekSummary({
    required this.number,
    required this.start,
    required this.end,
    required this.revenue,
    required this.fuel,
    required this.otherExpenses,
    required this.loggedDays,
  });

  double get expenses => fuel + otherExpenses;

  /// Revenue minus the logged expenses — the same formula as a day's net
  /// income and the dashboard's Net Income card.
  double get net => revenue - expenses;

  bool get hasData => loggedDays > 0;

  int get dayCount => end.day - start.day + 1;

  String get rangeLabel => start.month == end.month
      ? '${kMonthNames[start.month - 1]} ${start.day} – ${end.day}'
      : '${kMonthNames[start.month - 1]} ${start.day} – ${kMonthNames[end.month - 1]} ${end.day}';
}

/// Buckets the entries of [month] into its weeks (see [WeekSummary]). Only
/// entries dated inside the month are counted; the number of weeks follows
/// the month's real length (Feb 2026 -> 4, a 30/31-day month -> 5).
List<WeekSummary> summarizeMonthWeeks(DateTime month, Iterable<DriverOperationsEntry> entries) {
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final weekCount = (daysInMonth + 6) ~/ 7;

  return [
    for (var w = 0; w < weekCount; w++)
      () {
        final firstDay = 1 + 7 * w;
        final lastDay = (firstDay + 6) > daysInMonth ? daysInMonth : firstDay + 6;
        var revenue = 0.0;
        var fuel = 0.0;
        var other = 0.0;
        var logged = 0;
        for (final e in entries) {
          final d = e.date;
          if (d.year != month.year || d.month != month.month) continue;
          if (d.day < firstDay || d.day > lastDay) continue;
          revenue += e.totalEarnings;
          fuel += e.fuelExpense;
          other += e.otherExpenses;
          logged += 1;
        }
        return WeekSummary(
          number: w + 1,
          start: DateTime(month.year, month.month, firstDay),
          end: DateTime(month.year, month.month, lastDay),
          revenue: revenue,
          fuel: fuel,
          otherExpenses: other,
          loggedDays: logged,
        );
      }(),
  ];
}

/// Net-income-by-week bars (Monthly Analytics). Each bar is one
/// [WeekSummary]; a tap or drag resolves to that week.
class WeekBarsChart extends StatelessWidget {
  final List<WeekSummary> weeks;
  final int? selectedWeek; // WeekSummary.number
  final ValueChanged<int> onSelect;
  final double height;

  const WeekBarsChart({
    super.key,
    required this.weeks,
    required this.selectedWeek,
    required this.onSelect,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = weeks.indexWhere((w) => w.number == selectedWeek);
    return _BarsRow(
      bars: [
        for (final w in weeks)
          _BarSpec(
            label: 'Week ${w.number}',
            net: w.hasData ? w.net : null,
            tooltip: 'Week ${w.number}\n${w.rangeLabel}\n'
                '${w.hasData ? 'Net Income: ${formatPeso(w.net)}' : 'Nothing logged'}',
          ),
      ],
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      onSelectIndex: (i) => onSelect(weeks[i].number),
      barWidth: 26,
      height: height,
    );
  }
}

/// The selected week's details: exact date range, total revenue, total
/// expenses with the app's existing categories, and net income — all from
/// the same [WeekSummary] the bar was drawn from.
class WeekDetailsCard extends StatelessWidget {
  final WeekSummary week;

  /// The first sync hasn't finished — an empty week may just not have
  /// arrived yet, so it isn't reported as empty.
  final bool isLoading;

  /// The last sync failed — an empty week may be a failed fetch rather than
  /// a genuinely empty one, so it isn't reported as ₱0.
  final bool loadFailed;

  final VoidCallback onRetry;
  final VoidCallback onClose;

  const WeekDetailsCard({
    super.key,
    required this.week,
    required this.isLoading,
    required this.loadFailed,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Week ${week.number}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${week.rangeLabel}, ${week.start.year}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 18, color: Colors.black45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    if (!week.hasData) {
      if (isLoading) {
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Loading weekly details...',
              style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
          ],
        );
      }
      if (loadFailed) {
        return Row(
          children: [
            const Expanded(
              child: Text(
                'Unable to load weekly details.\nPlease try again.',
                style: TextStyle(fontSize: 12, color: Color(0xFFB42318), fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        );
      }
      return const Text(
        'No revenue or expenses recorded for this week.',
        style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(label: 'Total Revenue', value: formatPeso(week.revenue)),
        const SizedBox(height: 6),
        _DetailRow(label: 'Total Expenses', value: formatPeso(week.expenses)),
        const Divider(height: 22),
        const Text(
          'Expense Breakdown',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _DetailRow(label: 'Fuel', value: formatPeso(week.fuel)),
        const SizedBox(height: 6),
        _DetailRow(label: 'Other Expenses', value: formatPeso(week.otherExpenses)),
        const Divider(height: 22),
        _DetailRow(
          label: 'Net Income',
          value: formatPeso(week.net),
          emphasize: true,
          valueColor: week.net < 0 ? const Color(0xFFE23F3F) : AppColors.logoBlue,
        ),
        const SizedBox(height: 8),
        Text(
          '${week.loggedDays} of ${week.dayCount} days logged',
          style: const TextStyle(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// The selected day's expenses: total, then the same categories the Daily
/// Operations screen records (Fuel, Other Expenses), then the earnings and
/// net income they feed into — the very entry that Weekly/Monthly totals and
/// the dashboard's Net Income are computed from, so the numbers agree.
class DayExpenseDetailsCard extends StatelessWidget {
  final DateTime date;

  /// The day's logged entry; null = nothing logged for this date.
  final DriverOperationsEntry? entry;

  /// The first sync from the backend hasn't finished — a missing entry may
  /// just not have arrived yet, so it isn't reported as "no expenses".
  final bool isLoading;

  /// The last sync failed — a missing entry may be a failed fetch rather than
  /// a genuinely empty day, so it isn't reported as ₱0 either.
  final bool loadFailed;

  final VoidCallback onRetry;
  final VoidCallback onClose;

  const DayExpenseDetailsCard({
    super.key,
    required this.date,
    required this.entry,
    required this.isLoading,
    required this.loadFailed,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatLongDate(date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 18, color: Colors.black45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _body(),
        ],
      ),
    );
  }

  Widget _body() {
    final e = entry;

    if (e == null) {
      if (isLoading) {
        return const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Loading expense details...',
              style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
          ],
        );
      }
      if (loadFailed) {
        return Row(
          children: [
            const Expanded(
              child: Text(
                'Unable to load expense details.\nPlease try again.',
                style: TextStyle(fontSize: 12, color: Color(0xFFB42318), fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        );
      }
      return const Text(
        'No expenses recorded for this date.',
        style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
      );
    }

    final net = e.netIncome;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Total Expenses',
          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          formatPeso(e.totalExpenses),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        if (e.totalExpenses == 0)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'No expenses were logged for this day.',
              style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 14),
        const Text(
          'Expense Breakdown',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _DetailRow(label: 'Fuel', value: formatPeso(e.fuelExpense)),
        const SizedBox(height: 6),
        _DetailRow(label: 'Other Expenses', value: formatPeso(e.otherExpenses)),
        const Divider(height: 22),
        _DetailRow(label: 'Earnings', value: formatPeso(e.totalEarnings)),
        const SizedBox(height: 6),
        _DetailRow(
          label: 'Net Income',
          value: formatPeso(net),
          emphasize: true,
          valueColor: net < 0 ? const Color(0xFFE23F3F) : AppColors.logoBlue,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: emphasize ? AppColors.textPrimary : Colors.black54,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
