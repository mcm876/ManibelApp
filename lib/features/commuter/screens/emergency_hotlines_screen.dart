import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';

class _Hotline {
  final String acronym;
  final String fullName;
  final String number;
  final String description;
  final String logoAsset;
  final IconData fallbackIcon;
  final Color brandColor;
  final double logoSize; // Added custom logo size parameter

  const _Hotline({
    required this.acronym,
    required this.fullName,
    required this.number,
    required this.description,
    required this.logoAsset,
    required this.fallbackIcon,
    required this.brandColor,
    this.logoSize = 50.0, // Default size for all standard logos
  });
}

class EmergencyHotlinesScreen extends StatelessWidget {
  const EmergencyHotlinesScreen({super.key});

  static const List<_Hotline> _hotlines = [
    _Hotline(
      acronym: 'PNP',
      fullName: 'Philippine National Police',
      number: '117',
      description: 'For crimes, disturbances, violations, and police assistance.',
      logoAsset: AppAssets.pnpLogo,
      fallbackIcon: Icons.local_police_rounded,
      brandColor: Color(0xFF1F4B99),
      logoSize: 58.0, // <--- Made PNP logo slightly bigger
    ),
    _Hotline(
      acronym: 'MMDA',
      fullName: 'Metropolitan Manila Development Authority',
      number: '136',
      description: 'For road emergencies, traffic concerns, and road obstructions.',
      logoAsset: AppAssets.mmdaLogo,
      fallbackIcon: Icons.traffic_rounded,
      brandColor: Color(0xFF1F4B99),
    ),
    _Hotline(
      acronym: 'BFP',
      fullName: 'Bureau of Fire Protection',
      number: '(02) 8426-0219',
      description: 'For fire emergencies, rescue operations, and hazard incidents.',
      logoAsset: AppAssets.bfpLogo,
      fallbackIcon: Icons.local_fire_department_rounded,
      brandColor: Color(0xFFC02222),
    ),
    _Hotline(
      acronym: 'LTFRB',
      fullName: 'Land Transportation Franchising & Regulatory Board',
      number: '1342',
      description: 'For complaints, violations, and public transport concerns.',
      logoAsset: AppAssets.ltfrbLogo,
      fallbackIcon: Icons.directions_bus_rounded,
      brandColor: Color(0xFF1F4B99),
    ),
    _Hotline(
      acronym: 'LTO',
      fullName: 'Land Transportation Office',
      number: '09292920865',
      description: "For driver's license, vehicle registration, and concerns.",
      logoAsset: AppAssets.ltoLogo,
      fallbackIcon: Icons.badge_rounded,
      brandColor: Color(0xFF1F4B99),
    ),
  ];

  Future<void> _makePhoneCall(BuildContext context, String rawNumber) async {
    final String cleanNumber = rawNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final Uri launchUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        _showErrorSnackBar(context, 'Unable to open dialer for $rawNumber');
      }
    } catch (_) {
      if (!context.mounted) return;
      _showErrorSnackBar(context, 'Could not initiate call to $rawNumber');
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE23F3F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmAndCall(BuildContext context, String title, String number) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Call $title?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        content: Text(
          'You are about to dial $number. Only use this for genuine emergencies.',
          style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD62828),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Call Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _makePhoneCall(context, number);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.maybePop(context),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Emergency Hotlines',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "We're here to help. Stay safe.",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Hotlines List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  // 911 Featured Card
                  _EmergencyCard911(
                    onTap: () => _confirmAndCall(context, '911 Emergency Hotline', '911'),
                  ),
                  const SizedBox(height: 14),

                  // Agency Cards
                  ..._hotlines.map(
                    (hotline) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _HotlineCard(
                        hotline: hotline,
                        onTap: () => _confirmAndCall(context, hotline.acronym, hotline.number),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyCard911 extends StatelessWidget {
  final VoidCallback onTap;

  const _EmergencyCard911({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFDE8E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1C1C1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                // Shield Phone Icon
                Stack(
                  alignment: Alignment.center,
                  children: const [
                    Icon(Icons.shield_rounded, color: Color(0xFFD62828), size: 54),
                    Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 22),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'In Case of Emergency',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFD62828),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tap any hotline below to call for immediate assistance',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black45,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 911 Red Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD62828),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: const [
                      Text(
                        '911',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Emergency\nNumber',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                // Dynamic Agency Logo Container
                SizedBox(
                  width: hotline.logoSize,
                  height: hotline.logoSize,
                  child: Image.asset(
                    hotline.logoAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('❌ FAILED TO LOAD ASSET: "${hotline.logoAsset}"');
                      debugPrint('   Reason: $error');

                      return Icon(
                        hotline.fallbackIcon,
                        color: hotline.brandColor,
                        size: 36,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${hotline.acronym}\n',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: hotline.brandColor,
                                height: 1.1,
                              ),
                            ),
                            TextSpan(
                              text: hotline.fullName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hotline.description,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.black45,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Call Action Button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF63A375),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.phone, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'CALL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hotline.number,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2B7A4B),
                      ),
                    ),
                    const Text(
                      'Hotline',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}