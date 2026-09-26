import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/auth_api.dart';
import '../../../core/services/user_session.dart';
import '../../commuter/screens/commuter_dashboard_screen.dart';
import 'commuter_verification_screen.dart';
import 'commuter_verified_screen.dart';

/// Shown when the submission couldn't be auto-approved. Tells the commuter
/// what happened, lets them check whether an admin has decided yet, and — if
/// it was rejected — shows the reason and lets them submit a new ID.
class CommuterPendingReviewScreen extends StatefulWidget {
  const CommuterPendingReviewScreen({super.key, required this.reviewReasons});

  final List<String> reviewReasons;

  @override
  State<CommuterPendingReviewScreen> createState() =>
      _CommuterPendingReviewScreenState();
}

class _CommuterPendingReviewScreenState
    extends State<CommuterPendingReviewScreen> {
  bool _isChecking = false;
  String? _rejectionReason; // non-null once an admin rejected the submission
  String? _message; // transient feedback from the last status check

  bool get _isRejected => _rejectionReason != null;

  String get _explanation {
    final reasons = widget.reviewReasons;
    if (reasons.contains('FACE_NOT_MATCHED')) {
      return "Your selfie didn't match the photo on your ID.";
    }
    if (reasons.contains('BIRTH_DATE_MISMATCH')) {
      return "The birthdate on your ID doesn't match the one you signed up with.";
    }
    if (reasons.contains('BIRTH_DATE_UNREADABLE') ||
        reasons.contains('EXPIRY_DATE_UNREADABLE')) {
      return "We couldn't read the dates on your ID clearly.";
    }
    return "We couldn't automatically confirm your face against your ID.";
  }

  Future<void> _checkStatus() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _message = null;
    });

    try {
      final result = await AuthApi.getIdStatus(
        token: UserSession.instance.token ?? '',
      );
      if (!mounted) return;

      if (result.status == 'VERIFIED') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CommuterVerifiedScreen(idType: result.idTypeLabel ?? 'ID'),
          ),
        );
        return;
      }

      setState(() {
        _isChecking = false;
        if (result.status == 'NONE' && result.rejectionReason != null) {
          _rejectionReason = result.rejectionReason;
        } else {
          _message =
              "Still under review. We'll have an answer soon — check again in a bit.";
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _message = e.message;
      });
    }
  }

  void _submitNewId() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CommuterVerificationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rejected = _isRejected;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: rejected
                      ? const Color(0xFFFDE8E8)
                      : const Color(0xFFFFF4E0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  rejected ? Icons.close_rounded : Icons.hourglass_top_rounded,
                  color: rejected
                      ? const Color(0xFFE23F3F)
                      : const Color(0xFFE59A00),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                rejected
                    ? 'Verification Rejected'
                    : 'Verification Under Review',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                rejected
                    ? 'Our team reviewed your submission and could not approve it.'
                    : '$_explanation Your submission has been sent for manual verification by our team. '
                          "You can't book rides until it's approved.",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              if (rejected) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE23F3F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _rejectionReason!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isChecking
                      ? null
                      : (rejected ? _submitNewId : _checkStatus),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(
                      alpha: 0.6,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : Text(
                          rejected ? 'Submit a New ID' : 'Check Status',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onPrimary,
                          ),
                        ),
                ),
              ),
              if (!rejected)
                TextButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const CommuterDashboardScreen(),
                    ),
                    (route) => false,
                  ),
                  child: const Text('Continue to app for now'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
