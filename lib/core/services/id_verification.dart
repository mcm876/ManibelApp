import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'api_client.dart';
import 'id_date_parser.dart';

/// A government ID type from `GET /api/commuter/id-types`. [hasExpiry] says
/// whether that ID prints an expiry date the app should check.
class GovernmentIdType {
  final String label;
  final bool hasExpiry;

  const GovernmentIdType({required this.label, required this.hasExpiry});

  factory GovernmentIdType.fromJson(Map<String, dynamic> json) => GovernmentIdType(
        label: json['label'] as String,
        hasExpiry: json['hasExpiry'] as bool,
      );
}

/// Shared by the sign-up ID step and the rejected-account resubmit screen,
/// so both read and check the ID the same way.
class IdVerification {
  const IdVerification._();

  static const int minAge = 18;

  static Future<List<GovernmentIdType>> fetchIdTypes() async {
    final json = await ApiClient.get('/api/commuter/id-types');
    return (json['idTypes'] as List)
        .map((e) => GovernmentIdType.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Reads the birth and expiry dates off the ID photos, on-device. Returns
  /// empty dates if OCR isn't available or finds nothing — the backend then
  /// sends the submission to manual review rather than approving it.
  static Future<IdDates> readDates(List<File> images) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final buffer = StringBuffer();
      for (final image in images) {
        final result = await recognizer.processImage(InputImage.fromFile(image));
        buffer.writeln(result.text);
      }
      return parseIdDates(buffer.toString());
    } catch (_) {
      return const IdDates();
    } finally {
      await recognizer.close();
    }
  }

  /// A message if the dates read off the ID already prove it can't be used
  /// (expired, or the holder is under [minAge]); null if it's fine or the
  /// dates couldn't be read. The backend re-checks this.
  static String? rejectionMessage(IdDates dates, {required bool hasExpiry, DateTime? now}) {
    final today = now ?? DateTime.now();

    final birth = dates.birthDate;
    if (birth != null) {
      var age = today.year - birth.year;
      if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) {
        age--;
      }
      if (age < minAge) {
        return 'The birthdate on this ID shows you are under $minAge. You must be $minAge or older to use ManibelApp.';
      }
    }

    final expiry = dates.expiryDate;
    if (hasExpiry && expiry != null) {
      final startOfToday = DateTime.utc(today.year, today.month, today.day);
      if (expiry.isBefore(startOfToday)) {
        return 'This ID expired on ${toIsoDate(expiry)}. Please use a valid, unexpired ID.';
      }
    }
    return null;
  }

  /// Plain-language explanation of why an account is waiting on a person,
  /// from the backend's `reviewReasons` codes. Most specific reason first.
  static String reviewExplanation(List<String> reasons) {
    if (reasons.contains('FACE_NOT_MATCHED')) {
      return "Your selfie didn't match the photo on your ID.";
    }
    if (reasons.contains('BIRTH_DATE_MISMATCH')) {
      return "The birthdate on your ID doesn't match the one you signed up with.";
    }
    if (reasons.contains('BIRTH_DATE_UNREADABLE') || reasons.contains('EXPIRY_DATE_UNREADABLE')) {
      return "We couldn't read the dates on your ID clearly.";
    }
    if (reasons.contains('FACE_UNVERIFIED')) {
      return "We couldn't automatically confirm your face against your ID.";
    }
    return '';
  }
}
