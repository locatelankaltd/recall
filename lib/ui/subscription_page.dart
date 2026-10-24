import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/billing_service.dart';
import '../billing/revenuecat_store.dart';
import '../billing/supabase_billing_server.dart';
import '../design/design.dart';
import '../l10n/strings.dart';
import 'widgets.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, this.client, this.controller});
  final SupabaseClient? client;

  /// Dependency injection for tests. Production uses native stores and Supabase.
  final BillingController? controller;
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with WidgetsBindingObserver {
  late final BillingController _billing;
  StreamSubscription<AuthState>? _auth;
  String? _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _billing =
        widget.controller ??
        BillingController(
          store: RevenueCatStore(),
          server: SupabaseBillingServer(widget.client),
          currentUserId: () => widget.client?.auth.currentUser?.id,
        );
    _owner = widget.client?.auth.currentUser?.id;
    if (widget.client != null) {
      RevenueCatStore.observeSession(widget.client!);
      _auth = widget.client!.auth.onAuthStateChange.listen((state) {
        final owner = state.session?.user.id;
        if (owner == _owner) return;
        _owner = owner;
        _billing.sessionChanged();
      });
    }
    unawaited(_billing.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_billing.busy &&
        !_billing.accountChanged &&
        _billing.signedIn) {
      unawaited(_billing.verify());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth?.cancel());
    if (widget.controller == null) _billing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _billing,
    builder: (context, _) {
      final entitlement = _billing.entitlement;
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'subscription'))),
        body: PageBody(
          children: [
            const SizedBox(height: 16),
            const RecallBrand(size: 42),
            const SizedBox(height: 24),
            Text('Recall', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 12),
            Text(tr(context, 'subscriptionBody')),
            const SizedBox(height: 14),
            Text(tr(context, 'subscriptionFreeLimits')),
            const SizedBox(height: 6),
            Text(tr(context, 'subscriptionProLimits')),
            const SizedBox(height: 8),
            Text(
              tr(context, 'subscriptionAllowanceNote'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 22),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StateLabel(
                tr(
                  context,
                  entitlement.active
                      ? 'subscriptionActive'
                      : entitlement.status == 'stale'
                      ? 'subscriptionStale'
                      : entitlement.status == 'unverified'
                      ? 'subscriptionUnverified'
                      : 'subscriptionInactive',
                ),
                pending: !entitlement.active,
              ),
            ),
            if (_billing.messageKey != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Notice(
                  tr(context, _billing.messageKey!),
                  glyph: RecallGlyph.person,
                ),
              ),
            ],
            if (_billing.busy) ...[
              const SizedBox(height: 22),
              const LinearProgressIndicator(),
            ],
            if (_billing.signedIn && !_billing.accountChanged) ...[
              const SizedBox(height: 22),
              for (final plan in _billing.plans) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (plan.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(plan.description),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          plan.price,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_period(context, plan.period) != null)
                          Text(
                            _period(context, plan.period)!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _billing.canPurchase
                              ? () => _billing.purchase(plan)
                              : null,
                          child: Text(tr(context, 'subscriptionBuy')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_billing.plans.isNotEmpty)
                Text(tr(context, 'subscriptionRenewal')),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: _billing.busy ? null : _billing.verify,
                icon: const RecallIcon(RecallGlyph.check, size: 19),
                label: Text(tr(context, 'subscriptionRefresh')),
              ),
              if (_billing.storeAvailable) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _billing.busy ? null : _billing.restore,
                  icon: const RecallIcon(RecallGlyph.history, size: 19),
                  label: Text(tr(context, 'subscriptionRestore')),
                ),
              ],
              if (_billing.managementUrl != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _billing.busy
                      ? null
                      : () async {
                          final uri = _billing.managementUrl;
                          if (uri == null) return;
                          try {
                            if (!await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            )) {
                              throw const BillingFailure('subscriptionError');
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    tr(context, 'subscriptionError'),
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Text(tr(context, 'subscriptionManage')),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}

String? _period(BuildContext context, String? period) {
  final match = RegExp(r'^P([1-9][0-9]*)([DWMY])$').firstMatch(period ?? '');
  if (match == null) return null;
  final key = switch (match.group(2)) {
    'D' => 'subscriptionPeriodDays',
    'W' => 'subscriptionPeriodWeeks',
    'M' => 'subscriptionPeriodMonths',
    'Y' => 'subscriptionPeriodYears',
    _ => throw StateError('Invalid subscription period'),
  };
  return trParams(context, key, {'count': match.group(1)!});
}
