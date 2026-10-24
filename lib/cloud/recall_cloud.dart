import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_gateway.dart';
import 'recall_session.dart';

export 'cloud_gateway.dart';
export 'recall_session.dart';

class RecallCloudConfig {
  const RecallCloudConfig({
    required this.url,
    required this.anonKey,
    this.authRedirectUrl,
  });
  const RecallCloudConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
      authRedirectUrl = const String.fromEnvironment('AUTH_REDIRECT_URL');
  final String url;
  final String anonKey;
  final String? authRedirectUrl;
  bool get configured => url.isNotEmpty && anonKey.isNotEmpty;
  String? get validationError {
    if (!configured) return 'Cloud accounts are not configured in this build.';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme)) {
      return 'The cloud service URL is invalid.';
    }
    if (uri.scheme != 'https' &&
        !['localhost', '127.0.0.1'].contains(uri.host)) {
      return 'The cloud service requires a secure connection.';
    }
    if (anonKey.startsWith('sb_secret_')) {
      return 'A public client key is required.';
    }
    final parts = anonKey.split('.');
    if (parts.length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (payload is Map && payload['role'] != 'anon') {
          return 'A public client key is required.';
        }
      } catch (_) {
        return 'The public client key is invalid.';
      }
    }
    return null;
  }
}

/// Auth sessions and PKCE verifiers use platform secure storage, scoped to the
/// configured backend so switching environments cannot restore another session.
class SecureRecallAuthStorage extends LocalStorage {
  SecureRecallAuthStorage({
    required this.namespace,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();
  final String namespace;
  final FlutterSecureStorage _storage;
  String get _key => 'recall.auth.$namespace.session.v1';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

class SecureRecallPkceStorage extends GotrueAsyncStorage {
  SecureRecallPkceStorage({
    required this.namespace,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();
  final String namespace;
  final FlutterSecureStorage _storage;
  String _key(String key) => 'recall.auth.$namespace.pkce.$key';
  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: _key(key));
  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: _key(key), value: value);
  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: _key(key));
}

class RecallCloud {
  RecallCloud._({
    required this.session,
    this.client,
    this.projects,
    this.reviews,
  });
  factory RecallCloud.forTesting({
    required RecallSessionManager session,
    CloudProjectGateway? projects,
    CloudReviewGateway? reviews,
    SupabaseClient? client,
  }) => RecallCloud._(
    session: session,
    projects: projects,
    reviews: reviews,
    client: client,
  );
  final SupabaseClient? client;
  final RecallSessionManager session;
  final CloudProjectGateway? projects;
  final CloudReviewGateway? reviews;
  static Future<RecallCloud> initialize({
    RecallCloudConfig config = const RecallCloudConfig.fromEnvironment(),
  }) async {
    final invalid = config.validationError;
    if (invalid != null) {
      return RecallCloud._(
        session: RecallSessionManager(configurationError: invalid),
      );
    }
    try {
      final namespace = base64Url.encode(utf8.encode(config.url));
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.anonKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureRecallAuthStorage(namespace: namespace),
          pkceAsyncStorage: SecureRecallPkceStorage(namespace: namespace),
        ),
      );
      final client = Supabase.instance.client;
      final auth = SupabaseRecallAuthProvider(
        client,
        redirectUrl: config.authRedirectUrl,
      );
      final session = RecallSessionManager(provider: auth);
      final transport = SupabaseRecallTransport(
        client,
        supabaseUrl: config.url,
        publicKey: config.anonKey,
      );
      return RecallCloud._(
        client: client,
        session: session,
        projects: RpcCloudProjectGateway(
          transport: transport,
          currentUserId: () => session.userId,
        ),
        reviews: RpcCloudReviewGateway(transport: transport),
      );
    } catch (_) {
      return RecallCloud._(
        session: RecallSessionManager(
          configurationError:
              'Cloud sign in could not start. Check this build’s cloud settings and secure storage access.',
        ),
      );
    }
  }
}

CloudException _friendlyCloudError(Object problem) {
  if (problem is CloudException) return problem;
  if (problem is PostgrestException) {
    final message = switch (problem.code) {
      '40001' =>
        'This plan changed or this review is already closed. Refresh to review the latest version.',
      'P0002' =>
        'This project or review link is unavailable, expired, or revoked.',
      '28000' => 'Sign in again to continue.',
      '22023' =>
        'This change could not be accepted. Review the fields and try again.',
      '23505' =>
        'This request was already recorded. Refresh to see the result.',
      '54000' =>
        'Your workspace has reached its project limit. Review your subscription or remove a project.',
      _ => 'The cloud request could not be completed. Try again.',
    };
    return CloudException(message, code: problem.code);
  }
  if (problem is AuthException) {
    return CloudException(switch (problem.code) {
      'email_not_confirmed' =>
        'Verify your email before signing in. Check your inbox for the verification link.',
      'invalid_credentials' => 'The email or password is incorrect.',
      'weak_password' => 'Choose a stronger password and try again.',
      'over_email_send_rate_limit' =>
        'Please wait before requesting another email.',
      'user_already_exists' =>
        'This email may already have an account. Try signing in.',
      _ => 'This account request could not be completed. Try again.',
    }, code: problem.code);
  }
  return const CloudException(
    'The cloud service could not be reached. Check your connection and try again.',
  );
}

class SupabaseRecallTransport implements CloudRpcTransport {
  SupabaseRecallTransport(
    this.client, {
    required this.supabaseUrl,
    required this.publicKey,
    this.publicHttpClient,
  });
  final SupabaseClient client;
  final String supabaseUrl;
  final String publicKey;
  // Injected clients remain owned by their caller. Production creates and
  // closes a plain HTTP client for each public request, with no Auth wrapper.
  final http.Client? publicHttpClient;

  Future<dynamic> _publicRpc(
    String function,
    Map<String, dynamic> params,
  ) async {
    final plainHttp = publicHttpClient ?? http.Client();
    final rest = PostgrestClient(
      '${supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/rest/v1',
      headers: {'apikey': publicKey},
      httpClient: plainHttp,
      retryEnabled: false,
      requestTimeout: const Duration(seconds: 30),
    );
    try {
      // Publishable keys are not JWTs. Public bearer reviews use the apikey
      // header only and cannot inherit an expired or different private session.
      return await rest.rpc(function, params: params);
    } finally {
      try {
        await rest.dispose();
      } finally {
        if (publicHttpClient == null) plainHttp.close();
      }
    }
  }

  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) async {
    try {
      if (function == 'recall_review_link' ||
          function == 'recall_respond_review') {
        return await _publicRpc(function, params);
      }
      // Capture the real user JWT before the SDK's async token lookup. Its
      // AuthHttpClient preserves this per-request header during account changes.
      final bearer = client.auth.currentSession?.accessToken;
      if (bearer == null) {
        throw const CloudException('Sign in again to continue.');
      }
      return await client
          .rpc(function, params: params)
          .setHeader('Authorization', 'Bearer $bearer');
    } catch (problem) {
      throw _friendlyCloudError(problem);
    }
  }
}

class SupabaseRecallAuthProvider implements RecallAuthProvider {
  SupabaseRecallAuthProvider(this.client, {this.redirectUrl});
  final SupabaseClient client;
  final String? redirectUrl;
  String? get _redirect => redirectUrl?.isNotEmpty == true
      ? redirectUrl
      : kIsWeb
      ? Uri.base.replace(query: '', fragment: '').toString()
      : 'io.recall.app://login-callback';
  RecallAccount? _account(User? user) => user == null
      ? null
      : RecallAccount(
          id: user.id,
          email: user.email ?? '',
          emailVerified: user.emailConfirmedAt != null,
        );
  @override
  RecallAccount? get currentAccount => _account(client.auth.currentUser);
  @override
  Stream<RecallAuthEvent> get changes => client.auth.onAuthStateChange.map(
    (state) => RecallAuthEvent(
      _account(state.session?.user),
      passwordRecovery: state.event == AuthChangeEvent.passwordRecovery,
    ),
  );
  Future<void> _call(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (problem) {
      throw _friendlyCloudError(problem);
    }
  }

  @override
  Future<void> signIn(String email, String password) => _call(() async {
    await client.auth.signInWithPassword(email: email, password: password);
  });
  @override
  Future<void> signUp(String email, String password) => _call(() async {
    await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: _redirect,
    );
  });
  @override
  Future<void> signOut() => _call(() async {
    await client.auth.signOut();
  });
  @override
  Future<void> sendPasswordReset(String email) => _call(() async {
    await client.auth.resetPasswordForEmail(email, redirectTo: _redirect);
  });
  @override
  Future<void> updatePassword(String password) => _call(() async {
    await client.auth.updateUser(UserAttributes(password: password));
  });
  @override
  Future<void> resendVerification(String email) => _call(() async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: _redirect,
    );
  });
  @override
  Future<void> refreshAccount() => _call(() async {
    await client.auth.refreshSession();
  });
  @override
  Future<void> deleteAccount() => _call(() async {
    final bearer = client.auth.currentSession?.accessToken;
    if (bearer == null) {
      throw const CloudException('Sign in again to continue.');
    }
    final response = await client.functions.invoke(
      'account-delete',
      headers: {'Authorization': 'Bearer $bearer'},
    );
    if (response.status != 200) {
      throw const CloudException(
        'Your account could not be deleted. Please try again.',
      );
    }
  });
}
