import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/fleet_api.dart';

/// "Which jeepney are you currently driving?" — lists only the plates the
/// backend says are assigned to this driver, with each one's registered
/// seating capacity. Returns the chosen [DriverVehicle], or null if dismissed.
Future<DriverVehicle?> showVehiclePickerSheet(BuildContext context, {String? selectedId}) {
  return showModalBottomSheet<DriverVehicle>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _VehiclePickerSheet(selectedId: selectedId),
  );
}

class _VehiclePickerSheet extends StatefulWidget {
  const _VehiclePickerSheet({this.selectedId});
  final String? selectedId;

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  List<DriverVehicle>? _vehicles;
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _vehicles = null;
      _error = null;
    });
    try {
      final list = await FleetApi.fetchVehicles();
      if (!mounted) return;
      setState(() => _vehicles = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _offline = isOfflineError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Which jeepney are you currently driving?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Only jeepneys assigned to you are shown.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 14),
              Flexible(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Message(
        icon: _offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
        title: _offline ? "You're offline" : "Couldn't load your jeepneys",
        text: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800))),
      );
    }
    final vehicles = _vehicles;
    if (vehicles == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (vehicles.isEmpty) {
      return const _Message(
        icon: Icons.directions_bus_outlined,
        title: 'No jeepney assigned to you',
        text: 'Ask your operator to assign a jeepney to your account, then try again.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final v = vehicles[i];
        final selected = v.id == widget.selectedId;
        final blockedReason = v.seatingCapacity == null
            ? 'Seating capacity not set — ask your operator'
            : (v.inUse && !v.inUseByMe)
                ? 'Already on an active trip'
                : null;
        return Material(
          color: selected ? AppColors.qrTileBg : const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: blockedReason != null ? null : () => Navigator.pop(context, v),
            child: Opacity(
              opacity: blockedReason != null ? 0.55 : 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? AppColors.qrTileBorder : const Color(0xFFE6E6E7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus_filled_rounded, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.plateNumber, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            blockedReason ?? 'Seating capacity: ${v.seatingCapacity} passengers',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: blockedReason != null ? AppColors.errorRed : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.onPrimary, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Colors.black38),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.35)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
