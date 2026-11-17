import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/live_location.dart';

/// What the verification ended with. [confirmed] is true only when the server
/// itself said CONFIRMED — the app never decides that locally.
class BoardingResult {
  const BoardingResult({required this.tripId, required this.boardingId});
  final String? tripId;
  final String? boardingId;
}

/// Pressing Board does not put you on the jeepney's passenger count. This
/// opens a request on the server, then streams fresh GPS readings until the
/// server confirms they match the driver's position (or gives up). Returns the
/// confirmed boarding, or null if the commuter cancelled or it couldn't be
/// verified — in which case they were told why, and nobody was counted.
Future<BoardingResult?> showBoardingVerification(
  BuildContext context, {
  String? tripId,
  String? qrToken,
  required int riders,
}) {
  return showDialog<BoardingResult>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (_) => _BoardingVerificationDialog(tripId: tripId, qrToken: qrToken, riders: riders),
  );
}

enum _Phase { locating, verifying, confirmed, failed }

class _BoardingVerificationDialog extends StatefulWidget {
  const _BoardingVerificationDialog({this.tripId, this.qrToken, required this.riders});

  final String? tripId;
  final String? qrToken;
  final int riders;

  @override
  State<_BoardingVerificationDialog> createState() => _BoardingVerificationDialogState();
}

class _BoardingVerificationDialogState extends State<_BoardingVerificationDialog> {
  _Phase _phase = _Phase.locating;
  String? _message;
  int _confirmedReadings = 0;
  int _requiredReadings = 3;

  StreamSubscription<Position>? _positionSub;
  Position? _latest;
  DateTime? _latestReceivedAt;

  String? _requestId;
  bool _closing = false;
  int _attempt = 0;

  String? get _token => UserSession.instance.authToken;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _closing = true;
    _positionSub?.cancel();
    super.dispose();
  }

  String _newRequestKey() => 'b-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  void _fail(String message) {
    if (!mounted || _closing) return;
    _positionSub?.cancel();
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  /// The newest fix and how old it is — measured from when THIS app received
  /// it, not from the fix's own timestamp, which is wrong on any phone with an
  /// incorrect clock (see _dropOutOfOrder in live_location.dart).
  Map<String, dynamic>? _readingPayload() {
    final p = _latest;
    final at = _latestReceivedAt;
    if (p == null || at == null) return null;
    return {
      'lat': p.latitude,
      'lng': p.longitude,
      'accuracy': p.accuracy,
      'fixAgeSeconds': DateTime.now().difference(at).inMilliseconds / 1000.0,
    };
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    setState(() {
      _phase = _Phase.locating;
      _message = null;
      _confirmedReadings = 0;
      _requestId = null;
    });

    final access = await ensureLocationAccess();
    if (!mounted || attempt != _attempt) return;
    if (access != LocationAccess.granted) {
      _fail(locationAccessMessage(access));
      return;
    }

    await _positionSub?.cancel();
    _latest = null;
    _latestReceivedAt = null;
    _positionSub = livePositionStream(distanceFilterMeters: 0).listen(
      (p) {
        _latest = p;
        _latestReceivedAt = DateTime.now();
      },
      onError: (_) {},
    );

    // Wait for the first real fix.
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (_latest == null && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted || attempt != _attempt) return;
    }
    if (_latest == null) {
      _fail("We couldn't get your GPS location. Move to an open area, check that location is on, and try again.");
      return;
    }

    setState(() => _phase = _Phase.verifying);

    final key = _newRequestKey();
    var networkErrors = 0;
    Map<String, dynamic> response;
    try {
      response = await ApiClient.post(
        '/api/commuter/board',
        {
          if (widget.tripId != null) 'tripId': widget.tripId,
          if (widget.qrToken != null) 'qrToken': widget.qrToken,
          'riders': widget.riders,
          'clientRequestId': key,
          ...?_readingPayload(),
        },
        token: _token,
      );
    } on ApiException catch (e) {
      _fail(e.message);
      return;
    }

    while (mounted && attempt == _attempt && !_closing) {
      final status = response['status'] as String?;
      _requestId = response['requestId'] as String? ?? _requestId;
      _requiredReadings = (response['requiredReadings'] as num?)?.toInt() ?? _requiredReadings;

      if (status == 'CONFIRMED') {
        await _positionSub?.cancel();
        if (!mounted) return;
        setState(() => _phase = _Phase.confirmed);
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        _closing = true;
        Navigator.of(context).pop(
          BoardingResult(
            tripId: response['tripId'] as String?,
            boardingId: response['boardingId'] as String?,
          ),
        );
        return;
      }
      if (status == 'FAILED' || status == 'CANCELLED') {
        _fail(response['message'] as String? ?? "Boarding couldn't be confirmed.");
        return;
      }

      setState(() => _confirmedReadings = (response['confirmedReadings'] as num?)?.toInt() ?? 0);

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || attempt != _attempt || _closing) return;

      final payload = _readingPayload();
      final id = _requestId;
      if (id == null) {
        _fail("Boarding couldn't be confirmed. Please try again.");
        return;
      }
      try {
        response = await ApiClient.post(
          '/api/commuter/board/requests/$id/readings',
          payload ?? {'lat': 0, 'lng': 0, 'accuracy': 9999, 'fixAgeSeconds': 9999},
          token: _token,
        );
        networkErrors = 0;
      } on ApiException catch (e) {
        if (e.statusCode == null && ++networkErrors < 4) continue; // brief connection blip — keep trying
        _fail(e.statusCode == null ? 'Connection lost, so boarding was not confirmed. Please try again.' : e.message);
        return;
      }
    }
  }

  Future<void> _cancel() async {
    _closing = true;
    _attempt++;
    await _positionSub?.cancel();
    final id = _requestId;
    if (id != null && _phase != _Phase.failed) {
      // Best effort — an unconfirmed request counts for nothing either way,
      // and the server expires it on its own.
      try {
        await ApiClient.post('/api/commuter/board/requests/$id/cancel', {}, token: _token);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _phase == _Phase.failed;
    final confirmed = _phase == _Phase.confirmed;

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
                switch (_phase) {
                  _Phase.locating => 'Getting your location…',
                  _Phase.verifying => 'Confirming you’re on the jeepney…',
                  _Phase.confirmed => 'You’re on board!',
                  _Phase.failed => 'Boarding not confirmed',
                },
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                switch (_phase) {
                  _Phase.locating => 'Hold on while we find your GPS position.',
                  _Phase.verifying => 'Stay next to the jeepney. This usually takes a few seconds, and you are not counted until it is confirmed.',
                  _Phase.confirmed => 'Your boarding has been confirmed.',
                  _Phase.failed => _message ?? "Boarding couldn't be confirmed.",
                },
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
              if (_phase == _Phase.verifying) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: _requiredReadings == 0 ? null : (_confirmedReadings / _requiredReadings).clamp(0.0, 1.0),
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
                        onPressed: _start,
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
