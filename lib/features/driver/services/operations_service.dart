import 'package:flutter/foundation.dart';

class DailyOperationRecord {
  final DateTime date;
  final double startOdometer;
  final double endOdometer;
  final double dailyEarnings;
  final double fuelExpense;
  final double otherExpenses;

  DailyOperationRecord({
    required this.date,
    required this.startOdometer,
    required this.endOdometer,
    required this.dailyEarnings,
    required this.fuelExpense,
    required this.otherExpenses,
  });

  double get distanceTraveled => (endOdometer - startOdometer) > 0 ? (endOdometer - startOdometer) : 0.0;
  double get totalExpenses => fuelExpense + otherExpenses;
  double get netIncome => dailyEarnings - totalExpenses;
  double get revenuePerKm => distanceTraveled > 0 ? (dailyEarnings / distanceTraveled) : 0.0;
  double get fuelCostPerKm => distanceTraveled > 0 ? (fuelExpense / distanceTraveled) : 0.0;
}

class OperationsService extends ChangeNotifier {
  // Singleton pattern for simple dynamic state access across screens
  static final OperationsService _instance = OperationsService._internal();
  factory OperationsService() => _instance;
  OperationsService._internal();

  final List<DailyOperationRecord> _allRecords = [];

  List<DailyOperationRecord> get records => List.unmodifiable(_allRecords);

  /// Adds a new record or updates existing record for the same date
  void addRecord(DailyOperationRecord record) {
    // Check if record for same date already exists to overwrite
    final index = _allRecords.indexWhere(
      (r) => r.date.year == record.date.year &&
             r.date.month == record.date.month &&
             r.date.day == record.date.day,
    );

    if (index >= 0) {
      _allRecords[index] = record;
    } else {
      _allRecords.add(record);
    }
    notifyListeners();
  }

  /// Dynamic calculation: Total Net Income
  double get totalNetIncome => _allRecords.fold(0.0, (sum, item) => sum + item.netIncome);

  /// Dynamic calculation: Total Distance
  double get totalDistance => _allRecords.fold(0.0, (sum, item) => sum + item.distanceTraveled);

  /// Dynamic calculation: Average Daily Income (Error-handled against division-by-zero)
  double get averageDailyIncome {
    if (_allRecords.isEmpty) return 0.0;
    return totalNetIncome / _allRecords.length;
  }

  /// Dynamic calculation: Average Daily Distance (Error-handled against division-by-zero)
  double get averageDailyDistance {
    if (_allRecords.isEmpty) return 0.0;
    return totalDistance / _allRecords.length;
  }
}