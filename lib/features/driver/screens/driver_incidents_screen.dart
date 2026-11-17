import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/fleet_api.dart';
import '../widgets/restriction_notice.dart';

/// Short-tripping reports raised against this driver, where they explain what
/// happened. Read-mostly by design: a driver can write or update their
/// explanation until a reviewer decides, but can't change a status, delete a
/// report, or touch anything else — those records are the operator's.
class DriverIncidentsScreen extends StatefulWidget {
  const DriverIncidentsScreen({super.key});

  @override
  State<DriverIncidentsScreen> createState() => _DriverIncidentsScreenState();
}

class _DriverIncidentsScreenState extends State<DriverIncidentsScreen> {
  List<ShortTripIncidentInfo>? _incidents;
  DriverStatusInfo? _status;
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([FleetApi.fetchIncidents(), FleetApi.fetchStatus()]);
      if (!mounted) return;
      setState(() {
        _incidents = results[0] as List<ShortTripIncidentInfo>;
        _status = results[1] as DriverStatusInfo;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _offline = isOfflineError(e);
      });
    }
  }

  Future<void> _explain(ShortTripIncidentInfo incident) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ExplanationSheet(incident: incident),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('Short-Tripping Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_error != null && _incidents == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(_offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 40, color: Colors.black38),
          const SizedBox(height: 10),
          Center(child: Text(_offline ? "You're offline" : "Couldn't load reports", style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 12))),
          Center(child: TextButton(onPressed: _load, child: const Text('Try again'))),
        ],
      );
    }
    final incidents = _incidents;
    if (incidents == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_status?.restriction != null) ...[
          RestrictionNotice(restriction: _status!.restriction!, onMayHaveExpired: _load),
          const SizedBox(height: 14),
        ],
        const Text(
          'When a passenger reports being made to get off before their destination, you are asked to explain. A report is only counted after a reviewer confirms it.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        if (incidents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.verified_outlined, size: 40, color: Colors.black26),
                SizedBox(height: 10),
                Text('No reports', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('Nothing has been reported against you.', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        for (final i in incidents) ...[
          _IncidentCard(incident: i, onExplain: () => _explain(i)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.onExplain});
  final ShortTripIncidentInfo incident;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (incident.status) {
      'PENDING_EXPLANATION' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      'CONFIRMED' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      'DISMISSED' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      _ => (const Color(0xFFFEF3C7), const Color(0xFF92600A)),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  incident.route ?? 'Reported trip',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Text(incident.statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(formatRestrictionTime(incident.occurredAt), style: const TextStyle(fontSize: 10.5, color: Colors.black45, fontWeight: FontWeight.w600)),
          if (incident.description != null && incident.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(incident.description!, style: const TextStyle(fontSize: 12, height: 1.35, color: Colors.black87)),
          ],
          if (incident.explanation != null) ...[
            const SizedBox(height: 10),
            const Text('Your explanation', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(incident.explanation!, style: const TextStyle(fontSize: 12, height: 1.35)),
          ],
          if (incident.reviewNote != null && incident.reviewNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Reviewer note', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(incident.reviewNote!, style: const TextStyle(fontSize: 12, height: 1.35)),
          ],
          if (incident.canExplain) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onExplain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(incident.explanation == null ? 'Explain what happened' : 'Update explanation', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExplanationSheet extends StatefulWidget {
  const _ExplanationSheet({required this.incident});
  final ShortTripIncidentInfo incident;

  @override
  State<_ExplanationSheet> createState() => _ExplanationSheetState();
}

class _ExplanationSheetState extends State<_ExplanationSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.incident.explanation ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.length < 5) {
      setState(() => _error = 'Please explain what happened (at least a few words).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FleetApi.submitExplanation(widget.incident.id, text);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your explanation was sent for review.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = isOfflineError(e) ? "No connection — your explanation was NOT sent. Try again." : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Explain what happened', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Write it in your own words — for example a breakdown, an emergency, or a passenger issue. Your operator reviews this before anything is decided.',
            style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 5,
            maxLength: 2000,
            enabled: !_saving,
            decoration: InputDecoration(
              hintText: 'What happened?',
              filled: true,
              fillColor: AppColors.inputFieldFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary))
                  : const Text('Send explanation', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
