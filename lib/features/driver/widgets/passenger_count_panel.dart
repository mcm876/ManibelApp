import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/fleet_api.dart';

/// Live passenger count for the active trip: app-verified + manually counted
/// passengers, seating capacity, seats left, and the NEARLY FULL / FULL
/// warning. The count always comes from the server (polled, and refreshed
/// after every tap) — nothing here is computed locally, so it can't disagree
/// with what commuters' boardings are checked against. +1/-1 only change the
/// display once the server has accepted them.
class PassengerCountPanel extends StatefulWidget {
  const PassengerCountPanel({super.key, required this.tripId});

  final String tripId;

  @override
  State<PassengerCountPanel> createState() => _PassengerCountPanelState();
}

class _PassengerCountPanelState extends State<PassengerCountPanel> {
  TripOccupancy? _occupancy;
  bool _loading = true;
  bool _stale = false; // last refresh failed — showing the last known count
  bool _busy = false;
  bool _canUndo = false;
  Timer? _pollTimer;
  Timer? _undoTimer;
  int _requestSeq = 0;
  OccupancyLevel? _lastLevel;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _undoTimer?.cancel();
    super.dispose();
  }

  void _apply(TripOccupancy occ) {
    // A buzz the moment the jeepney crosses into NEARLY FULL / FULL — the
    // driver is usually looking at the road, not this card.
    if (_lastLevel != null && occ.level != _lastLevel && (occ.level == OccupancyLevel.nearlyFull || occ.level == OccupancyLevel.full)) {
      HapticFeedback.heavyImpact();
    }
    _lastLevel = occ.level;
    _occupancy = occ;
    _stale = false;
    _loading = false;
  }

  Future<void> _refresh() async {
    if (_busy) return;
    try {
      final occ = await FleetApi.fetchOccupancy(widget.tripId);
      if (!mounted) return;
      setState(() {
        if (occ != null) _apply(occ);
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _stale = true;
        _loading = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _adjust(int delta) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final occ = await FleetApi.adjustManual(
        widget.tripId,
        delta,
        requestId: '${DateTime.now().microsecondsSinceEpoch}-${_requestSeq++}',
      );
      if (!mounted) return;
      setState(() {
        _apply(occ);
        _canUndo = true;
      });
      _undoTimer?.cancel();
      _undoTimer = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _canUndo = false);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(isOfflineError(e) ? "No connection — the passenger count was NOT changed." : e.message);
      _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final occ = await FleetApi.undoManual(widget.tripId);
      if (!mounted) return;
      setState(() {
        _apply(occ);
        _canUndo = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(isOfflineError(e) ? "No connection — nothing was undone." : e.message);
      setState(() => _canUndo = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final occ = _occupancy;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: occ == null ? _placeholder() : _content(occ),
    );
  }

  Widget _placeholder() {
    return SizedBox(
      height: 56,
      child: Center(
        child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.black45),
                  const SizedBox(width: 8),
                  const Text("Can't load passenger count", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
      ),
    );
  }

  Widget _content(TripOccupancy occ) {
    final cap = occ.seatingCapacity;
    final (Color chipBg, Color chipFg, String chipText) = switch (occ.level) {
      OccupancyLevel.full => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C), 'FULL'),
      OccupancyLevel.nearlyFull => (const Color(0xFFFEF3C7), const Color(0xFF92600A), 'NEARLY FULL'),
      OccupancyLevel.normal => (const Color(0xFFDCFCE7), const Color(0xFF15803D), 'NORMAL'),
      OccupancyLevel.unknown => (const Color(0xFFE5E7EB), Colors.black54, 'NO CAPACITY SET'),
    };
    final isFull = occ.level == OccupancyLevel.full;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_rounded, size: 22, color: AppColors.logoBlue),
            const SizedBox(width: 8),
            const Text('Passengers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
              child: Text(chipText, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: chipFg)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Stat(label: 'App', value: '${occ.appPassengers}'),
            _Stat(label: 'Manual', value: '${occ.manualPassengers}'),
            _Stat(label: 'Total', value: '${occ.totalPassengers}', emphasize: true),
            _Stat(label: 'Capacity', value: cap == null ? '—' : '$cap'),
            _Stat(label: 'Seats left', value: occ.remainingSeats == null ? '—' : '${occ.remainingSeats}'),
          ],
        ),
        if (occ.level == OccupancyLevel.nearlyFull || isFull) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(10)),
            child: Text(
              isFull
                  ? 'Jeepney is FULL. No more passengers can be added, and app boardings are blocked.'
                  : 'Nearly full — only ${occ.remainingSeats ?? 0} seat${occ.remainingSeats == 1 ? '' : 's'} left.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: chipFg),
            ),
          ),
        ],
        if (_stale) ...[
          const SizedBox(height: 6),
          const Text(
            'Offline — showing the last known count. It may be out of date.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.errorRed),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_busy || occ.manualPassengers <= 0) ? null : () => _adjust(-1),
                icon: const Icon(Icons.remove_rounded, size: 24),
                label: const Text('-1 Remove', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: (_busy || isFull) ? null : () => _adjust(1),
                icon: const Icon(Icons.add_rounded, size: 26),
                label: const Text('+1 Add Passenger', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
        if (_canUndo)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _undo,
              icon: const Icon(Icons.undo_rounded, size: 20),
              label: const Text('Undo last change', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 30 : 22,
              fontWeight: FontWeight.w900,
              color: emphasize ? AppColors.logoBlue : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
        ],
      ),
    );
  }
}
