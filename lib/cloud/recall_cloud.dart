import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'cloud_gateway.dart';
import 'recall_api.dart';
import 'recall_session.dart';

export 'cloud_gateway.dart';
export 'recall_api.dart';
export 'recall_session.dart';

class RecallCloudConfig {
  const RecallCloudConfig({
    this.apiKey = '',
    this.appId = '',
    this.projectId = '',
    this.authDomain = '',
    this.messagingSenderId = '',
    this.storageBucket = '',
    this.apiUrl = '',
    this.publicAppUrl = '',
  });
  const RecallCloudConfig.fromEnvironment()
    : apiKey = const String.fromEnvironment('FIREBASE_API_KEY'),
      appId = const String.fromEnvironment('FIREBASE_APP_ID'),
      projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      authDomain = const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      messagingSenderId = const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      storageBucket = const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      apiUrl = const String.fromEnvironment('RECALL_API_URL'),
      publicAppUrl = const String.fromEnvironment('PUBLIC_APP_URL');
  final String apiKey,
      appId,
      projectId,
      authDomain,
      messagingSenderId,
      storageBucket,
      apiUrl,
      publicAppUrl;
  bool get configured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      projectId.isNotEmpty &&
      messagingSenderId.isNotEmpty;
  Uri get endpoint => Uri.parse(
    apiUrl.isEmpty
        ? 'https://europe-west1-$projectId.cloudfunctions.net/recallApi'
        : apiUrl,
  );
  String? get validationError {
    if (!configured) return 'Cloud accounts are not configured in this build.';
    if (!apiKey.startsWith('AIza') ||
        apiKey.contains(RegExp(r'\s')) ||
        apiKey.contains('PRIVATE KEY') ||
        !RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(projectId) ||
        !RegExp(r'^1:\d+:(web|android|ios):[a-zA-Z0-9]+$').hasMatch(appId) ||
        !RegExp(r'^\d+$').hasMatch(messagingSenderId)) {
      return 'The Firebase public configuration is invalid.';
    }
    final uri = Uri.tryParse(
      apiUrl.isEmpty
          ? 'https://europe-west1-$projectId.cloudfunctions.net/recallApi'
          : apiUrl,
    );
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                ['localhost', '127.0.0.1'].contains(uri.host)))) {
      return 'The cloud service requires a secure connection.';
    }
    if (publicAppUrl.isNotEmpty) {
      final public = Uri.tryParse(publicAppUrl);
      if (public == null ||
          public.host.isEmpty ||
          public.userInfo.isNotEmpty ||
          public.hasQuery ||
          public.hasFragment ||
          (public.scheme != 'https' &&
              !(public.scheme == 'http' &&
                  ['localhost', '127.0.0.1'].contains(public.host)))) {
        return 'The public app address is invalid.';
      }
    }
    return null;
  }

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: messagingSenderId,
    authDomain: authDomain.isEmpty ? '$projectId.firebaseapp.com' : authDomain,
    storageBucket: storageBucket.isEmpty ? null : storageBucket,
  );
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
    RecallApiClient? client,
  }) => RecallCloud._(
    session: session,
    projects: projects,
    reviews: reviews,
    client: client,
  );
  final RecallApiClient? client;
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
      final app = Firebase.apps.isEmpty
          ? await Firebase.initializeApp(options: config.options)
          : Firebase.app();
      if (app.options.projectId != config.projectId ||
          app.options.appId != config.appId) {
        throw StateError('Firebase environment mismatch');
      }
      final auth = FirebaseAuth.instanceFor(app: app);
      final identity = FirebaseRecallIdentity(auth);
      final client = RecallApiClient(
        endpoint: config.endpoint,
        identity: identity,
      );
      final provider = FirebaseRecallAuthProvider(
        auth: auth,
        client: client,
        publicAppUrl: config.publicAppUrl,
      );
      final session = RecallSessionManager(provider: provider);
      return RecallCloud._(
        client: client,
        session: session,
        projects: RpcCloudProjectGateway(
          transport: client,
          currentUserId: () => session.userId,
        ),
        reviews: RpcCloudReviewGateway(transport: client),
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

class FirebaseRecallIdentity implements RecallApiIdentity {
  const FirebaseRecallIdentity(this.auth);
  final FirebaseAuth auth;
  @override
  String? get userId => auth.currentUser?.uid;
  @override
  Stream<String?> get userChanges =>
      auth.userChanges().map((user) => user?.uid);
  @override
  Future<String?> getIdToken() async {
    final user = auth.currentUser;
    if (user == null) return null;
    final token = await user.getIdToken();
    if (auth.currentUser?.uid != user.uid) {
      throw const CloudException(
        'The account changed. Open the workspace again.',
        code: 'account_changed',
      );
    }
    return token;
  }
}

CloudException _authError(
  FirebaseAuthException error,
) => CloudException(switch (error.code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'The email or password is incorrect.',
  'email-already-in-use' =>
    'This email may already have an account. Try signing in.',
  'weak-password' => 'Choose a stronger password and try again.',
  'too-many-requests' =>
    'Please wait before trying this account request again.',
  'requires-recent-login' => 'Sign in again to continue.',
  'network-request-failed' =>
    'The cloud service could not be reached. Check your connection and try again.',
  _ => 'This account request could not be completed. Try again.',
}, code: error.code);

class FirebaseRecallAuthProvider implements RecallAuthProvider {
  const FirebaseRecallAuthProvider({
    required this.auth,
    required this.client,
    this.publicAppUrl = '',
  });
  final FirebaseAuth auth;
  final RecallApiClient client;
  final String publicAppUrl;
  ActionCodeSettings? get _actionSettings => publicAppUrl.isEmpty
      ? null
      : ActionCodeSettings(url: publicAppUrl, handleCodeInApp: false);
  RecallAccount? _account(User? user) => user == null
      ? null
      : RecallAccount(
          id: user.uid,
          email: user.email ?? '',
          emailVerified: user.emailVerified,
        );
  @override
  RecallAccount? get currentAccount => _account(auth.currentUser);
  @override
  Stream<RecallAuthEvent> get changes =>
      auth.userChanges().map((user) => RecallAuthEvent(_account(user)));
  Future<void> _call(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      throw _authError(error);
    }
  }

  @override
  Future<void> signIn(String email, String password) => _call(() async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  });
  @override
  Future<void> signUp(String email, String password) => _call(() async {
    final result = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = result.user;
    if (user == null) {
      throw const CloudException(
        'This account request could not be completed. Try again.',
      );
    }
    await user.sendEmailVerification(_actionSettings);
  });
  @override
  Future<void> signOut() => _call(auth.signOut);
  @override
  Future<void> sendPasswordReset(String email) => _call(
    () => auth.sendPasswordResetEmail(
      email: email,
      actionCodeSettings: _actionSettings,
    ),
  );
  @override
  Future<void> updatePassword(String password) => _call(() async {
    final user = auth.currentUser;
    if (user == null) throw const CloudException('Sign in again to continue.');
    await user.updatePassword(password);
  });
  @override
  Future<void> resendVerification(String email) => _call(() async {
    final user = auth.currentUser;
    if (user == null || user.email?.toLowerCase() != email.toLowerCase()) {
      throw const CloudException('Sign in again to continue.');
    }
    await user.sendEmailVerification(_actionSettings);
  });
  @override
  Future<void> refreshAccount() => _call(() async {
    final user = auth.currentUser;
    if (user == null) throw const CloudException('Sign in again to continue.');
    await user.reload();
    if (auth.currentUser?.uid != user.uid) {
      throw const CloudException(
        'The account changed. Open the workspace again.',
      );
    }
    await auth.currentUser?.getIdToken(true);
  });
  @override
  Future<void> reauthenticate(String password) => _call(() async {
    final user = auth.currentUser;
    if (user == null || user.email == null) {
      throw const CloudException('Sign in again to continue.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    if (auth.currentUser?.uid != user.uid) {
      throw const CloudException(
        'The account changed. Open the workspace again.',
      );
    }
    await user.getIdToken(true);
  });
  @override
  Future<void> deleteAccount() async {
    final result = await client.invoke('account-delete');
    if (result is! Map || result['deleted'] != true) {
      throw const CloudException(
        'Your account could not be deleted. Please try again.',
      );
    }
  }
}
