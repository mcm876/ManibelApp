import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/fleet_api.dart';

String formatRestrictionTime(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  final suffix = t.hour >= 12 ? 'PM' : 'AM';
  return '${months[t.month - 1]} ${t.day}, $hour12:$minute $suffix';
}

String _remainingLabel(Duration d) {
  if (d.inSeconds <= 0) return 'ending now';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m}m left';
  if (d.inMinutes > 0) return '${d.inMinutes}m left';
  return 'less than a minute left';
}

/// Tells a driver they can't start a trip right now, why, and until when.
/// The server is the one that actually enforces it — this only explains it,
/// and asks the caller to re-check ([onMayHaveExpired]) when the shown end
/// time passes, since that's the server's call, not this phone's clock's.
class RestrictionNotice extends StatefulWidget {
  const RestrictionNotice({super.key, required this.restriction, this.onMayHaveExpired});

  final TripRestriction restriction;
  final VoidCallback? onMayHaveExpired;

  @override
  State<RestrictionNotice> createState() => _RestrictionNoticeState();
}

class _RestrictionNoticeState extends State<RestrictionNotice> {
  Timer? _timer;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_notified && DateTime.now().isAfter(widget.restriction.expiresAt)) {
        _notified = true;
        widget.onMayHaveExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restriction;
    final left = r.expiresAt.difference(DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5B5B5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.block_rounded, size: 18, color: AppColors.errorRed),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trip start temporarily restricted',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF7A1F1F)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.reason,
            style: const TextStyle(fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w500, color: Color(0xFF7A1F1F)),
          ),
          const SizedBox(height: 10),
          Text(
            'Started: ${formatRestrictionTime(r.startsAt)}\nEnds: ${formatRestrictionTime(r.expiresAt)}  (${_remainingLabel(left)})',
            style: const TextStyle(fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w700, color: Color(0xFF7A1F1F)),
          ),
          const SizedBox(height: 8),
          const Text(
            'This stays in place if you log out or use another phone. You can start trips again automatically once it ends. Questions? Contact your operator.',
            style: TextStyle(fontSize: 10.5, height: 1.35, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
