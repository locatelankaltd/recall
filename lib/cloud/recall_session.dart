import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cloud_gateway.dart';

class RecallAccount {
  const RecallAccount({
    required this.id,
    required this.email,
    required this.emailVerified,
  });
  final String id;
  final String email;
  final bool emailVerified;
}

class RecallAuthEvent {
  const RecallAuthEvent(this.account, {this.passwordRecovery = false});
  final RecallAccount? account;
  final bool passwordRecovery;
}

/// Auth boundary can be tested without creating accounts or sending emails.
abstract class RecallAuthProvider {
  RecallAccount? get currentAccount;
  Stream<RecallAuthEvent> get changes;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String password);
  Future<void> resendVerification(String email);
  Future<void> refreshAccount();
  Future<void> deleteAccount();
}

class RecallSessionManager extends ChangeNotifier {
  RecallSessionManager({RecallAuthProvider? provider, this.configurationError})
    : _provider = provider {
    _account = provider?.currentAccount;
    _subscription = provider?.changes.listen(
      (event) {
        _account = event.account?.id == deletedUserId ? null : event.account;
        if (event.passwordRecovery) passwordRecovery = true;
        if (event.account == null) passwordRecovery = false;
        _notify();
      },
      onError: (Object _) {
        error = 'Your session could not be refreshed. Sign in again.';
        _notify();
      },
    );
  }
  final RecallAuthProvider? _provider;
  final String? configurationError;
  StreamSubscription<RecallAuthEvent>? _subscription;
  RecallAccount? _account;
  String? _verificationEmail;
  bool _disposed = false;
  bool busy = false;
  bool passwordRecovery = false;
  String? error;
  String? notice;

  /// Emitted only after the server confirms account deletion, never on sign out.
  String? deletedUserId;
  bool get configured => _provider != null;
  bool get isSignedIn => _account != null;
  String? get userId => _account?.id;
  String? get email => _account?.email ?? _verificationEmail;
  bool get emailVerified => _account?.emailVerified ?? false;
  bool get awaitingVerification => _verificationEmail != null && !emailVerified;

  Future<bool> _run(Future<void> Function(RecallAuthProvider) action) async {
    if (busy) return false;
    final provider = _provider;
    if (provider == null) {
      error =
          configurationError ??
          'Cloud accounts are not configured in this build.';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    notice = null;
    _notify();
    try {
      await action(provider);
      final account = provider.currentAccount;
      _account = account?.id == deletedUserId ? null : account;
      return true;
    } catch (problem) {
      error = problem is CloudException
          ? problem.message
          : 'This account request could not be completed. Check your connection and try again.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> signIn({required String email, required String password}) =>
      _run((provider) async {
        await provider.signIn(email.trim(), password);
        _verificationEmail = null;
        passwordRecovery = false;
      });

  Future<bool> signUp({
    required String email,
    required String password,
  }) => _run((provider) async {
    await provider.signUp(email.trim(), password);
    _verificationEmail = email.trim();
    notice = provider.currentAccount?.emailVerified == true
        ? 'Your account is ready.'
        : 'Check your email for the verification link, then return here and sign in. If the address is already registered, use sign in or reset your password.';
  });

  Future<bool> signOut() => _run((provider) async {
    await provider.signOut();
    _verificationEmail = null;
    passwordRecovery = false;
  });

  Future<bool> sendPasswordReset(String email) => _run((provider) async {
    if (email.trim().isEmpty) {
      throw const CloudException('Enter your email address first.');
    }
    await provider.sendPasswordReset(email.trim());
    notice =
        'If this email has an account, a password reset link will arrive shortly. Open it on this device.';
  });

  Future<bool> resendVerification() => _run((provider) async {
    final address = email;
    if (address == null) {
      throw const CloudException('Enter your account email first.');
    }
    await provider.resendVerification(address);
    notice = 'If verification is needed, a new link will arrive by email.';
  });

  Future<bool> refreshAccount() => _run((provider) async {
    await provider.refreshAccount();
    if (provider.currentAccount?.emailVerified == true) {
      _verificationEmail = null;
    }
  });

  Future<bool> updatePassword(String password) => _run((provider) async {
    if (password.length < 8) {
      throw const CloudException('Use a password with at least 8 characters.');
    }
    await provider.updatePassword(password);
    passwordRecovery = false;
    notice = 'Your password has been updated.';
  });

  /// The password is checked with Supabase before account deletion is requested.
  Future<bool> deleteAccount({required String password}) => _run((
    provider,
  ) async {
    final before = _account;
    if (before == null || password.isEmpty) {
      throw const CloudException(
        'Enter your current password to delete this account.',
      );
    }
    await provider.signIn(before.email, password);
    if (provider.currentAccount?.id != before.id) {
      throw const CloudException(
        'The account changed. Sign in again before deleting.',
      );
    }
    await provider.deleteAccount();
    deletedUserId = before.id;
    final sameAccount = provider.currentAccount?.id == before.id;
    _account = sameAccount ? null : provider.currentAccount;
    _notify();
    if (sameAccount) {
      try {
        await provider.signOut();
      } catch (_) {
        // A failed logout cannot undo confirmed server deletion. A different
        // account that signed in during deletion must keep its own session.
      }
    }
    _verificationEmail = null;
    passwordRecovery = false;
    notice = 'Your account and cloud projects have been deleted.';
  });

  void clearMessage() {
    error = null;
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
