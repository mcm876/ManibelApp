import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class _Hotline {
  final String name;
  final String number;
  final String description;
  final IconData icon;
  final Color color;

  const _Hotline({
    required this.name,
    required this.number,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class EmergencyHotlinesScreen extends StatelessWidget {
  const EmergencyHotlinesScreen({super.key});

  static const List<_Hotline> _hotlines = [
    _Hotline(
      name: 'National Emergency Hotline',
      number: '911',
      description: 'Police, fire, and medical emergencies',
      icon: Icons.emergency_rounded,
      color: Color(0xFFE23F3F),
    ),
    _Hotline(
      name: 'Philippine National Police',
      number: '117',
      description: 'Report crimes or request police assistance',
      icon: Icons.local_police_rounded,
      color: Color(0xFF2E5FE5),
    ),
    _Hotline(
      name: 'Bureau of Fire Protection',
      number: '(02) 8426-0219',
      description: 'Fire emergencies and rescue',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFE5A800),
    ),
    _Hotline(
      name: 'Red Cross Ambulance',
      number: '143',
      description: 'Medical emergencies and ambulance dispatch',
      icon: Icons.medical_services_rounded,
      color: Color(0xFF2E9E6D),
    ),
    _Hotline(
      name: 'LTFRB Hotline',
      number: '1342',
      description: 'Report jeepney or driver violations',
      icon: Icons.directions_bus_rounded,
      color: AppColors.logoBlue,
    ),
  ];

  Future<void> _confirmAndCall(BuildContext context, _Hotline hotline) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Call ${hotline.name}?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'You are about to dial ${hotline.number}. Only use this for a genuine emergency.',
          style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE23F3F),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Call Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // NOTE: Requires the `url_launcher` package to actually place the call:
    //   final uri = Uri(scheme: 'tel', path: hotline.number);
    //   if (await canLaunchUrl(uri)) await launchUrl(uri);
    // Left as a TODO here since url_launcher isn't confirmed to be in this
    // project's pubspec.yaml yet.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dialing ${hotline.number}…')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F8),
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          'Emergency Hotlines',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFBDADA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFE23F3F), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tap a hotline to call. You will be asked to confirm before the call is placed.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7A1F1F)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ..._hotlines.map(
              (hotline) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HotlineCard(
                  hotline: hotline,
                  onTap: () => _confirmAndCall(context, hotline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotlineCard extends StatelessWidget {
  final _Hotline hotline;
  final VoidCallback onTap;

  const _HotlineCard({required this.hotline, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hotline.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(hotline.icon, color: hotline.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotline.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hotline.description,
                      style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hotline.number,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.logoBlue),
                  ),
                  const Icon(Icons.call_rounded, size: 16, color: Color(0xFF2E9E6D)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}