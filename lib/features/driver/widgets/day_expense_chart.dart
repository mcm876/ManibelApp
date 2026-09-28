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

/// Net-income-by-day bars. Every bar knows its own date, so a tap resolves to
/// that exact date — nothing is inferred from an index or a total. Tapping
/// selects (via [onSelect]); dragging a finger across the bars scrubs the
/// selection, which keeps the thin bars of a 31-day month easy to hit.
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
    if (days.isEmpty) return SizedBox(height: height);

    final maxMagnitude = days.fold<double>(0, (max, d) {
      final net = d.entry?.netIncome.abs() ?? 0;
      return net > max ? net : max;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / days.length;

        DateTime dateAt(double dx) {
          final index = (dx / slotWidth).floor().clamp(0, days.length - 1);
          return days[index].date;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onTapUp (not onTapDown): only a real tap selects, so starting a
          // scroll of the page over the chart doesn't.
          onTapUp: (details) => onSelect(dateAt(details.localPosition.dx)),
          onHorizontalDragUpdate: (details) {
            final date = dateAt(details.localPosition.dx);
            if (!isSameDay(date, selectedDate)) onSelect(date);
          },
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  SizedBox(
                    width: slotWidth,
                    child: _DayBarSlot(
                      data: day,
                      maxMagnitude: maxMagnitude,
                      barWidth: barWidth,
                      selected: isSameDay(day.date, selectedDate),
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

class _DayBarSlot extends StatelessWidget {
  final DayBarData data;
  final double maxMagnitude;
  final double barWidth;
  final bool selected;

  const _DayBarSlot({
    required this.data,
    required this.maxMagnitude,
    required this.barWidth,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final entry = data.entry;
    final net = entry?.netIncome ?? 0;
    final ratio = maxMagnitude > 0
        ? (net.abs() / maxMagnitude).clamp(0.05, 1.0)
        : 0.0;
    final barHeight = entry == null ? 4.0 : (ratio * 100).clamp(4.0, 100.0);
    final barColor = net >= 0 ? AppColors.logoBlue : const Color(0xFFE23F3F);

    return Container(
      // The selected day's whole column is tinted, so it reads as selected
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
              color: entry == null ? const Color(0xFFE6E6E7) : barColor,
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
              data.label,
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
