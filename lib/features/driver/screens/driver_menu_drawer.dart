import 'package:flutter/material.dart';
import '../../auth/screens/driver_login_screen.dart';
import 'settings_screen.dart';
import 'jeepney_qr_screen.dart';
import '../../auth/screens/driver_login_screen.dart';

class DriverMenuDrawer extends StatelessWidget {
  final String driverName;
  final String driverId;
  final String? driverMobile;
  final String plateNumber;
  final String routeName;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onQrCodeTap;
  final VoidCallback? onLogoutTap;

  const DriverMenuDrawer({
    super.key,
    required this.driverName,
    required this.driverId,
    this.driverMobile,
    this.plateNumber = 'ABC 1234',
    this.routeName = 'Pasig - Quiapo',
    this.onSettingsTap,
    this.onQrCodeTap,
    this.onLogoutTap,
  });

  /// Confirmation dialog before logging out
  Future<void> _handleLogout(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Logout',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Are you sure you want to log out of your account?',
          style: TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500),
        ),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCC0000),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      if (onLogoutTap != null) {
        onLogoutTap!();
        return;
      }

      // Clears all screens from memory and redirects to DriverLoginScreen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => DriverLoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.78,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dynamic Driver Profile Header
              Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFD9D9D9),
                    child: Icon(Icons.person_rounded, size: 36, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Driver ID:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0066FF),
                          ),
                        ),
                        Text(
                          driverId,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0066FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Button 1: Settings
              _buildMenuButton(
                context: context,
                icon: Icons.settings_outlined,
                label: 'Settings',
                backgroundColor: const Color(0xFFD6E3F8),
                borderColor: const Color(0xFF8BAEE8),
                iconColor: const Color(0xFF0044CC),
                textColor: Colors.black,
                onTap: () {
                  Navigator.pop(context); // Close drawer
                  if (onSettingsTap != null) {
                    onSettingsTap!();
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsScreen(
                          currentFullName: driverName,
                          currentMobile: driverMobile ?? '+63 917 123 4567',
                          currentPlateNumber: plateNumber,
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),

              // Button 2: Your QR Code
              _buildMenuButton(
                context: context,
                icon: Icons.qr_code_2_rounded,
                label: 'Your QR Code',
                backgroundColor: const Color(0xFFC7EBD1),
                borderColor: const Color(0xFF8DCFA1),
                iconColor: const Color(0xFF1E7538),
                textColor: const Color(0xFF1E7538),
                onTap: () {
                  Navigator.pop(context); // Close drawer
                  if (onQrCodeTap != null) {
                    onQrCodeTap!();
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JeepneyQrScreen(
                          plateNumber: plateNumber,
                          routeName: routeName,
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),

              // Button 3: Logout
              _buildMenuButton(
                context: context,
                icon: Icons.logout_rounded,
                label: 'Logout',
                backgroundColor: const Color(0xFFF9D8D6),
                borderColor: const Color(0xFFEAA09C),
                iconColor: const Color(0xFFCC0000),
                textColor: const Color(0xFFCC0000),
                onTap: () => _handleLogout(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color borderColor,
    required Color iconColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: iconColor,
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}