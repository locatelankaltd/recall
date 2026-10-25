import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_gateway.dart';

/// A narrow identity boundary keeps Firebase SDK persistence out of transport
/// tests. Production captures the Firebase User before fetching its ID token.
abstract interface class RecallApiIdentity {
  String? get userId;
  Stream<String?> get userChanges;
  Future<String?> getIdToken();
}

class RecallApiException extends CloudException {
  const RecallApiException(super.message, {super.code, required this.status});
  final int status;
}

String _safeMessage(String? code, int status) => switch (code) {
  '40001' =>
    'This plan changed or this review is already closed. Refresh to review the latest version.',
  'P0002' => 'This project or review link is unavailable, expired, or revoked.',
  '28000' => 'Sign in again to continue.',
  '22023' =>
    'This change could not be accepted. Review the fields and try again.',
  '54000' =>
    'Your workspace has reached a service limit. Export or remove an older project, or try again later.',
  '42501' => 'This account cannot perform that action.',
  _ =>
    status == 401
        ? 'Sign in again to continue.'
        : 'The cloud request could not be completed. Try again.',
};

/// Firebase HTTPS Functions API. It never accepts a service credential or direct
/// provider destination. Public review requests never read private auth state.
class RecallApiClient implements CloudRpcTransport {
  RecallApiClient({
    required this.endpoint,
    required this.identity,
    this.httpClient,
  });
  final Uri endpoint;
  final RecallApiIdentity identity;
  final http.Client? httpClient;
  String? get userId => identity.userId;
  Stream<String?> get userChanges => identity.userChanges;
  static const maxResponseBytes = 8 * 1024 * 1024;
  static const _publicRpc = {'recall_review_link', 'recall_respond_review'};

  Uri _url(String path) =>
      Uri.parse('${endpoint.toString().replaceAll(RegExp(r'/+$'), '')}/$path');

  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) async =>
      _request(
        'rpc',
        body: {'name': function, 'params': params},
        authenticated: !_publicRpc.contains(function),
        unwrapData: true,
      );

  Future<dynamic> invoke(
    String function, {
    Object? body,
    List<http.MultipartFile>? files,
    Future<void>? abortSignal,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9-]{0,80}$').hasMatch(function)) {
      throw const CloudException(
        'The cloud request could not be completed. Try again.',
      );
    }
    return _request(
      function,
      body: body,
      files: files,
      abortSignal: abortSignal,
      preserveDeletionReceipt: function == 'account-delete',
      timeout: const Duration(seconds: 55),
    );
  }

  Future<dynamic> _request(
    String path, {
    Object? body,
    List<http.MultipartFile>? files,
    Future<void>? abortSignal,
    bool authenticated = true,
    bool unwrapData = false,
    bool preserveDeletionReceipt = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    String? owner;
    String? token;
    final abort = Completer<void>();
    final trigger = abortSignal == null
        ? abort.future
        : Future.any<void>([abort.future, abortSignal]);
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final client = httpClient ?? http.Client();
    try {
      if (authenticated) {
        owner = identity.userId;
        if (owner == null) {
          throw const CloudException(
            'Sign in again to continue.',
            code: '28000',
          );
        }
        try {
          token = await Future.any<String?>([
            identity.getIdToken(),
            trigger.then<String?>(
              (_) => throw TimeoutException('The cloud request was cancelled.'),
            ),
          ]);
        } on TimeoutException {
          rethrow;
        } on CloudException {
          rethrow;
        } catch (_) {
          throw const CloudException(
            'Sign in again to continue.',
            code: '28000',
          );
        }
        if (identity.userId != owner) {
          throw const CloudException(
            'The account changed. Open the workspace again.',
            code: 'account_changed',
          );
        }
        if (token == null || token.isEmpty) {
          throw const CloudException(
            'Sign in again to continue.',
            code: '28000',
          );
        }
      }
      final headers = {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final http.BaseRequest request;
      if (files != null) {
        if (body is! Map || body.values.any((value) => value is! String)) {
          throw const CloudException(
            'The cloud request could not be completed. Try again.',
          );
        }
        request =
            http.AbortableMultipartRequest(
                'POST',
                _url(path),
                abortTrigger: trigger,
              )
              ..headers.addAll(headers)
              ..fields.addAll(Map<String, String>.from(body))
              ..files.addAll(files);
      } else {
        request =
            http.AbortableRequest('POST', _url(path), abortTrigger: trigger)
              ..headers.addAll({...headers, 'Content-Type': 'application/json'})
              ..body = jsonEncode(body ?? const {});
      }
      final response = await client.send(request).timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const CloudException(
            'This cloud response is too large to open safely.',
          );
        }
        bytes.addAll(chunk);
      }
      // A deletion receipt is still actionable for its captured owner after a
      // switch: the session manager clears A's files while preserving B's login.
      if (authenticated &&
          !preserveDeletionReceipt &&
          identity.userId != owner) {
        throw const CloudException(
          'The account changed. Open the workspace again.',
          code: 'account_changed',
        );
      }
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const CloudException(
          'The cloud service returned an invalid response.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = data is Map && data['code'] is String
            ? data['code'] as String
            : null;
        throw RecallApiException(
          _safeMessage(code, response.statusCode),
          code: code,
          status: response.statusCode,
        );
      }
      if (unwrapData) {
        if (data is! Map || !data.containsKey('data')) {
          throw const CloudException(
            'The cloud service returned an invalid response.',
          );
        }
        return data['data'];
      }
      return data;
    } on CloudException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on http.RequestAbortedException {
      throw TimeoutException('The cloud request timed out.');
    } catch (_) {
      throw const CloudException(
        'The cloud service could not be reached. Check your connection and try again.',
      );
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
      if (httpClient == null) client.close();
    }
  }
}
