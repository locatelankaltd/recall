import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recall_next/cloud/recall_cloud.dart';

class TestFirebaseCredential implements UserCredential {
  TestFirebaseCredential(this.user);
  @override
  final User? user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestFirebaseUser implements User {
  TestFirebaseUser({
    required this.uid,
    this.email = 'sam@example.com',
    this.emailVerified = false,
  });
  @override
  final String uid;
  @override
  final String? email;
  @override
  bool emailVerified;
  int verificationEmails = 0;
  int reauthentications = 0;
  int directDeletes = 0;
  final tokenRefreshes = <bool>[];
  ActionCodeSettings? lastActionSettings;
  Future<String?> Function()? pendingToken;
  Future<void> Function()? onReload;
  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    verificationEmails++;
    lastActionSettings = actionCodeSettings;
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    tokenRefreshes.add(forceRefresh);
    return pendingToken == null ? 'firebase-token-$uid' : await pendingToken!();
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    expect(credential.providerId, 'password');
    reauthentications++;
    return TestFirebaseCredential(this);
  }

  @override
  Future<void> reload() async {
    await onReload?.call();
  }

  @override
  Future<void> delete() async {
    directDeletes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestFirebaseAuth implements FirebaseAuth {
  TestFirebaseAuth(this.currentUser);
  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast(sync: true);
  int creates = 0;
  int signIns = 0;
  int resets = 0;
  int signOuts = 0;
  ActionCodeSettings? resetActionSettings;
  @override
  Stream<User?> userChanges() => changes.stream;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    changes.add(currentUser);
    return TestFirebaseCredential(currentUser);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signIns++;
    changes.add(currentUser);
    return TestFirebaseCredential(currentUser);
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    resets++;
    resetActionSettings = actionCodeSettings;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    currentUser = null;
    changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Firebase signup sends real SDK verification and keeps unverified state explicit',
    () async {
      final user = TestFirebaseUser(uid: 'firebase-a');
      final auth = TestFirebaseAuth(user);
      final client = RecallApiClient(
        endpoint: Uri.parse('https://recall.invalid/api'),
        identity: FirebaseRecallIdentity(auth),
      );
      final provider = FirebaseRecallAuthProvider(
        auth: auth,
        client: client,
        publicAppUrl: 'https://recall.invalid/',
      );
      await provider.signUp('sam@example.com', 'chosen-password');
      expect(auth.creates, 1);
      expect(user.verificationEmails, 1);
      expect(user.lastActionSettings!.url, 'https://recall.invalid/');
      expect(user.lastActionSettings!.handleCodeInApp, isFalse);
      expect(provider.currentAccount!.emailVerified, isFalse);
      await auth.changes.close();
    },
  );
  test(
    'password reset uses hosted Firebase email action rather than inventing a recovery session',
    () async {
      final auth = TestFirebaseAuth(null);
      final client = RecallApiClient(
        endpoint: Uri.parse('https://recall.invalid/api'),
        identity: FirebaseRecallIdentity(auth),
      );
      final provider = FirebaseRecallAuthProvider(
        auth: auth,
        client: client,
        publicAppUrl: 'https://recall.invalid/',
      );
      await provider.sendPasswordReset('sam@example.com');
      expect(auth.resets, 1);
      expect(auth.resetActionSettings!.handleCodeInApp, isFalse);
      expect(provider.currentAccount, isNull);
      await auth.changes.close();
    },
  );
  test(
    'verification refresh reloads the Firebase user and force refreshes its token claims',
    () async {
      final user = TestFirebaseUser(uid: 'firebase-a');
      user.onReload = () async {
        user.emailVerified = true;
      };
      final auth = TestFirebaseAuth(user);
      final client = RecallApiClient(
        endpoint: Uri.parse('https://recall.invalid/api'),
        identity: FirebaseRecallIdentity(auth),
      );
      final provider = FirebaseRecallAuthProvider(auth: auth, client: client);
      await provider.refreshAccount();
      expect(provider.currentAccount!.emailVerified, isTrue);
      expect(user.tokenRefreshes, [true]);
      await auth.changes.close();
    },
  );
  test(
    'Firebase identity binds token fetch to the captured user across account switches',
    () async {
      final token = Completer<String?>();
      final user = TestFirebaseUser(uid: 'firebase-a')
        ..pendingToken = () => token.future;
      final auth = TestFirebaseAuth(user);
      final pending = FirebaseRecallIdentity(auth).getIdToken();
      final rejected = expectLater(
        pending,
        throwsA(
          isA<CloudException>().having(
            (e) => e.code,
            'code',
            'account_changed',
          ),
        ),
      );
      auth.currentUser = TestFirebaseUser(uid: 'firebase-b');
      token.complete('token-for-a');
      await rejected;
      await auth.changes.close();
    },
  );
  test(
    'account deletion reauthenticates with SDK credentials and calls only authenticated server cleanup',
    () async {
      final user = TestFirebaseUser(uid: 'firebase-a', emailVerified: true);
      final auth = TestFirebaseAuth(user);
      final httpClient = MockClient((request) async {
        expect(request.url.path, '/api/account-delete');
        expect(
          request.headers['authorization'],
          'Bearer firebase-token-firebase-a',
        );
        expect(jsonDecode(request.body), isEmpty);
        return http.Response(
          '{"deleted":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(httpClient.close);
      final client = RecallApiClient(
        endpoint: Uri.parse('https://recall.invalid/api'),
        identity: FirebaseRecallIdentity(auth),
        httpClient: httpClient,
      );
      final provider = FirebaseRecallAuthProvider(auth: auth, client: client);
      final session = RecallSessionManager(provider: provider);
      expect(await session.deleteAccount(password: 'current-password'), isTrue);
      expect(user.reauthentications, 1);
      expect(auth.signIns, 0);
      expect(user.tokenRefreshes.first, isTrue);
      expect(user.directDeletes, 0);
      expect(session.deletedUserId, 'firebase-a');
      expect(session.isSignedIn, isFalse);
      session.dispose();
      await auth.changes.close();
    },
  );
  test(
    'confirmed deletion of A preserves a different account signed in during its server request',
    () async {
      final user = TestFirebaseUser(uid: 'firebase-a', emailVerified: true);
      final auth = TestFirebaseAuth(user);
      final httpClient = MockClient((request) async {
        expect(
          request.headers['authorization'],
          'Bearer firebase-token-firebase-a',
        );
        auth.currentUser = TestFirebaseUser(
          uid: 'firebase-b',
          emailVerified: true,
        );
        auth.changes.add(auth.currentUser);
        return http.Response(
          '{"deleted":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(httpClient.close);
      final client = RecallApiClient(
        endpoint: Uri.parse('https://recall.invalid/api'),
        identity: FirebaseRecallIdentity(auth),
        httpClient: httpClient,
      );
      final session = RecallSessionManager(
        provider: FirebaseRecallAuthProvider(auth: auth, client: client),
      );
      expect(await session.deleteAccount(password: 'current-password'), isTrue);
      expect(session.deletedUserId, 'firebase-a');
      expect(session.userId, 'firebase-b');
      expect(auth.signOuts, 0);
      session.dispose();
      await auth.changes.close();
    },
  );
}
