import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'change_password_screen.dart';

class CheckSmsScreen extends StatefulWidget {
  final String phoneNumber;

  const CheckSmsScreen({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<CheckSmsScreen> createState() => _CheckSmsScreenState();
}

class _CheckSmsScreenState extends State<CheckSmsScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Helper to mask phone numbers so only the last 3 digits remain visible
  String _getMaskedPhoneNumber(String phone) {
    final cleanPhone = phone.trim();
    if (cleanPhone.length <= 3) {
      return cleanPhone;
    }
    final String lastThree = cleanPhone.substring(cleanPhone.length - 3);
    final String asterisks = '*' * (cleanPhone.length - 3);
    return '$asterisks$lastThree';
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

  void _verifyCode() async {
    FocusScope.of(context).unfocus();

    if (_formKey.currentState?.validate() ?? false) {
      final String code = _codeController.text.trim();

      if (code.length < 4) {
        _showErrorSnackBar('Please enter a valid verification code.');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        // Simulate API verification delay
        await Future.delayed(const Duration(seconds: 2));

        if (!mounted) return;

        // Example error condition for testing invalid codes
        if (code == '0000' || code == '000000') {
          _showErrorSnackBar('Invalid or expired verification code. Please try again.');
          setState(() {
            _isLoading = false;
          });
          return;
        }

        setState(() {
          _isLoading = false;
        });

        // Seamless transition to Change Password Screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ChangePasswordScreen(),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('Network error. Please check your connection.');
      }
    } else {
      _showErrorSnackBar('Please enter the code sent to your phone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String maskedPhone = _getMaskedPhoneNumber(widget.phoneNumber);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),

                // 1. ManibelApp Branding Logo
                RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'Manibel',
                        style: TextStyle(color: Color(0xFF0038FF)),
                      ),
                      TextSpan(
                        text: 'App',
                        style: TextStyle(color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Screen Header Title
                const Text(
                  'Check Your SMS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Dynamic Masked Phone Message
                Text(
                  "We've sent a code to your phone number\n[$maskedPhone]",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black45,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Code Expiration Warning
                const Text(
                  'The code will expire in 15 minutes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 32),

                // 5. Verification Code Input Box
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                    letterSpacing: 2,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter code';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter code',
                    hintStyle: const TextStyle(
                      color: Colors.black26,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF2F2F2),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF0038FF), width: 1.8),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 6. Send Code Action Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE5A800),
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Send Code',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // 7. Return to Welcome / Login Link
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  ),
                  child: const Text(
                    'Back to Welcome',
                    style: TextStyle(
                      color: Color(0xFF0038FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
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