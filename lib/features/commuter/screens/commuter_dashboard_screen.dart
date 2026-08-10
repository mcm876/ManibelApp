import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import 'find_nearby_jeepneys_screen.dart';
import 'rate_or_report_driver_screen.dart';
import 'emergency_hotlines_screen.dart';
import 'commuter_menu_drawer.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import '../../../core/services/user_session.dart';
import '../../auth/screens/commuter_login_screen.dart';

class CommuterDashboardScreen extends StatefulWidget {
  const CommuterDashboardScreen({super.key});

  @override
  State<CommuterDashboardScreen> createState() =>
      _CommuterDashboardScreenState();
}

class _CommuterDashboardScreenState extends State<CommuterDashboardScreen> {
  String _commuterName = UserSession.instance.fullName ?? 'Juan Dela Cruz';
  String _mobileNumber = UserSession.instance.mobileNumber ?? '';
  DateTime? _dateOfBirth = UserSession.instance.dateOfBirth;
  String? _photoPath = UserSession.instance.photoPath;

  Future<void> _handleLogout(BuildContext context) async {
    await UserSession.instance.signOut();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CommuterLoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final result = await Navigator.push<SettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialFullName: _commuterName,
          initialMobileNumber: _mobileNumber,
          initialDateOfBirth: _dateOfBirth,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      if (result.fullName.isNotEmpty) _commuterName = result.fullName;
      _mobileNumber = result.mobileNumber;
      _dateOfBirth = result.dateOfBirth;
      _photoPath = result.photoPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      drawer: CommuterMenuDrawer(
        commuterName: _commuterName,
        photoPath: _photoPath,
        onSettingsTap: () => _openSettings(context),
        onLogoutTap: () => _handleLogout(context),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _TopBar(photoPath: _photoPath),
            const SizedBox(height: 16),
            _WelcomeCard(
              name: _commuterName,
              role: 'Commuter',
              photoPath: _photoPath,
            ),
            const SizedBox(height: 16),
            const _NearbyJeepneysCard(),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Commuter Dashboard'),
            const SizedBox(height: 12),
            _DashboardListItem(
              icon: Icons.map_outlined,
              iconBackground: const Color(0xFFDCEFE6),
              iconColor: const Color(0xFF2E9E6D),
              title: 'Find Nearby Jeepneys',
              subtitle: 'View available jeepneys near your\ncurrent location.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FindNearbyJeepneysScreen(
                    commuterName: _commuterName,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _DashboardListItem(
              icon: Icons.warning_amber_rounded,
              iconBackground: const Color(0xFFFCEFD2),
              iconColor: const Color(0xFFE5A800),
              title: 'Rate or Report Driver',
              subtitle: 'Allows passengers to rate drivers and\nreport issues for better service and safety.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RateOrReportDriverScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _DashboardListItem(
              icon: Icons.phone_in_talk_rounded,
              iconBackground: const Color(0xFFFBDADA),
              iconColor: const Color(0xFFE23F3F),
              title: 'Emergency Hotlines',
              subtitle: 'Allow passengers to quickly contact\nemergency services when needed.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmergencyHotlinesScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({this.photoPath});

  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu, color: Colors.black87),
        ),

        // CENTER LOGO & APP NAME BRANDING
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              AppAssets.jeepneyLogo,
              width: 44, // Increased from 32 for better visibility
              height: 44, // Increased from 32 for better visibility
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.directions_bus_rounded,
                  size: 38, // Increased fallback icon size to match
                  color: AppColors.logoBlue,
                );
              },
            ),

            const SizedBox(width: 8),

            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
                children: [
                  TextSpan(
                    text: 'Manibel',
                    style: TextStyle(
                      color: AppColors.logoBlue,
                    ),
                  ),
                  TextSpan(
                    text: 'App',
                    style: TextStyle(
                      color: AppColors.logoRed,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        IconButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          },
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final String name;
  final String role;
  final String? photoPath;

  const _WelcomeCard({required this.name, required this.role, this.photoPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFE4E4E4),
            backgroundImage:
                photoPath != null ? FileImage(File(photoPath!)) : null,
            child: photoPath == null
                ? const Icon(Icons.person, color: Colors.white70, size: 26)
                : null,
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome,',
                style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
              ),
              const SizedBox(height: 2),
              Text(
                role,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.logoBlue),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NearbyJeepneysCard extends StatelessWidget {
  const _NearbyJeepneysCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nearby Jeepneys',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              _LiveBadge(),
            ],
          ),

          SizedBox(height: 4),

          Text(
            'Track active drivers and route in real time',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
          ),

          SizedBox(height: 8),

          _TrafficLegend(),

          SizedBox(height: 8),

          SizedBox(
            height: 140,
            child: _MapPreview(),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: Color(0xFF2E9E6D), shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        const Text(
          'Live',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2E9E6D)),
        ),
      ],
    );
  }
}

class _TrafficLegend extends StatelessWidget {
  const _TrafficLegend();

  Widget _legendRow(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE7E7E7),
        ),
      ),
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(const Color(0xFF2E9E6D), 'SMOOTH'),
          _legendRow(const Color(0xFFE5A800), 'MODERATE'),
          _legendRow(const Color(0xFFE23F3F), 'HEAVY TRAFFIC'),
        ],
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.of(context).size.height * 0.18;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: mapHeight.clamp(120.0, 160.0),
        width: double.infinity,
        child: Stack(
          children: [
            Container(
              color: const Color(0xFFE9ECEE),
            ),

            Positioned.fill(
              child: CustomPaint(
                painter: _MapRoadsPainter(),
              ),
            ),

            const Positioned(
              left: 60,
              top: 70,
              child: _JeepneyPin(
                color: Color(0xFF2E9E6D),
              ),
            ),

            const Positioned(
              left: 130,
              top: 40,
              child: _JeepneyPin(
                color: Color(0xFFE5A800),
              ),
            ),

            const Positioned(
              left: 170,
              top: 110,
              child: _JeepneyPin(
                color: Color(0xFF2E9E6D),
              ),
            ),

            const Positioned(
              left: 90,
              top: 140,
              child: _JeepneyPin(
                color: Color(0xFFE23F3F),
              ),
            ),

            Positioned(
              right: 10,
              bottom: 44,
              child: _MapButton(
                icon: Icons.my_location_rounded,
                onTap: () {},
              ),
            ),

            Positioned(
              right: 10,
              bottom: 8,
              child: _MapButton(
                icon: Icons.layers_outlined,
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapRoadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.25), paint);
    canvas.drawLine(Offset(0, size.height * 0.65), Offset(size.width, size.height * 0.7), paint);
    canvas.drawLine(Offset(size.width * 0.3, 0), Offset(size.width * 0.35, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.65, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _JeepneyPin extends StatelessWidget {
  final Color color;
  const _JeepneyPin({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
    );
  }
}

class _DashboardListItem extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _DashboardListItem({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

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
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500, height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.logoBlue),
            ],
          ),
        ),
      ),
    );
  }
}