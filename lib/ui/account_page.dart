import 'package:flutter/material.dart';

import '../l10n/strings.dart';

import '../cloud/recall_session.dart';
import '../design/recall_icon.dart';
import '../design/recall_theme.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.session,
    this.onOpenWorkspace,
    this.onUseLocal,
  });
  final RecallSessionManager session;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onUseLocal;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _showPassword = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final session = widget.session;
    if (session.passwordRecovery) {
      await session.updatePassword(_password.text);
    } else if (_create) {
      await session.signUp(email: _email.text, password: _password.text);
    } else {
      await session.signIn(email: _email.text, password: _password.text);
    }
    _password.clear();
  }

  Future<void> _delete() async {
    final password = TextEditingController();
    final approved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'accountDeleteTitle')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'accountDeleteBody')),
              const SizedBox(height: 20),
              TextField(
                controller: password,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'accountCurrentPassword'),
                ),
                enableSuggestions: false,
                autocorrect: false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'accountKeep')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, password.text),
            child: Text(tr(context, 'accountDeletePermanently')),
          ),
        ],
      ),
    );
    password.dispose();
    if (approved != null && approved.isNotEmpty) {
      await widget.session.deleteAccount(password: approved);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final palette = RecallPalette.of(context);
      final signedIn = session.isSignedIn && !session.passwordRecovery;
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'accountTitle'))),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: palette.panel,
                            border: Border.all(color: palette.line),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: RecallIcon(
                            RecallGlyph.person,
                            size: 32,
                            color: palette.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        session.passwordRecovery
                            ? tr(context, 'accountNewPasswordHeading')
                            : signedIn
                            ? tr(context, 'accountSharedHeading')
                            : tr(context, 'accountWelcomeHeading'),
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        signedIn
                            ? tr(context, 'accountSignedInBody')
                            : tr(context, 'accountSignInBody'),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      if (!session.configured) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context, 'accountUnavailable'),
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  session.configurationError != null
                                      ? tr(context, session.configurationError!)
                                      : tr(context, 'accountNotConfigured'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (signedIn) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.email ?? '',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  session.emailVerified
                                      ? tr(context, 'accountEmailVerified')
                                      : tr(context, 'accountEmailUnverified'),
                                  style: TextStyle(
                                    color: session.emailVerified
                                        ? palette.confirmed
                                        : palette.pending,
                                  ),
                                ),
                                if (!session.emailVerified) ...[
                                  const SizedBox(height: 12),
                                  Text(tr(context, 'accountCheckInbox')),
                                  TextButton(
                                    onPressed: session.busy
                                        ? null
                                        : session.resendVerification,
                                    child: Text(
                                      tr(context, 'accountResendVerification'),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: session.busy
                                        ? null
                                        : session.refreshAccount,
                                    child: Text(
                                      tr(context, 'accountVerifiedAction'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (session.emailVerified &&
                            widget.onOpenWorkspace != null)
                          FilledButton.icon(
                            onPressed: session.busy
                                ? null
                                : widget.onOpenWorkspace,
                            icon: const RecallIcon(RecallGlyph.projects),
                            label: Text(tr(context, 'accountOpenWorkspace')),
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: session.busy
                              ? null
                              : () => session.sendPasswordReset(
                                  session.email ?? '',
                                ),
                          child: Text(tr(context, 'accountSendReset')),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: session.busy ? null : session.signOut,
                          child: Text(tr(context, 'accountSignOut')),
                        ),
                      ] else ...[
                        Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!session.passwordRecovery) ...[
                                TextFormField(
                                  controller: _email,
                                  decoration: InputDecoration(
                                    labelText: tr(context, 'accountEmail'),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  validator: (value) =>
                                      value == null ||
                                          !RegExp(
                                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                          ).hasMatch(value.trim())
                                      ? tr(context, 'accountInvalidEmail')
                                      : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _password,
                                decoration: InputDecoration(
                                  labelText: session.passwordRecovery
                                      ? tr(context, 'accountNewPassword')
                                      : tr(context, 'accountPassword'),
                                  suffixIcon: IconButton(
                                    tooltip: _showPassword
                                        ? tr(context, 'accountHidePassword')
                                        : tr(context, 'accountShowPassword'),
                                    onPressed: () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                obscureText: !_showPassword,
                                enableSuggestions: false,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                autofillHints: [
                                  session.passwordRecovery || _create
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                onFieldSubmitted: (_) => _submit(),
                                validator: (value) =>
                                    value == null || value.isEmpty
                                    ? tr(context, 'accountPasswordRequired')
                                    : (_create || session.passwordRecovery) &&
                                          value.length < 8
                                    ? tr(context, 'accountPasswordLength')
                                    : null,
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: session.busy ? null : _submit,
                                child: Text(
                                  session.passwordRecovery
                                      ? tr(context, 'accountUpdatePassword')
                                      : _create
                                      ? tr(context, 'accountCreate')
                                      : tr(context, 'accountSignIn'),
                                ),
                              ),
                              if (!session.passwordRecovery) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: session.busy
                                      ? null
                                      : () {
                                          setState(() => _create = !_create);
                                          _password.clear();
                                          session.clearMessage();
                                        },
                                  child: Text(
                                    _create
                                        ? tr(context, 'accountHaveAccount')
                                        : tr(context, 'accountCreatePrompt'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: session.busy
                                      ? null
                                      : () => session.sendPasswordReset(
                                          _email.text,
                                        ),
                                  child: Text(
                                    tr(context, 'accountForgotPassword'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (session.awaitingVerification) ...[
                          const SizedBox(height: 16),
                          Text(
                            trParams(context, 'accountVerificationPending', {
                              'email': session.email ?? '',
                            }),
                          ),
                          TextButton(
                            onPressed: session.busy
                                ? null
                                : session.resendVerification,
                            child: Text(
                              tr(context, 'accountResendVerification'),
                            ),
                          ),
                        ],
                      ],
                      if (session.busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: LinearProgressIndicator(),
                        ),
                      if (session.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              tr(context, session.error!),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                      if (session.notice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              tr(context, session.notice!),
                              style: TextStyle(color: palette.accent),
                            ),
                          ),
                        ),
                      if (widget.onUseLocal != null) ...[
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: session.busy ? null : widget.onUseLocal,
                          child: Text(tr(context, 'accountUseDevice')),
                        ),
                      ],
                      if (signedIn) ...[
                        const SizedBox(height: 36),
                        const Divider(),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: session.busy ? null : _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          child: Text(tr(context, 'accountDeleteAction')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
