import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/qr_constants.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/widgets/app_avatar.dart';
import 'qr_scanner_screen.dart';

// Same list the backend enforces (COMPLAINT_TYPES in commuter.ts) — sent as-is
// as complaintType, so it can't drift from what POST /complaints accepts.
const List<String> kDriverReportReasons = [
  'Reckless Driving',
  'Overcharging',
  'Rude Behavior',
  'Route Deviation',
  'Other',
];

const List<String> _kStarLabels = [
  '1 - Very Poor',
  '2 - Poor',
  '3 - Average',
  '4 - Good',
  '5 - Excellent',
];

/// Pulls the backend token out of a scanned driver QR, or null if the code
/// isn't a ManibelaApp driver code at all (wrong prefix / empty token).
String? driverTokenFromQr(String rawValue) {
  final value = rawValue.trim();
  if (!value.startsWith(kDriverQrPrefix)) return null;
  final token = value.substring(kDriverQrPrefix.length).trim();
  return token.isEmpty ? null : token;
}

class _ScannedDriver {
  const _ScannedDriver({
    required this.fullName,
    required this.plateNumber,
    required this.route,
    required this.photoUrl,
    required this.averageRating,
    required this.ratingCount,
    required this.ratableTripId,
    required this.alreadyRated,
  });

  final String fullName;
  final String plateNumber;
  final String? route;
  final String? photoUrl;
  final double? averageRating;
  final int ratingCount;

  /// A ride this commuter took with this driver that can still be rated, or
  /// null (never rode with them, or every ride is already rated).
  final String? ratableTripId;
  final bool alreadyRated;

  factory _ScannedDriver.fromResponse(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>;
    return _ScannedDriver(
      fullName: driver['fullName'] as String,
      plateNumber: driver['plateNumber'] as String,
      route: driver['route'] as String?,
      photoUrl: driver['photoUrl'] as String?,
      averageRating: (driver['averageRating'] as num?)?.toDouble(),
      ratingCount: (driver['ratingCount'] as num?)?.toInt() ?? 0,
      ratableTripId: json['ratableTripId'] as String?,
      alreadyRated: json['alreadyRated'] as bool? ?? false,
    );
  }
}

enum _Stage { scanning, identifying, found, invalid, notFound, networkError }

/// Commuter side menu -> "Scan Driver QR": scan a jeepney's driver QR,
/// confirm which driver it is (the backend validates the token — the QR alone
/// is never trusted), then rate or report them.
class ScanDriverQrScreen extends StatefulWidget {
  const ScanDriverQrScreen({super.key});

  @override
  State<ScanDriverQrScreen> createState() => _ScanDriverQrScreenState();
}

class _ScanDriverQrScreenState extends State<ScanDriverQrScreen> {
  _Stage _stage = _Stage.scanning;
  _ScannedDriver? _driver;
  String? _token;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() => _stage = _Stage.scanning);

    // QrScannerScreen returns after the FIRST readable code (it ignores
    // further frames), so one scan can only ever trigger one lookup.
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(title: 'Scan Driver QR'),
      ),
    );
    if (!mounted) return;

    if (raw == null) {
      // Cancelled / camera denied and backed out — nothing to show here.
      if (_driver == null) Navigator.of(context).pop();
      else setState(() => _stage = _Stage.found);
      return;
    }

    final token = driverTokenFromQr(raw);
    if (token == null) {
      setState(() => _stage = _Stage.invalid);
      return;
    }
    await _identify(token);
  }

  Future<void> _identify(String token) async {
    setState(() {
      _stage = _Stage.identifying;
      _token = token;
    });
    try {
      final response = await ApiClient.get(
        '/api/commuter/driver-by-qr/${Uri.encodeComponent(token)}',
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      setState(() {
        _driver = _ScannedDriver.fromResponse(response);
        _stage = _Stage.found;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = not a registered driver; anything else (401, 5xx, no
      // connection) is a problem on our side, not a bad QR.
      setState(() => _stage = e.statusCode == 404 ? _Stage.notFound : _Stage.networkError);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.networkError);
    }
  }

  // -------------------------------------------------------------------------
  // Rate / Report
  // -------------------------------------------------------------------------

  Future<void> _rate() async {
    final driver = _driver!;
    if (driver.ratableTripId == null) {
      await _info(
        driver.alreadyRated ? 'Already Rated' : 'Ride Needed',
        driver.alreadyRated
            ? "You've already rated your ride with ${driver.fullName}."
            : "You can rate a driver after you've ridden with them. Scan the QR when you board to record your ride first.",
      );
      return;
    }

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RateSheet(driver: driver),
    );
    if (submitted == true && mounted) {
      await _info('Rating Submitted', 'Thank you for rating your driver.');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _report() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ReportDriverForm(driver: _driver!)),
    );
    if (submitted == true && mounted) {
      await _info('Report Submitted', 'Your report has been submitted for review.');
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _info(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F8),
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          'Scan Driver QR',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_stage) {
            _Stage.scanning || _Stage.identifying => _buildIdentifying(),
            _Stage.found => _buildFound(_driver!),
            _Stage.invalid => _buildProblem(
              icon: Icons.qr_code_2_rounded,
              title: 'Invalid QR Code',
              message: "That's not a ManibelaApp driver QR code. Please scan the QR code shown by the driver.",
              onRetry: _scan,
              retryLabel: 'Scan Again',
            ),
            _Stage.notFound => _buildProblem(
              icon: Icons.person_off_rounded,
              title: 'Invalid QR Code',
              message: 'This QR code is not associated with a registered driver or jeepney.',
              onRetry: _scan,
              retryLabel: 'Scan Again',
            ),
            _Stage.networkError => _buildProblem(
              icon: Icons.wifi_off_rounded,
              title: 'Unable to identify the driver',
              message: 'Please check your internet connection and try again.',
              onRetry: () => _token != null ? _identify(_token!) : _scan(),
              retryLabel: 'Try Again',
            ),
          },
        ),
      ),
    );
  }

  Widget _buildIdentifying() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Identifying driver...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildProblem({
    required IconData icon,
    required String title,
    required String message,
    required VoidCallback onRetry,
    required String retryLabel,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.black38),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 22),
          _FilledButton(label: retryLabel, onTap: onRetry),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildFound(_ScannedDriver driver) {
    final rating = driver.ratingCount == 0 || driver.averageRating == null
        ? 'New'
        : '${driver.averageRating!.toStringAsFixed(1)} (${driver.ratingCount})';

    return ListView(
      children: [
        const Text('Driver Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              AppAvatar(
                size: 56,
                photoUrl: driver.photoUrl,
                fallback: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
                backgroundColor: AppColors.settingsIconColor,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Plate Number: ${driver.plateNumber}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    if (driver.route != null)
                      Text('Route: ${driver.route}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    Text('Rating: $rating', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _FilledButton(label: 'Rate Driver', onTap: _rate),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _report,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            side: const BorderSide(color: AppColors.errorRed),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('Report Driver', style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _FilledButton extends StatelessWidget {
  const _FilledButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

// ===========================================================================
// RATE SHEET
// ===========================================================================

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.driver});

  final _ScannedDriver driver;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _stars = 0;
  bool _submitting = false;
  String? _error;
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_stars == 0) {
      setState(() => _error = 'Please choose a rating from 1 to 5 stars.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final comment = _comment.text.trim();
      await ApiClient.post(
        '/api/commuter/trips/${widget.driver.ratableTripId}/rating',
        {'stars': _stars, if (comment.isNotEmpty) 'comment': comment},
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't reach the server. Please check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rate Your Experience', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '${widget.driver.fullName} · ${widget.driver.plateNumber}',
              style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return InkWell(
                  onTap: _submitting ? null : () => setState(() => _stars = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      i < _stars ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 36,
                      color: const Color(0xFFE0A100),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _stars == 0 ? 'Tap a star to rate' : _kStarLabels[_stars - 1],
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _comment,
              enabled: !_submitting,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Comment (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            _FilledButton(label: _submitting ? 'Submitting...' : 'Submit Rating', onTap: _submitting ? null : _submit),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// REPORT FORM
// ===========================================================================

class _ReportDriverForm extends StatefulWidget {
  const _ReportDriverForm({required this.driver});

  final _ScannedDriver driver;

  @override
  State<_ReportDriverForm> createState() => _ReportDriverFormState();
}

class _ReportDriverFormState extends State<_ReportDriverForm> {
  String? _reason;
  bool _submitting = false;
  String? _error;
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final details = _details.text.trim();
    if (_reason == null) {
      setState(() => _error = 'Please choose a reason for your report.');
      return;
    }
    if (details.isEmpty) {
      setState(() => _error = 'Please add a few details about what happened.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // The same complaints endpoint Trip History uses, so the report lands in
      // the admin's existing Complaints queue (PENDING) — no separate system.
      await ApiClient.uploadFiles(
        '/api/commuter/complaints',
        files: const {},
        fields: {
          'plateNumber': widget.driver.plateNumber,
          if (widget.driver.ratableTripId != null) 'tripId': widget.driver.ratableTripId!,
          'complaintType': _reason!,
          'description': details,
        },
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't reach the server. Please check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F8),
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('Report Driver', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              '${widget.driver.fullName} · ${widget.driver.plateNumber}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'An admin will review this before any action is taken.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black45),
            ),
            const SizedBox(height: 18),
            const Text('Reason for Report', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) {
                if (!_submitting) setState(() => _reason = value);
              },
              child: Column(
                children: [
                  for (final reason in kDriverReportReasons)
                    RadioListTile<String>(
                      value: reason,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(reason, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text('Additional Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              enabled: !_submitting,
              maxLines: 5,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: 'Tell us what happened',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 14),
            _FilledButton(label: _submitting ? 'Submitting...' : 'Submit Report', onTap: _submitting ? null : _submit),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
