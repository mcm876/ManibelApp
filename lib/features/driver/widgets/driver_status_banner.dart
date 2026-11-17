import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/fleet_api.dart';
import 'restriction_notice.dart';

/// Dashboard heads-up for the two things a driver must not miss: a trip-start
/// restriction, and short-tripping reports still waiting for their explanation.
/// Renders nothing when there's neither.
class DriverStatusBanner extends StatelessWidget {
  const DriverStatusBanner({super.key, required this.status, required this.onOpenIncidents, this.onMayHaveExpired});

  final DriverStatusInfo? status;
  final VoidCallback onOpenIncidents;
  final VoidCallback? onMayHaveExpired;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const SizedBox.shrink();
    final children = <Widget>[];

    if (s.restriction != null) {
      children.add(RestrictionNotice(restriction: s.restriction!, onMayHaveExpired: onMayHaveExpired));
    } else if (s.suspended) {
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF5B5B5)),
          ),
          child: const Text(
            'Your account is suspended from driving. Please contact your operator.',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7A1F1F)),
          ),
        ),
      );
    }

    if (s.pendingExplanations > 0) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 8));
      children.add(
        Material(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onOpenIncidents,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, size: 20, color: AppColors.onPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.pendingExplanations == 1
                          ? 'A passenger report needs your explanation. Tap to respond.'
                          : '${s.pendingExplanations} passenger reports need your explanation. Tap to respond.',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.onPrimary),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(children: children));
  }
}
