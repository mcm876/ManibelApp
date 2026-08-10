import 'package:flutter/material.dart';
import '../../../core/services/user_session.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  static const int _minLength = 8;
  static final RegExp _hasUppercase = RegExp(r'[A-Z]');
  static final RegExp _hasLowercase = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');
  static final RegExp _hasSpecialChar =
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]\\/;+=~`]');

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateCurrentPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) {
      return 'Enter your current password';
    }
    if (UserSession.instance.password != null &&
        v != UserSession.instance.password) {
      return 'Current password is incorrect';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) {
      return 'Enter a new password';
    }
    if (v.length < _minLength) {
      return 'Must be at least $_minLength characters';
    }
    if (v.length > 128) {
      return 'Password is too long';
    }
    if (!_hasUppercase.hasMatch(v)) {
      return 'Must include at least one uppercase letter';
    }
    if (!_hasLowercase.hasMatch(v)) {
      return 'Must include at least one lowercase letter';
    }
    if (!_hasDigit.hasMatch(v)) {
      return 'Must include at least one number';
    }
    if (!_hasSpecialChar.hasMatch(v)) {
      return 'Must include at least one special character';
    }
    if (v.contains(' ')) {
      return 'Password cannot contain spaces';
    }
    if (_currentPasswordController.text.isNotEmpty &&
        v == _currentPasswordController.text) {
      return 'New password must be different from your current password';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) {
      return 'Confirm your new password';
    }
    if (v != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted fields.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    final success = await UserSession.instance.updatePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current password is incorrect.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated successfully.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              _TopBar(onBack: () => Navigator.of(context).maybePop()),
              const SizedBox(height: 32),
              _PasswordField(
                label: 'Current Password',
                controller: _currentPasswordController,
                obscureText: _obscureCurrent,
                hintText: 'Enter your current password',
                onToggleObscure: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
                validator: _validateCurrentPassword,
              ),
              const SizedBox(height: 16),
              _PasswordField(
                label: 'New Password',
                controller: _newPasswordController,
                obscureText: _obscureNew,
                hintText: 'Enter a new password',
                onToggleObscure: () =>
                    setState(() => _obscureNew = !_obscureNew),
                validator: _validateNewPassword,
                onChanged: (_) {
                  _formKey.currentState?.validate();
                },
              ),
              const SizedBox(height: 8),
              const _PasswordRequirementsHint(),
              const SizedBox(height: 16),
              _PasswordField(
                label: 'Confirm New Password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                hintText: 'Re-enter your new password',
                onToggleObscure: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                validator: _validateConfirmPassword,
              ),
              const SizedBox(height: 32),
              _SubmitButton(
                isLoading: _isSubmitting,
                onTap: _isSubmitting ? null : _handleSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TOP BAR
/// -----------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onBack,
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
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.black87),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Change Password',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Keep your account secure with a strong password',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black38,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// PASSWORD FIELD
/// -----------------------------------------------------------------------

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.obscureText,
    required this.hintText,
    required this.onToggleObscure,
    required this.validator,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final String hintText;
  final VoidCallback onToggleObscure;
  final String? Function(String?) validator;
  final void Function(String)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: controller,
                  obscureText: obscureText,
                  validator: validator,
                  onChanged: onChanged,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      color: Colors.black26,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    errorStyle: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD32F2F),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            splashRadius: 20,
            icon: Icon(
              obscureText
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 22,
              color: Colors.black54,
            ),
            onPressed: onToggleObscure,
          ),
        ],
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// PASSWORD REQUIREMENTS HINT
/// -----------------------------------------------------------------------

class _PasswordRequirementsHint extends StatelessWidget {
  const _PasswordRequirementsHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'At least 8 characters, with uppercase, lowercase, a number, and a special character.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.black38,
          height: 1.3,
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// SUBMIT BUTTON
/// -----------------------------------------------------------------------

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
          ),
          child: isLoading
              ? const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.published_with_changes_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Update Password',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}