import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/auth_api.dart';
import '../../../core/services/id_date_parser.dart';
import '../../../core/services/user_session.dart';
import 'commuter_face_verification_screen.dart';

const int _maxUploadBytes = 8 * 1024 * 1024; // 8 MB

class CommuterVerificationScreen extends StatefulWidget {
  const CommuterVerificationScreen({super.key});

  @override
  State<CommuterVerificationScreen> createState() =>
      _CommuterVerificationScreenState();
}

class _CommuterVerificationScreenState
    extends State<CommuterVerificationScreen> {
  final ImagePicker _picker = ImagePicker();

  List<GovernmentIdType> _idTypes = const [];
  bool _isLoadingTypes = true;
  String? _typesError;

  GovernmentIdType? _selectedId;
  File? _frontImage;
  File? _backImage;
  bool _ageConfirmed = false;
  bool _isVerifying = false;
  bool _isPickingImage =
      false; // guards against double taps while a picker sheet/IO op is in flight

  String? _idError;
  String? _frontError;
  String? _backError;
  String? _ageError;

  bool get _canUploadId => _selectedId != null;
  bool get _needsBack => _selectedId?.requiresBack ?? true;

  @override
  void initState() {
    super.initState();
    _loadIdTypes();
  }

  Future<void> _loadIdTypes() async {
    setState(() {
      _isLoadingTypes = true;
      _typesError = null;
    });
    try {
      final types = await AuthApi.getIdTypes(
        token: UserSession.instance.token ?? '',
      );
      if (!mounted) return;
      setState(() {
        _idTypes = types;
        _isLoadingTypes = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _typesError = e.message;
        _isLoadingTypes = false;
      });
    }
  }

  void _handleIdTypeChanged(String? code) {
    setState(() {
      _selectedId = _idTypes.where((t) => t.code == code).firstOrNull;
      if (!_needsBack) {
        _backImage = null;
        _backError = null;
      }
      _idError = null;
    });
  }

  /// Reads all text off the ID photos on-device. Returns '' if OCR isn't
  /// available (e.g. unsupported platform) — dates then come back null and
  /// the backend sends the submission to manual review.
  Future<String> _readIdText(List<File> images) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final buffer = StringBuffer();
      for (final image in images) {
        final result = await recognizer.processImage(
          InputImage.fromFile(image),
        );
        buffer.writeln(result.text);
      }
      return buffer.toString();
    } catch (_) {
      return '';
    } finally {
      await recognizer.close();
    }
  }

  void _toggleAgeConfirmed(bool? value) {
    setState(() {
      _ageConfirmed = value ?? false;
      _ageError = null;
    });
  }

  Future<void> _pickImage({required bool isFront}) async {
    // Guard at the source too, not just via the tile's disabled state — in
    // case this ever gets called some other way before an ID type exists.
    if (_isPickingImage || !_canUploadId) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Upload ID Photo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_rounded,
                color: AppColors.logoBlue,
              ),
              title: const Text(
                'Take Photo',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.logoBlue,
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    setState(() => _isPickingImage = true);

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null || !mounted) return; // user cancelled

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
    if (_isVerifying) return; // prevent duplicate submissions

    // --- Validation --------------------------------------------------
    final idError = _selectedId == null
        ? 'Please choose a government ID type'
        : null;
    final frontError = _frontImage == null
        ? 'Please upload the front of your ID'
        : null;
    final backError = _needsBack && _backImage == null
        ? 'Please upload the back of your ID'
        : null;
    final ageError = !_ageConfirmed
        ? 'You must confirm you are 18 years old or above'
        : null;

    setState(() {
      _idError = idError;
      _frontError = frontError;
      _backError = backError;
      _ageError = ageError;
    });

    if (idError != null ||
        frontError != null ||
        backError != null ||
        ageError != null)
      return;

    setState(() => _isVerifying = true);

    try {
      final text = await _readIdText([
        _frontImage!,
        if (_backImage != null) _backImage!,
      ]);
      if (!mounted) return;
      final dates = parseIdDates(text);

      // Fail fast on what the ID already proves; the backend re-checks.
      final today = DateTime.now();
      final birth = dates.birthDate;
      if (birth != null) {
        var age = today.year - birth.year;
        if (today.month < birth.month ||
            (today.month == birth.month && today.day < birth.day))
          age--;
        if (age < 18) {
          setState(
            () => _frontError =
                'The birthdate on this ID shows you are under 18. You must be 18 or older.',
          );
          return;
        }
      }
      final expiry = dates.expiryDate;
      if (_selectedId!.hasExpiry && expiry != null) {
        final startOfToday = DateTime.utc(today.year, today.month, today.day);
        if (expiry.isBefore(startOfToday)) {
          setState(
            () => _frontError =
                'This ID expired on ${toIsoDate(expiry)}. Please use a valid, unexpired ID.',
          );
          return;
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CommuterFaceVerificationScreen(
            idType: _selectedId!,
            frontImage: _frontImage!,
            backImage: _backImage,
            birthDate: birth,
            expiryDate: expiry,
          ),
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.settingsTileBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.settingsIconColor,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "We need to verify your identity before you can book rides. Choose a valid government ID and upload clear photos of both sides.",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.settingsIconColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Government ID Type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            if (_isLoadingTypes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                ),
              )
            else if (_typesError != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _typesError!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE23F3F),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadIdTypes,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedId?.code,
                onChanged: _handleIdTypeChanged,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.black54,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: 'Select ID type',
                  hintStyle: const TextStyle(
                    color: Colors.black38,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.logoBlue,
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE23F3F)),
                  ),
                  errorText: _idError,
                  errorStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE23F3F),
                  ),
                ),
                items: _idTypes
                    .map(
                      (t) =>
                          DropdownMenuItem(value: t.code, child: Text(t.label)),
                    )
                    .toList(),
              ),
            const SizedBox(height: 20),
            const Text(
              'Upload ID Photos',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            if (!_canUploadId)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Select a government ID type above to enable uploads.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black45,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _IdUploadTile(
              label: 'Front of ID',
              file: _frontImage,
              error: _frontError,
              disabled: _isPickingImage || !_canUploadId,
              onUpload: () => _pickImage(isFront: true),
              onRemove: () => _removeImage(isFront: true),
            ),
            if (_needsBack) ...[
              const SizedBox(height: 12),
              _IdUploadTile(
                label: 'Back of ID',
                file: _backImage,
                error: _backError,
                disabled: _isPickingImage || !_canUploadId,
                onUpload: () => _pickImage(isFront: false),
                onRemove: () => _removeImage(isFront: false),
              ),
            ],
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: _ageError != null
                      ? const Color(0xFFE23F3F)
                      : Colors.transparent,
                ),
              ),
              child: CheckboxListTile(
                value: _ageConfirmed,
                onChanged: _toggleAgeConfirmed,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.logoBlue,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: const Text(
                  'I confirm that I am 18 years old or above',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            if (_ageError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _ageError!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE23F3F),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _handleVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onPrimary,
                        ),
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
      // Visually communicate the disabled (no-ID-type-yet) state, distinct
      // from the transient "picker in flight" disabled state which doesn't
      // need dimming since it's momentary.
      opacity: disabled && !hasImage ? 0.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: disabled ? null : onUpload,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: error != null
                        ? const Color(0xFFE23F3F)
                        : (hasImage
                              ? AppColors.primary
                              : const Color(0xFFEDEDED)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: hasImage
                          ? Image.file(
                              file!,
                              width: 56,
                              height: 44,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 56,
                              height: 44,
                              color: const Color(0xFFF5F6F8),
                              child: const Icon(
                                Icons.badge_outlined,
                                color: Colors.black38,
                                size: 22,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasImage
                                ? 'Photo selected'
                                : 'Tap to take a photo or upload',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: hasImage
                                  ? AppColors.onPrimary
                                  : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasImage)
                      IconButton(
                        onPressed: disabled ? null : onRemove,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.black45,
                          size: 20,
                        ),
                      )
                    else
                      Icon(
                        Icons.upload_rounded,
                        color: disabled ? Colors.black26 : AppColors.logoBlue,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                error!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE23F3F),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
