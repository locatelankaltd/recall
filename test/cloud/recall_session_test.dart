import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/cloud_gateway.dart';
import 'package:recall_next/cloud/recall_session.dart';

class FakeAuth implements RecallAuthProvider {
  RecallAccount? account;
  final events = StreamController<RecallAuthEvent>.broadcast(sync: true);
  final actions = <String>[];
  bool failSignIn = false;
  bool failSignOut = false;
  @override
  RecallAccount? get currentAccount => account;
  @override
  Stream<RecallAuthEvent> get changes => events.stream;
  void emit(RecallAccount? user, {bool recovery = false}) {
    account = user;
    events.add(RecallAuthEvent(user, passwordRecovery: recovery));
  }

  @override
  Future<void> signIn(String email, String password) async {
    actions.add('signIn');
    if (failSignIn) throw const CloudException('Incorrect password');
    emit(RecallAccount(id: 'account-a', email: email, emailVerified: true));
  }

  @override
  Future<void> signUp(String email, String password) async {
    actions.add('signUp');
  }

  @override
  Future<void> signOut() async {
    actions.add('signOut');
    emit(null);
    if (failSignOut) throw const CloudException('Logout failed');
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    actions.add('reset');
  }

  @override
  Future<void> updatePassword(String password) async {
    actions.add('updatePassword');
  }

  @override
  Future<void> resendVerification(String email) async {
    actions.add('verify');
  }

  @override
  Future<void> refreshAccount() async {
    actions.add('refresh');
  }

  @override
  Future<void> reauthenticate(String password) async {
    actions.add('reauthenticate');
    if (failSignIn) throw const CloudException('Incorrect password');
  }

  @override
  Future<void> deleteAccount() async {
    actions.add('delete');
  }
}

void main() {
  const account = RecallAccount(
    id: 'account-a',
    email: 'sam@example.com',
    emailVerified: true,
  );
  test(
    'unconfigured builds expose failure rather than fake account success',
    () async {
      final session = RecallSessionManager();
      expect(
        await session.signIn(email: 'sam@example.com', password: 'password'),
        isFalse,
      );
      expect(session.configured, isFalse);
      expect(session.userId, isNull);
      expect(session.error, contains('not configured'));
      session.dispose();
    },
  );
  test(
    'sign up without session explicitly waits for email verification',
    () async {
      final auth = FakeAuth();
      final session = RecallSessionManager(provider: auth);
      expect(
        await session.signUp(email: ' sam@example.com ', password: 'password'),
        isTrue,
      );
      expect(session.isSignedIn, isFalse);
      expect(session.awaitingVerification, isTrue);
      expect(session.email, 'sam@example.com');
      expect(session.notice, contains('verification'));
      session.dispose();
      await auth.events.close();
    },
  );
  test(
    'password recovery is only activated by auth event and clears after update',
    () async {
      final auth = FakeAuth();
      final session = RecallSessionManager(provider: auth);
      await session.sendPasswordReset('sam@example.com');
      expect(session.passwordRecovery, isFalse);
      auth.emit(account, recovery: true);
      expect(session.passwordRecovery, isTrue);
      expect(await session.updatePassword('new-password'), isTrue);
      expect(session.passwordRecovery, isFalse);
      expect(auth.actions, ['reset', 'updatePassword']);
      session.dispose();
      await auth.events.close();
    },
  );
  test(
    'account deletion reauthenticates and never invokes delete for bad password',
    () async {
      final auth = FakeAuth()..account = account;
      final session = RecallSessionManager(provider: auth);
      auth.failSignIn = true;
      expect(await session.deleteAccount(password: 'wrong'), isFalse);
      expect(auth.actions, ['reauthenticate']);
      expect(session.deletedUserId, isNull);
      expect(session.isSignedIn, isTrue);
      auth.failSignIn = false;
      expect(await session.deleteAccount(password: 'correct'), isTrue);
      expect(auth.actions, [
        'reauthenticate',
        'reauthenticate',
        'delete',
        'signOut',
      ]);
      expect(session.isSignedIn, isFalse);
      expect(session.deletedUserId, 'account-a');
      session.dispose();
      await auth.events.close();
    },
  );
  test('sign out immediately clears account identity from listeners', () async {
    final auth = FakeAuth()..account = account;
    final session = RecallSessionManager(provider: auth);
    final observed = <String?>[];
    session.addListener(() => observed.add(session.userId));
    await session.signOut();
    expect(observed.last, isNull);
    expect(session.email, isNull);
    expect(session.deletedUserId, isNull);
    session.dispose();
    await auth.events.close();
  });
  test(
    'confirmed deletion stays successful if the logout request fails',
    () async {
      final auth = FakeAuth()
        ..account = account
        ..failSignOut = true;
      final session = RecallSessionManager(provider: auth);
      expect(await session.deleteAccount(password: 'current-password'), isTrue);
      expect(session.isSignedIn, isFalse);
      expect(session.deletedUserId, 'account-a');
      expect(session.notice, contains('have been deleted'));
      expect(session.error, isNull);
      session.dispose();
      await auth.events.close();
    },
  );
}
