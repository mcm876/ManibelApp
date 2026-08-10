/// Thrown by [ApiClient] for any non-2xx response, or when the request
/// couldn't be sent at all (network unreachable). [code] is the backend's
/// machine-readable `error` field (e.g. `invalid_credentials`,
/// `mobile_already_registered`) — check it when a screen needs to react
/// differently to specific failures, and fall back to [message] for
/// anything shown straight to the user.
class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}
