import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../services/boarding_config.dart';
import '../services/boarding_flow.dart';

/// What the verification ended with — only ever produced from a server-side
/// CONFIRMED (see [BoardingFlow]); the app never decides that locally.
typedef BoardingResult = BoardingOutcome;

// Only one boarding attempt per phone at a time — a second tap on Board (or a
// proximity prompt firing mid-attempt) must not stack another dialog.
bool _boardingDialogOpen = false;

/// Pressing Board does not put you on the jeepney's passenger count. This
/// opens a request on the server, then streams fresh GPS readings until the
/// server confirms they match the driver's position (or gives up). Returns the
/// confirmed boarding, or null if the commuter cancelled or it couldn't be
/// verified — in which case they were told why, and nobody was counted.
///
/// Every step is time-boxed (see [BoardingConfig]) and the dialog always has a
/// working Cancel / Try Again, so it can never leave the screen blocked.
Future<BoardingResult?> showBoardingVerification(
  BuildContext context, {
  String? tripId,
  String? qrToken,
  required int riders,
}) async {
  if (_boardingDialogOpen) return null;
  _boardingDialogOpen = true;
  try {
    return await showDialog<BoardingResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => _BoardingVerificationDialog(tripId: tripId, qrToken: qrToken, riders: riders),
    );
  } finally {
    _boardingDialogOpen = false;
  }
}

class _BoardingVerificationDialog extends StatefulWidget {
  const _BoardingVerificationDialog({this.tripId, this.qrToken, required this.riders});

  final String? tripId;
  final String? qrToken;
  final int riders;

  @override
  State<_BoardingVerificationDialog> createState() => _BoardingVerificationDialogState();
}

class _BoardingVerificationDialogState extends State<_BoardingVerificationDialog> {
  late final BoardingFlow _flow;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _flow = BoardingFlow(tripId: widget.tripId, qrToken: widget.qrToken, riders: widget.riders)
      ..addListener(_onChanged);
    // Start after the first frame so the dialog is on screen immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _flow.start());
  }

  @override
  void dispose() {
    _flow.removeListener(_onChanged);
    _flow.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_flow.state == BoardingState.confirmed && !_popped) {
      _popped = true;
      // Show the confirmation briefly, then close. Guarded so it pops exactly
      // once, and only this dialog.
      Future<void>.delayed(_flow.config.confirmedDisplay, () {
        if (!mounted) return;
        Navigator.of(context).pop(_flow.outcome);
      });
    }
  }

  void _cancel() {
    if (_popped) return; // a second tap must not pop the screen underneath
    _popped = true;
    _flow.cancel(); // returns immediately; never waits on GPS or the network
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = _flow.state;
    final failed = state == BoardingState.failed;
    final confirmed = state == BoardingState.confirmed;
    final validating = state == BoardingState.validating;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (confirmed)
                const Icon(Icons.check_circle_rounded, size: 52, color: Color(0xFF15803D))
              else if (failed)
                const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.errorRed)
              else
                const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3.5)),
              const SizedBox(height: 16),
              Text(
                switch (state) {
                  BoardingState.idle || BoardingState.pending => 'Getting your location…',
                  BoardingState.validating => 'Confirming you’re on the jeepney…',
                  BoardingState.confirmed => 'You’re on board!',
                  BoardingState.failed => 'Boarding not confirmed',
                },
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                switch (state) {
                  BoardingState.idle || BoardingState.pending => BoardingMessages.checkingLocation,
                  BoardingState.validating =>
                    '${BoardingMessages.verifyingJeepney} Stay next to the jeepney — you are not counted until it is confirmed.',
                  BoardingState.confirmed => BoardingMessages.confirmed,
                  BoardingState.failed => _flow.message.isEmpty ? BoardingMessages.generic : _flow.message,
                },
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
              if (validating) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: _flow.requiredReadings == 0 ? null : (_flow.confirmedReadings / _flow.requiredReadings).clamp(0.0, 1.0),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (failed)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _cancel,
                        child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _flow.busy ? null : _flow.start,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                )
              else if (!confirmed)
                TextButton(
                  onPressed: _cancel,
                  child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
