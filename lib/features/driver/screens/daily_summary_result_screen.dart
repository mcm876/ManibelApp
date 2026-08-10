import 'package:flutter/material.dart';
import '../services/operations_service.dart';
import 'weekly_operations_report_screen.dart';

class DailySummaryResultScreen extends StatelessWidget {
  final double startOdometer;
  final double endOdometer;
  final double distanceTraveled;
  final double dailyEarnings;
  final double fuelExpense;
  final double otherExpenses;

  const DailySummaryResultScreen({
    super.key,
    required this.startOdometer,
    required this.endOdometer,
    required this.distanceTraveled,
    required this.dailyEarnings,
    required this.fuelExpense,
    required this.otherExpenses,
  });

  String _getFormattedDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _getDayOfWeek(DateTime date) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return days[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic math calculations
    final double totalExpenses = fuelExpense + otherExpenses;
    final double revenuePerKm = distanceTraveled > 0 ? (dailyEarnings / distanceTraveled) : 0.0;
    final double fuelCostPerKm = distanceTraveled > 0 ? (fuelExpense / distanceTraveled) : 0.0;
    final double netIncome = dailyEarnings - totalExpenses;

    final DateTime now = DateTime.now();
    final String formattedDate = _getFormattedDate(now);
    final String dayOfWeek = _getDayOfWeek(now);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back Button & Title
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
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Summary',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                      Text(
                        'Result',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Date Header
              Text(
                formattedDate,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
              Text(
                dayOfWeek,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const SizedBox(height: 20),

              // Dynamic Metric Cards
              _buildMetricCard(
                icon: Icons.add_road_rounded,
                iconColor: const Color(0xFF0052CC),
                label: 'Distance Traveled',
                value: '${distanceTraveled.toStringAsFixed(0)} km',
                bgColor: const Color(0xFFF2F2F2),
                borderColor: const Color(0xFFD0D0D0),
              ),
              const SizedBox(height: 12),

              _buildMetricCard(
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFF2E7D32),
                label: 'Daily Earnings',
                value: '₱ ${dailyEarnings.toStringAsFixed(2)}',
                bgColor: const Color(0xFFF2F2F2),
                borderColor: const Color(0xFFD0D0D0),
              ),
              const SizedBox(height: 12),

              _buildMetricCard(
                icon: Icons.local_gas_station_rounded,
                iconColor: const Color(0xFFFF5252),
                label: 'Fuel Expense',
                value: '₱ ${fuelExpense.toStringAsFixed(2)}',
                bgColor: const Color(0xFFF2F2F2),
                borderColor: const Color(0xFFD0D0D0),
              ),
              const SizedBox(height: 12),

              _buildMetricCard(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: const Color(0xFFE5A800),
                label: 'Total Expenses',
                value: '₱ ${totalExpenses.toStringAsFixed(2)}',
                bgColor: const Color(0xFFF2F2F2),
                borderColor: const Color(0xFFD0D0D0),
              ),
              const SizedBox(height: 12),

              _buildMetricCard(
                icon: Icons.show_chart_rounded,
                iconColor: const Color(0xFF1E7538),
                label: 'Revenue per km',
                value: '₱ ${revenuePerKm.toStringAsFixed(2)}/km',
                bgColor: const Color(0xFFE2F3E5),
                borderColor: const Color(0xFFB4E0BC),
              ),
              const SizedBox(height: 12),

              _buildMetricCard(
                icon: Icons.local_gas_station_outlined,
                iconColor: const Color(0xFF1E7538),
                label: 'Fuel Cost per km',
                value: '₱ ${fuelCostPerKm.toStringAsFixed(2)}/km',
                bgColor: const Color(0xFFE2F3E5),
                borderColor: const Color(0xFFB4E0BC),
              ),
              const SizedBox(height: 12),

              _buildMetricCard(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: const Color(0xFF1E7538),
                label: 'Net Income',
                value: '₱ ${netIncome.toStringAsFixed(2)}',
                bgColor: const Color(0xFFE2F3E5),
                borderColor: const Color(0xFFB4E0BC),
              ),
              const SizedBox(height: 28),

              // Dynamic Save Record Action
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    try {
                      // 1. Save new record to dynamic global state
                      final newRecord = DailyOperationRecord(
                        date: DateTime.now(),
                        startOdometer: startOdometer,
                        endOdometer: endOdometer,
                        dailyEarnings: dailyEarnings,
                        fuelExpense: fuelExpense,
                        otherExpenses: otherExpenses,
                      );

                      OperationsService().addRecord(newRecord);

                      // 2. Navigate directly to Weekly Operations Report
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WeeklyOperationsReportScreen(),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error saving record: ${e.toString()}'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0038FF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save Record',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}