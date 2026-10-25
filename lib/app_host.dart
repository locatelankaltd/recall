import 'dart:async';
import 'package:flutter/material.dart';
import 'app.dart';
import 'app_services.dart';
import 'billing/firebase_billing_server.dart';
import 'cloud/recall_cloud.dart';
import 'cloud/public_review_page.dart';
import 'data/recall_controller.dart';
import 'l10n/strings.dart';
import 'platform/incoming_share_service.dart';
import 'platform/deadline_reminders.dart';
import 'platform/local_audio_index.dart';
import 'ui/account_page.dart';
import 'ui/update_editor.dart';

class RecallHost extends StatefulWidget {
  const RecallHost({
    super.key,
    required this.cloud,
    this.localController,
    this.shareService,
    this.reminderService,
  });
  final RecallCloud cloud;
  final RecallController? localController;
  final IncomingShareService? shareService;
  final DeadlineReminders? reminderService;
  @override
  State<RecallHost> createState() => _RecallHostState();
}

class _RecallHostState extends State<RecallHost> with WidgetsBindingObserver {
  late final RecallController _local;
  late final IncomingShareService _shares;
  late final DeadlineReminders _reminders;
  String? _syncedLocaleOwner;
  String? _cleanedDeletedOwner;
  RecallController? _remote;
  String? _remoteOwner;
  bool _useLocal = false;
  bool _sharing = false;
  bool _recoveryShown = false;
  bool _refreshing = false;
  final _planChecks = <String, DateTime>{};
  String? _promptedShare;
  String _mode = 'local';
  var _navigator = GlobalKey<NavigatorState>();
  Timer? _refreshTimer;
  RecallController get _active =>
      !_useLocal && _remote != null ? _remote! : _local;

  @override
  void initState() {
    super.initState();
    _local = widget.localController ?? RecallController();
    _shares = widget.shareService ?? IncomingShareService();
    _reminders = widget.reminderService ?? DeadlineReminders();
    _local.addListener(_workspaceChanged);
    unawaited(_reminders.initialize().then((_) => _workspaceChanged()));
    WidgetsBinding.instance.addObserver(this);
    unawaited(_local.initialize());
    widget.cloud.session.addListener(_accountChanged);
    _accountChanged(notify: false);
    _shares.pending.addListener(_shareChanged);
    unawaited(_shares.start());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refresh(),
    );
  }

  void _accountChanged({bool notify = true}) {
    final owner = widget.cloud.session.emailVerified
        ? widget.cloud.session.userId
        : null;
    final deletedOwner = widget.cloud.session.deletedUserId;
    if (deletedOwner != null && deletedOwner != _cleanedDeletedOwner) {
      _cleanedDeletedOwner = deletedOwner;
      final index = deletedOwner == _remoteOwner
          ? _remote?.audioIndex ?? LocalAudioIndex(userId: deletedOwner)
          : LocalAudioIndex(userId: deletedOwner);
      unawaited(_cleanupDeletedAudio(index));
    }
    if (owner != _remoteOwner) {
      _remote?.removeListener(_workspaceChanged);
      _remote?.dispose();
      _syncedLocaleOwner = null;
      _remote = owner == null || widget.cloud.projects == null
          ? null
          : RecallController(
              cloudGateway: widget.cloud.projects,
              audioIndex: LocalAudioIndex(userId: owner),
              initialLocale: _local.locale,
            );
      _remoteOwner = owner;
      _useLocal = false;
      if (_remote != null) {
        _remote!.addListener(_workspaceChanged);
        unawaited(_remote!.initialize());
      }
    }
    final nextMode = _active.isCloud ? 'account:$owner' : 'local';
    if (_mode != nextMode) {
      _mode = nextMode;
      unawaited(
        _reminders.syncFor(
          const [],
          workspaceKey: _mode,
          languageCode: _active.locale,
        ),
      );
      _navigator = GlobalKey<NavigatorState>();
    }
    if (notify && mounted) setState(() {});
    if (owner != null) unawaited(_refreshPlanIfNeeded());
    if (widget.cloud.session.passwordRecovery && !_recoveryShown) {
      _recoveryShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAccount());
    } else if (!widget.cloud.session.passwordRecovery) {
      _recoveryShown = false;
    }
  }

  void _workspaceChanged() {
    if (!mounted) return;
    if (_remote != null &&
        !_remote!.isLoading &&
        !_local.isLoading &&
        _syncedLocaleOwner != _remoteOwner) {
      _syncedLocaleOwner = _remoteOwner;
      unawaited(_remote!.setLocale(_local.locale).catchError((Object _) {}));
    }
    if (!_active.isLoading) {
      unawaited(
        _reminders.syncFor(
          _active.projects,
          workspaceKey: _mode,
          languageCode: _active.locale,
        ),
      );
    }
  }

  Future<void> _setLocale(String language) async {
    await _local.setLocale(language);
    if (_active != _local) await _active.setLocale(language);
  }

  Future<void> _cleanupDeletedAudio(LocalAudioIndex index) async {
    try {
      await index.clear(deleteRecordings: true);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _navigator.currentContext;
        if (!mounted || context == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Some local recordings could not be removed. Try again.',
              ),
            ),
            action: SnackBarAction(
              label: tr(context, 'retry'),
              onPressed: () => unawaited(_cleanupDeletedAudio(index)),
            ),
          ),
        );
      });
    }
  }

  void _selectWorkspace(bool local) {
    setState(() {
      _useLocal = local;
      _mode = _active.isCloud ? 'account:$_remoteOwner' : 'local';
      _navigator = GlobalKey<NavigatorState>();
    });
    _workspaceChanged();
  }

  void _openAccount() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(
          session: widget.cloud.session,
          onUseLocal: () => _selectWorkspace(true),
          onOpenWorkspace: () => _selectWorkspace(false),
        ),
      ),
    );
  }

  Future<void> _refreshPlanIfNeeded() async {
    final client = widget.cloud.client;
    final owner = widget.cloud.session.userId;
    if (client == null || owner == null) return;
    final now = DateTime.now();
    final checked = _planChecks[owner];
    if (checked != null && now.difference(checked) < const Duration(hours: 6)) {
      return;
    }
    _planChecks[owner] = now;
    try {
      final server = FirebaseBillingServer(client);
      final entitlement = await server.read();
      if (!mounted || widget.cloud.session.userId != owner) return;
      final verified = entitlement.verifiedAt;
      if (verified == null ||
          now.difference(verified) > const Duration(hours: 12)) {
        await server.refresh();
      }
    } catch (_) {
      // Quotas remain server-authoritative; availability never invents Pro.
      // Billing settings expose verification failures and an explicit retry.
    }
  }

  Future<void> _refresh() async {
    if (!mounted ||
        _refreshing ||
        !_active.isCloud ||
        _active.isLoading ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _refreshing = true;
    unawaited(_refreshPlanIfNeeded());
    try {
      await _active.refreshFromCloud();
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      _workspaceChanged();
    }
  }

  void _shareChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _showShare());
  }

  Future<void> _showShare({bool force = false}) async {
    final share = _shares.pending.value;
    final workspace = _active;
    final context = _navigator.currentContext;
    if (!mounted ||
        context == null ||
        share == null ||
        _sharing ||
        (!force && _promptedShare == share.id)) {
      return;
    }
    _sharing = true;
    _promptedShare = share.id;
    try {
      final text = share.text;
      final issueKey = switch (share.issue) {
        IncomingShareIssue.tooLarge => 'sharedTextTooLarge',
        IncomingShareIssue.unsupported => 'sharedTextUnsupported',
        IncomingShareIssue.empty => 'sharedTextEmpty',
        IncomingShareIssue.invalidPayload => 'sharedTextInvalid',
        IncomingShareIssue.queueFull => 'sharedTextQueueFull',
        null => text != null && text.length > 30000 ? 'sourceTooLong' : null,
      };
      if (issueKey != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr(ctx, 'sharedTextTitle')),
            content: Text(tr(ctx, issueKey)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr(ctx, 'close')),
              ),
            ],
          ),
        );
        _shares.clear();
        return;
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'sharedTextTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(ctx, 'sharedTextBody')),
                const SizedBox(height: 16),
                Text(
                  (text ?? '').length > 500
                      ? '${text!.substring(0, 500)}…'
                      : text ?? '',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(ctx, 'sharedTextDiscard')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(ctx, 'sharedTextReview')),
            ),
          ],
        ),
      );
      if (approved != true) {
        if (approved == false) _shares.clear();
        return;
      }
      if (!mounted || !context.mounted || _active != workspace) return;
      final eligible = workspace.projects
          .where((p) => p.items.isNotEmpty)
          .toList();
      if (eligible.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr(ctx, 'chooseProject')),
            content: Text(tr(ctx, 'noItems')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr(ctx, 'close')),
              ),
            ],
          ),
        );
        return; // Volatile text remains available from the shared-text action.
      }
      final project = eligible.length == 1
          ? eligible.first
          : await showModalBottomSheet<Project>(
              context: context,
              builder: (ctx) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: eligible
                      .map(
                        (p) => ListTile(
                          title: Text(p.title),
                          subtitle: Text(p.clientName),
                          onTap: () => Navigator.pop(ctx, p),
                        ),
                      )
                      .toList(),
                ),
              ),
            );
      if (project == null || !mounted || _active != workspace) return;
      final selected = _shares.take();
      if (selected?.text == null) return;
      await _navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => UpdateEditor(
            controller: workspace,
            projectId: project.id,
            initialSourceText: selected!.text,
          ),
        ),
      );
    } finally {
      _sharing = false;
      if (mounted &&
          _shares.pending.value != null &&
          _shares.pending.value!.id != _promptedShare) {
        _shareChanged();
      }
    }
  }

  String? get _reviewToken {
    try {
      final uri = Uri.base;
      final fragment = Uri.splitQueryString(uri.fragment);
      final value = fragment['review'] ?? uri.queryParameters['review'];
      return value != null && value.length <= 256 ? value : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = _reviewToken;
    final home = token == null
        ? null
        : widget.cloud.reviews == null
        ? const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This review service is unavailable. Ask the sender for a new link.',
                ),
              ),
            ),
          )
        : PublicReviewPage(gateway: widget.cloud.reviews!, token: token);
    return RecallServices(
      cloud: widget.cloud,
      openAccount: _openAccount,
      openSharedText: () => _showShare(force: true),
      hasSharedText: _shares.pending.value != null,
      reminders: _reminders,
      setLocale: _setLocale,
      child: RecallApp(
        key: ValueKey(_mode),
        controller: _active,
        navigatorKey: _navigator,
        home: home,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.cloud.session.removeListener(_accountChanged);
    _refreshTimer?.cancel();
    _shares.pending.removeListener(_shareChanged);
    _shares.dispose();
    _local.removeListener(_workspaceChanged);
    _remote?.removeListener(_workspaceChanged);
    _reminders.dispose();
    _local.dispose();
    _remote?.dispose();
    super.dispose();
  }
}
