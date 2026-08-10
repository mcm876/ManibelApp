import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:manibelapp_frontend/features/driver/screens/daily_summary_result_screen.dart';

class DailyOperationsScreen extends StatefulWidget {
  const DailyOperationsScreen({super.key});

  @override
  State<DailyOperationsScreen> createState() => _DailyOperationsScreenState();
}

class _DailyOperationsScreenState extends State<DailyOperationsScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _startOdometerController = TextEditingController();
  final TextEditingController _endOdometerController = TextEditingController();
  final TextEditingController _earningsController = TextEditingController();
  final TextEditingController _fuelController = TextEditingController();
  final TextEditingController _otherExpensesController = TextEditingController();

  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _startOdometerController.addListener(_checkFormState);
    _endOdometerController.addListener(_checkFormState);
    _earningsController.addListener(_checkFormState);
    _fuelController.addListener(_checkFormState);
  }

  void _checkFormState() {
    final bool hasValues = _startOdometerController.text.isNotEmpty &&
        _endOdometerController.text.isNotEmpty &&
        _earningsController.text.isNotEmpty &&
        _fuelController.text.isNotEmpty;

    if (hasValues != _isFormValid) {
      setState(() {
        _isFormValid = hasValues;
      });
    }
  }

  @override
  void dispose() {
    _startOdometerController.dispose();
    _endOdometerController.dispose();
    _earningsController.dispose();
    _fuelController.dispose();
    _otherExpensesController.dispose();
    super.dispose();
  }

  void _calculateOperations() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() ?? false) {
      final double startKm = double.parse(_startOdometerController.text.trim());
      final double endKm = double.parse(_endOdometerController.text.trim());
      final double earnings = double.parse(_earningsController.text.trim());
      final double fuel = double.parse(_fuelController.text.trim());
      final double other = double.tryParse(_otherExpensesController.text.trim()) ?? 0.0;

      if (endKm < startKm) {
        _showErrorSnackBar('End odometer reading cannot be less than start reading.');
        return;
      }

      final double totalDistance = endKm - startKm;

      // Navigate directly to Daily Summary Result Screen
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DailySummaryResultScreen(
            startOdometer: startKm,
            endOdometer: endKm,
            distanceTraveled: totalDistance,
            dailyEarnings: earnings,
            fuelExpense: fuel,
            otherExpenses: other,
          ),
        ),
      );

      if (!mounted) return;

      if (result != null) {
        Navigator.pop(context, result);
      }
    } else {
      _showErrorSnackBar('Please fill in all required fields.');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32.0,
                ),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Section
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
                                  'Daily Operations',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                                Text(
                                  'Record Daily Operations',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'Enter your daily details after\nyour shift.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Input Fields
                        _buildCustomField(
                          controller: _startOdometerController,
                          label: 'Start Odometer (km)',
                          icon: Icons.speed_rounded,
                          iconColor: const Color(0xFF0052CC),
                        ),
                        const SizedBox(height: 16),

                        _buildCustomField(
                          controller: _endOdometerController,
                          label: 'End Odometer (km)',
                          icon: Icons.speed_rounded,
                          iconColor: const Color(0xFF0052CC),
                        ),
                        const SizedBox(height: 16),

                        _buildCustomField(
                          controller: _earningsController,
                          label: 'Total Daily Earnings',
                          icon: Icons.payments_outlined,
                          iconColor: const Color(0xFF2E7D32),
                          isCurrency: true,
                        ),
                        const SizedBox(height: 16),

                        _buildCustomField(
                          controller: _fuelController,
                          label: 'Fuel Expense',
                          icon: Icons.local_gas_station_rounded,
                          iconColor: const Color(0xFFFF5252),
                          isCurrency: true,
                        ),
                        const SizedBox(height: 16),

                        _buildCustomField(
                          controller: _otherExpensesController,
                          label: 'Other Expenses (Optional)',
                          icon: Icons.account_balance_wallet_rounded,
                          iconColor: const Color(0xFFE5A800),
                          isCurrency: true,
                        ),
                        const SizedBox(height: 6),

                        const Padding(
                          padding: EdgeInsets.only(left: 12.0),
                          child: Text(
                            'e.g. food, maintenance, toll, etc.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black38,
                            ),
                          ),
                        ),

                        const Spacer(),
                        const SizedBox(height: 24),

                        // Calculate Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _calculateOperations,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFormValid ? const Color(0xFF0038FF) : const Color(0xFF9E9E9E),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Calculate',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCustomField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color iconColor,
    bool isCurrency = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: controller.text.isNotEmpty ? const Color(0xFF0038FF) : const Color(0xFFE0E0E0),
          width: controller.text.isNotEmpty ? 1.8 : 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (isCurrency && controller.text.isNotEmpty)
                      const Text(
                        '₱ ',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                        ),
                        onChanged: (_) {
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}