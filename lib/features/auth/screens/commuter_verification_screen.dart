import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import 'commuter_face_verification_screen.dart';

const List<String> _idTypeOptions = [
  'Philippine National ID (PhilSys)',
  "Driver's License",
  'Passport',
  'UMID',
  "Voter's ID",
  'Postal ID',
  'SSS ID',
  'PRC ID',
  'Senior Citizen ID',
];

const int _maxUploadBytes = 8 * 1024 * 1024; // 8 MB

class CommuterVerificationScreen extends StatefulWidget {
  const CommuterVerificationScreen({super.key});

  @override
  State<CommuterVerificationScreen> createState() => _CommuterVerificationScreenState();
}

class _CommuterVerificationScreenState extends State<CommuterVerificationScreen> {
  final ImagePicker _picker = ImagePicker();

  String? _selectedId;
  File? _frontImage;
  File? _backImage;
  bool _ageConfirmed = false;
  bool _isVerifying = false;
  bool _isPickingImage = false;

  String? _idError;
  String? _frontError;
  String? _backError;
  String? _ageError;

  bool get _canUploadId => _selectedId != null;

  void _handleIdTypeChanged(String? value) {
    setState(() {
      _selectedId = value;
      _idError = null;
    });
  }

  void _toggleAgeConfirmed(bool? value) {
    setState(() {
      _ageConfirmed = value ?? false;
      _ageError = null;
    });
  }

  Future<void> _pickImage({required bool isFront}) async {
    if (_isPickingImage || !_canUploadId) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Upload ID Photo',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppColors.logoBlue, size: 24),
              title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.logoBlue, size: 24),
              title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    setState(() => _isPickingImage = true);

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null || !mounted) return;

      final file = File(picked.path);
      final sizeBytes = await file.length();

      if (sizeBytes > _maxUploadBytes) {
        setState(() {
          if (isFront) {
            _frontError = 'Image is too large. Please choose one under 8MB.';
          } else {
            _backError = 'Image is too large. Please choose one under 8MB.';
          }
        });
        return;
      }

      setState(() {
        if (isFront) {
          _frontImage = file;
          _frontError = null;
        } else {
          _backImage = file;
          _backError = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final message = 'Could not load that photo. Please try again.';
        if (isFront) {
          _frontError = message;
        } else {
          _backError = message;
        }
      });
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _removeImage({required bool isFront}) {
    if (_isPickingImage) return;
    setState(() {
      if (isFront) {
        _frontImage = null;
      } else {
        _backImage = null;
      }
    });
  }

  Future<void> _handleVerify() async {
    if (_isVerifying) return;

    final idError = _selectedId == null ? 'Please choose a government ID type' : null;
    final frontError = _frontImage == null ? 'Please upload the front of your ID' : null;
    final backError = _backImage == null ? 'Please upload the back of your ID' : null;
    final ageError = !_ageConfirmed ? 'You must confirm you are 18 years old or above' : null;

    setState(() {
      _idError = idError;
      _frontError = frontError;
      _backError = backError;
      _ageError = ageError;
    });

    if (idError != null || frontError != null || backError != null || ageError != null) return;

    setState(() => _isVerifying = true);

    try {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommuterFaceVerificationScreen(idType: _selectedId!),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: Color(0xFFE23F3F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
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
        title: const Text(
          'Identity Verification',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Info Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FE),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.logoBlue, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "We need to verify your identity before you can continue using ManibelApp. Choose a valid government ID and upload clear photos of both sides.",
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1F4B99), height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Dropdown Section
            const Text(
              'Government ID Type',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedId,
              onChanged: _handleIdTypeChanged,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54, size: 26),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black),
              decoration: InputDecoration(
                hintText: 'Select ID type',
                hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w600, fontSize: 15),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.logoBlue, width: 1.8),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE23F3F)),
                ),
                errorText: _idError,
                errorStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
              ),
              items: _idTypeOptions
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
            ),
            const SizedBox(height: 26),

            // Upload Section
            const Text(
              'Upload ID Photos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
            ),
            if (!_canUploadId)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Select a government ID type above to enable uploads.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black45),
                ),
              ),
            const SizedBox(height: 12),

            _IdUploadTile(
              label: 'Front of ID',
              file: _frontImage,
              error: _frontError,
              disabled: _isPickingImage || !_canUploadId,
              onUpload: () => _pickImage(isFront: true),
              onRemove: () => _removeImage(isFront: true),
            ),
            const SizedBox(height: 16),

            _IdUploadTile(
              label: 'Back of ID',
              file: _backImage,
              error: _backError,
              disabled: _isPickingImage || !_canUploadId,
              onUpload: () => _pickImage(isFront: false),
              onRemove: () => _removeImage(isFront: false),
            ),
            const SizedBox(height: 26),

            // Age Confirmation Tile
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
                border: Border.all(
                  color: _ageError != null ? const Color(0xFFE23F3F) : Colors.transparent,
                ),
              ),
              child: CheckboxListTile(
                value: _ageConfirmed,
                onChanged: _toggleAgeConfirmed,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.logoBlue,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                title: const Text(
                  'I confirm that I am 18 years old or above',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.black),
                ),
              ),
            ),
            if (_ageError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 6),
                child: Text(
                  _ageError!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
                ),
              ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _handleVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.logoBlue,
                  disabledBackgroundColor: AppColors.logoBlue.withOpacity(0.6),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdUploadTile extends StatelessWidget {
  const _IdUploadTile({
    required this.label,
    required this.file,
    required this.onUpload,
    required this.onRemove,
    this.error,
    this.disabled = false,
  });

  final String label;
  final File? file;
  final String? error;
  final bool disabled;
  final VoidCallback onUpload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;

    return Opacity(
      opacity: disabled && !hasImage ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: disabled ? null : onUpload,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: error != null
                        ? const Color(0xFFE23F3F)
                        : (hasImage ? const Color(0xFF2E9E6D) : const Color(0xFFEDEDED)),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: hasImage
                          ? Image.file(file!, width: 72, height: 52, fit: BoxFit.cover)
                          : Container(
                              width: 72,
                              height: 52,
                              color: const Color(0xFFF5F6F8),
                              child: const Icon(Icons.badge_outlined, color: Colors.black38, size: 28),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasImage ? 'Photo selected' : 'Tap to take a photo or upload',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: hasImage ? const Color(0xFF2E9E6D) : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasImage)
                      IconButton(
                        onPressed: disabled ? null : onRemove,
                        icon: const Icon(Icons.close_rounded, color: Colors.black45, size: 22),
                      )
                    else
                      Icon(
                        Icons.upload_rounded,
                        color: disabled ? Colors.black26 : AppColors.logoBlue,
                        size: 24,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 6),
              child: Text(
                error!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
              ),
            ),
        ],
      ),
    );
  }
}