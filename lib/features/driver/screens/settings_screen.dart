import 'package:flutter/material.dart';
import 'settings_change_password_screen.dart';
import '../../auth/screens/driver_login_screen.dart'; // Driver Login screen import

class SettingsScreen extends StatefulWidget {
  final String currentFullName;
  final String currentMobile;
  final String currentEmail;
  final String currentDob;
  final String currentPlateNumber;

  const SettingsScreen({
    super.key,
    required this.currentFullName,
    required this.currentMobile,
    this.currentEmail = 'driver@manibelapp.ph',
    this.currentDob = 'May 15, 1990',
    this.currentPlateNumber = 'ABC 1234',
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fullNameController;
  late TextEditingController _mobileController;
  late TextEditingController _emailController;
  late TextEditingController _dobController;
  late TextEditingController _plateNumberController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _fullNameController = TextEditingController(text: widget.currentFullName);
    _mobileController = TextEditingController(text: widget.currentMobile);
    _emailController = TextEditingController(text: widget.currentEmail);
    _dobController = TextEditingController(text: widget.currentDob);
    _plateNumberController = TextEditingController(text: widget.currentPlateNumber);
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep controllers synced if logged-in driver data changes dynamically
    if (oldWidget.currentFullName != widget.currentFullName) {
      _fullNameController.text = widget.currentFullName;
    }
    if (oldWidget.currentMobile != widget.currentMobile) {
      _mobileController.text = widget.currentMobile;
    }
    if (oldWidget.currentEmail != widget.currentEmail) {
      _emailController.text = widget.currentEmail;
    }
    if (oldWidget.currentDob != widget.currentDob) {
      _dobController.text = widget.currentDob;
    }
    if (oldWidget.currentPlateNumber != widget.currentPlateNumber) {
      _plateNumberController.text = widget.currentPlateNumber;
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Prompts a dialog requiring password verification before changing sensitive data
  Future<bool?> _promptPasswordVerification() async {
    final TextEditingController passwordController = TextEditingController();
    bool isObscured = true;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Security Check',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Please enter your current password to save changes to your Mobile Number or Email Address.',
                    style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: isObscured,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      filled: true,
                      fillColor: const Color(0xFFF2F2F2),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.black45,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            isObscured = !isObscured;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final pwd = passwordController.text.trim();
                    if (pwd.isEmpty) {
                      _showErrorSnackBar('Password cannot be empty.');
                      return;
                    }
                    if (pwd.length < 6) {
                      _showErrorSnackBar('Incorrect password. Please try again.');
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0038FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Confirms and handles driver logout redirect
  Future<void> _confirmAndLogout() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Log Out',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Are you sure you want to log out of your driver account?',
            style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD62828),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Log Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && mounted) {
      _showSuccessSnackBar('Logged out successfully.');

      // Redirect directly to Driver Login screen and clear navigation history
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const DriverLoginScreen(),
        ),
        (route) => false,
      );
    }
  }

  void _saveSettings() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() ?? false) {
      final bool mobileChanged = _mobileController.text.trim() != widget.currentMobile;
      final bool emailChanged = _emailController.text.trim() != widget.currentEmail;

      if (mobileChanged || emailChanged) {
        final verified = await _promptPasswordVerification();
        if (verified != true) return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        await Future.delayed(const Duration(seconds: 1)); // Simulate save request

        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });

        _showSuccessSnackBar('Account settings saved successfully!');
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('Failed to save settings. Please try again.');
      }
    } else {
      _showErrorSnackBar('Please fix the validation errors before saving.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP HEADER SECTION
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.black12, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'Manage your account and preferences',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 2. ACCOUNT SETTINGS HEADER & AVATAR
                const Text(
                  'Account Settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),

                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF5252),
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 65,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. READ-ONLY FULL NAME FIELD
                _buildFieldCard(
                  label: 'Full Name',
                  child: TextFormField(
                    controller: _fullNameController,
                    enabled: false,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. EDITABLE MOBILE NUMBER FIELD
                _buildFieldCard(
                  label: 'Mobile Number',
                  child: TextFormField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Mobile number cannot be empty';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 5. EDITABLE EMAIL ADDRESS FIELD
                _buildFieldCard(
                  label: 'Email Address',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email address cannot be empty';
                      }
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 6. READ-ONLY DATE OF BIRTH FIELD (Non-editable)
                _buildFieldCard(
                  label: 'Date of Birth',
                  child: TextFormField(
                    controller: _dobController,
                    enabled: false,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 7. JEEPNEY PLATE NUMBER FIELD
                _buildFieldCard(
                  label: 'Jeepney Plate Number',
                  child: TextFormField(
                    controller: _plateNumberController,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 8. SECURITY SECTION
                const Text(
                  'Security',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, color: Colors.black, size: 24),
                        SizedBox(width: 14),
                        Text(
                          'Change Password',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.chevron_right_rounded, color: Colors.black45, size: 24),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // 9. SAVE CHANGES BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0038FF),
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // 10. LOG OUT BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _confirmAndLogout,
                    icon: const Icon(Icons.logout_rounded, color: Color(0xFFD62828), size: 22),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(
                        color: Color(0xFFD62828),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFFDE8E8),
                      side: const BorderSide(color: Color(0xFFF1C1C1), width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldCard({
    required String label,
    required Widget child,
    IconData? trailingIcon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 12),
            Icon(trailingIcon, color: Colors.black, size: 28),
          ],
        ],
      ),
    );
  }
}