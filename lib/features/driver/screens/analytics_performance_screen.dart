import 'package:flutter/material.dart';
import '../services/operations_service.dart';

class AnalyticsPerformanceScreen extends StatefulWidget {
  const AnalyticsPerformanceScreen({super.key});

  @override
  State<AnalyticsPerformanceScreen> createState() => _AnalyticsPerformanceScreenState();
}

class _AnalyticsPerformanceScreenState extends State<AnalyticsPerformanceScreen> {
  final OperationsService _service = OperationsService();

  String _formatBestDayDate(DateTime date) {
    const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'June', 'July', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
    final dayName = days[date.weekday % 7];
    final monthName = months[date.month - 1];
    return '$dayName, $monthName ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    // Shared dynamic records list
    final records = _service.records;

    // Dynamic Calculations with Division-by-Zero Error Safeguards
    final double totalDistance = _service.totalDistance;
    final double totalEarnings = records.fold(0.0, (sum, r) => sum + r.dailyEarnings);
    final double totalFuel = records.fold(0.0, (sum, r) => sum + r.fuelExpense);

    final double avgRevenuePerKm = totalDistance > 0 ? (totalEarnings / totalDistance) : 0.0;
    final double avgFuelCostPerKm = totalDistance > 0 ? (totalFuel / totalDistance) : 0.0;
    final double avgDailyIncome = _service.averageDailyIncome;

    // Dynamic "Best Performing Day" logic based on max Net Income
    DailyOperationRecord? bestRecord;
    if (records.isNotEmpty) {
      bestRecord = records.reduce((curr, next) => curr.netIncome > next.netIncome ? curr : next);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TOP NAVIGATION HEADER
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.black12, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Analytics &',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'Performance',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 2. MONTH SELECTOR HEADER
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 28),
                  SizedBox(width: 16),
                  Text(
                    'June 2026',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(width: 16),
                  Icon(Icons.chevron_right_rounded, size: 28),
                ],
              ),
              const SizedBox(height: 16),

              // 3. EARNINGS TREND LINE CHART
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Earnings Trend (This Month)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: TrendLineChartPainter(
                          points: records.map((r) => r.dailyEarnings).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. METRICS GRID (DYNAMIC VALUES)
              Row(
                children: [
                  Expanded(
                    child: _buildSquareMetricCard(
                      icon: Icons.show_chart_rounded,
                      iconColor: const Color(0xFF1E7538),
                      title: 'Average Revenue\nper km',
                      value: '₱ ${avgRevenuePerKm.toStringAsFixed(2)}/km',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSquareMetricCard(
                      icon: Icons.local_gas_station_rounded,
                      iconColor: const Color(0xFFFF6D00),
                      title: 'Average Fuel Cost\nper km',
                      value: '₱ ${avgFuelCostPerKm.toStringAsFixed(2)}/km',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildSquareMetricCard(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: const Color(0xFFE5A800),
                      title: 'Average Daily\nIncome',
                      value: '₱ ${avgDailyIncome.toStringAsFixed(2)}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSquareMetricCard(
                      icon: Icons.add_road_rounded,
                      iconColor: const Color(0xFF0052CC),
                      title: 'Total Distance\n(This Month)',
                      value: '${totalDistance.toStringAsFixed(0)} km',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 5. DYNAMIC BEST PERFORMING DAY CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFB300),
                      size: 44,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Best Performing Day',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            bestRecord != null
                                ? _formatBestDayDate(bestRecord.date)
                                : 'No entries logged',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bestRecord != null
                                ? '₱ ${bestRecord.netIncome.toStringAsFixed(2)}'
                                : '₱ 0.00',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 6. DYNAMIC PERFORMANCE INSIGHT BANNER
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F3E5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFB4E0BC), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: Color(0xFF1E7538),
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        records.isNotEmpty
                            ? 'Keep it up! Your active entries indicate consistent performance this period.'
                            : 'Log your shifts on the Daily Operations screen to build real-time analytics.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E7538),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSquareMetricCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// 7. DYNAMIC LINE CHART PAINTER
class TrendLineChartPainter extends CustomPainter {
  final List<double> points;

  TrendLineChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPadding = 45.0;
    const double bottomPadding = 25.0;
    final double chartWidth = size.width - leftPadding;
    final double chartHeight = size.height - bottomPadding;

    // Y-Axis Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    const yLabels = ['₱ 2,500', '₱ 2,000', '₱ 1,500', '₱ 1,000'];

    for (int i = 0; i < yLabels.length; i++) {
      final y = (chartHeight / (yLabels.length - 1)) * i;
      textPainter.text = TextSpan(
        text: yLabels[i],
        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w700),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(0, y - 6));
    }

    // Axes
    final axisPaint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1.2;

    canvas.drawLine(const Offset(leftPadding, 0), Offset(leftPadding, chartHeight), axisPaint);
    canvas.drawLine(Offset(leftPadding, chartHeight), Offset(size.width, chartHeight), axisPaint);

    // X-Axis Labels
    const xLabels = ['June 7', 'June 14', 'June 21', 'June 28'];
    final xStep = chartWidth / (xLabels.length - 1);

    for (int i = 0; i < xLabels.length; i++) {
      final x = leftPadding + (xStep * i);
      textPainter.text = TextSpan(
        text: xLabels[i],
        style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w700),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), chartHeight + 6));
    }

    // Dynamically render entered earnings or fallback points
    final displayPoints = (points.length >= 4)
        ? points.sublist(points.length - 4)
        : (points.isNotEmpty ? List.filled(4, points.last) : [1400.0, 1850.0, 1650.0, 2400.0]);

    final linePaint = Paint()
      ..color = const Color(0xFF1E7538)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF1E7538)
      ..style = PaintingStyle.fill;

    final path = Path();

    for (int i = 0; i < displayPoints.length; i++) {
      final x = leftPadding + (xStep * i);
      final normalizedValue = ((displayPoints[i] - 1000) / 1500).clamp(0.0, 1.0);
      final y = chartHeight - (normalizedValue * chartHeight);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, dotPaint);
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}