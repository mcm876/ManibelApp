import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin JSON wrapper around `package:http`, pointed at the ManibelApp
/// backend (`backend/` — see backend/src/app.ts for the routes this talks
/// to). There's no auth backend deployed anywhere yet, so this only knows
/// about localhost.
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// Set this to point the app at a different host — e.g. your dev
  /// machine's LAN IP when testing from a physical device, since neither
  /// `localhost` nor the Android-emulator alias below reach it. Leave null
  /// to use the default for the current platform.
  static String? baseUrlOverride;

  String get _baseUrl {
    if (baseUrlOverride != null) return baseUrlOverride!;
    // 10.0.2.2 is the Android emulator's alias for its host machine's
    // localhost — plain "localhost" from inside the emulator means the
    // emulator itself, which isn't running the backend.
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }

  Future<Map<String, dynamic>> get(String path, {String? token}) {
    return _send('GET', path, token: token);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) {
    return _send('POST', path, body: body, token: token);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = method == 'GET'
          ? await http.get(uri, headers: headers)
          : await http.post(
              uri,
              headers: headers,
              body: body != null ? jsonEncode(body) : null,
            );
    } catch (_) {
      throw const ApiException(
        statusCode: 0,
        code: 'network_error',
        message: "Couldn't reach the server. Check your connection and try again.",
      );
    }

    final Map<String, dynamic> decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    throw ApiException(
      statusCode: response.statusCode,
      code: (decoded['error'] as String?) ?? 'unknown_error',
      message: _errorMessage(decoded),
    );
  }

  String _errorMessage(Map<String, dynamic> decoded) {
    final message = decoded['message'] as String?;
    if (message != null) return message;

    // Validation errors come back as { error, details: { field: [msg, ...] } }
    final details = decoded['details'];
    if (details is Map) {
      for (final value in details.values) {
        if (value is List && value.isNotEmpty) return value.first.toString();
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
