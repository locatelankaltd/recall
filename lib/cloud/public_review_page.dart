import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'package:intl/intl.dart';

import '../design/recall_icon.dart';
import '../design/recall_theme.dart';
import '../domain/recall_models.dart';
import 'cloud_gateway.dart';

/// Public bearer review: a receipt identifies a link holder, not a verified
/// person. The server, rather than the browser, decides if it is still current.
class PublicReviewPage extends StatefulWidget {
  const PublicReviewPage({
    super.key,
    required this.gateway,
    required this.token,
  });
  final CloudReviewGateway gateway;
  final String token;
  @override
  State<PublicReviewPage> createState() => _PublicReviewPageState();
}

class _PublicReviewPageState extends State<PublicReviewPage> {
  Locale _reviewLocale = const Locale('en');
  PublicReview? _review;
  ReviewReceipt? _receipt;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  bool _acknowledged = false;
  final _note = TextEditingController();
  @override
  void initState() {
    super.initState();
    final language =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _reviewLocale = Locale(
      ['en', 'es', 'fr'].contains(language) ? language : 'en',
    );
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _acknowledged = false;
    });
    try {
      final review = await widget.gateway.fetchReview(widget.token);
      if (mounted) setState(() => _review = review);
    } catch (problem) {
      if (mounted) {
        setState(
          () => _error = problem is CloudException
              ? problem.message
              : 'publicReviewLoadFailed',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(String action) async {
    if (_sending || !_acknowledged) return;
    if (action == 'correction' && _note.text.trim().isEmpty) {
      setState(() => _error = 'publicReviewCorrectionRequired');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final receipt = await widget.gateway.respond(
        token: widget.token,
        action: action,
        note: _note.text,
      );
      if (mounted) setState(() => _receipt = receipt);
    } catch (problem) {
      if (mounted) {
        setState(
          () => _error = problem is CloudException
              ? problem.message
              : 'publicReviewResponseFailed',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    locale: _reviewLocale,
    child: Builder(builder: _buildPage),
  );

  Widget _buildPage(BuildContext context) {
    final palette = RecallPalette.of(context);
    final review = _review;
    final receipt = _receipt;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'publicReviewTitle')),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr(context, 'language'),
            icon: const RecallIcon(RecallGlyph.language),
            onSelected: (language) => setState(() {
              _reviewLocale = Locale(language);
              _acknowledged = false;
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'es', child: Text('Español')),
              PopupMenuItem(value: 'fr', child: Text('Français')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(tr(context, 'publicReviewLoading')),
                  ] else if (review == null) ...[
                    Text(
                      tr(context, 'publicReviewUnavailable'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(tr(context, _error ?? 'publicReviewUnavailableBody')),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(tr(context, 'retry')),
                    ),
                  ] else ...[
                    Text(
                      review.projectTitle,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      trParams(context, 'publicReviewFor', {
                        'name': review.participantName,
                      }),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RecallIcon(
                              RecallGlyph.person,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tr(context, 'publicReviewIdentityNote'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      tr(context, 'publicReviewChanges'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(tr(context, 'publicReviewCompare')),
                    const SizedBox(height: 20),
                    for (final change in review.changes) ...[
                      _ChangeCard(change: change),
                      const SizedBox(height: 16),
                    ],
                    if (review.changes.isEmpty)
                      Text(tr(context, 'publicReviewNoChanges')),
                    const SizedBox(height: 12),
                    Text(
                      tr(context, 'publicReviewSourceHeading'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (review.evidence.isEmpty)
                      Text(tr(context, 'publicReviewNoSource')),
                    for (final source in review.evidence) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                source.kind == 'originalText'
                                    ? trParams(
                                        context,
                                        'publicReviewOriginal',
                                        {'language': source.language},
                                      )
                                    : trParams(
                                        context,
                                        'publicReviewRecollection',
                                        {'language': source.language},
                                      ),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 12),
                              SelectableText(source.text),
                              const SizedBox(height: 12),
                              Text(
                                source.kind == 'originalText'
                                    ? tr(context, 'publicReviewOriginalNote')
                                    : tr(
                                        context,
                                        'publicReviewRecollectionNote',
                                      ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (review.evidenceOmitted)
                      Text(tr(context, 'publicReviewSourceOmitted')),
                    const SizedBox(height: 28),
                    if (receipt != null) ...[
                      _ResponseNotice(
                        action: receipt.action,
                        receipt: receipt.receiptId,
                      ),
                    ] else if (review.response != null) ...[
                      _ResponseNotice(
                        action:
                            review.response!['action'] as String? ?? 'recorded',
                        receipt: review.response!['receiptId'] as String?,
                      ),
                    ] else if (!review.canRespond) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                review.status == 'stale'
                                    ? tr(context, 'publicReviewStale')
                                    : tr(context, 'publicReviewClosed'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(tr(context, 'publicReviewClosedBody')),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        tr(context, 'publicReviewResponse'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(tr(context, 'publicReviewResponseNote')),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _note,
                        maxLines: 4,
                        maxLength: 2000,
                        enabled: !_sending,
                        decoration: InputDecoration(
                          labelText: tr(context, 'publicReviewNote'),
                          hintText: tr(context, 'publicReviewNoteHint'),
                        ),
                      ),
                      CheckboxListTile(
                        value: _acknowledged,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _sending
                            ? null
                            : (value) => setState(
                                () => _acknowledged = value ?? false,
                              ),
                        title: Text(tr(context, 'publicReviewAcknowledgement')),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: !_acknowledged || _sending
                            ? null
                            : () => _respond('confirm'),
                        icon: const RecallIcon(RecallGlyph.check),
                        label: Text(tr(context, 'publicReviewConfirm')),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: !_acknowledged || _sending
                            ? null
                            : () => _respond('correction'),
                        child: Text(tr(context, 'correct')),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: !_acknowledged || _sending
                            ? null
                            : () => _respond('decline'),
                        child: Text(tr(context, 'publicReviewDecline')),
                      ),
                      if (_sending)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            tr(context, _error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _sending ? null : _load,
                      child: Text(tr(context, 'publicReviewRefresh')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponseNotice extends StatelessWidget {
  const _ResponseNotice({required this.action, this.receipt});
  final String action;
  final String? receipt;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switch (action) {
              'confirm' => tr(context, 'publicReviewConfirmed'),
              'correction' => tr(context, 'publicReviewCorrectionRecorded'),
              'decline' => tr(context, 'publicReviewDeclined'),
              _ => tr(context, 'publicReviewAlreadyAnswered'),
            }, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(tr(context, 'publicReviewReceiptNote')),
            if (receipt != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                trParams(context, 'publicReviewReceipt', {'receipt': receipt!}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.change});
  final ReviewChange change;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previous = _ItemSnapshot(
            label: tr(context, 'currentPlan'),
            item: change.previous,
          );
          final proposed = _ItemSnapshot(
            label: tr(context, 'publicReviewProposedVersion'),
            item: change.proposed,
          );
          return constraints.maxWidth >= 550
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: previous),
                    const SizedBox(width: 28),
                    Expanded(child: proposed),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    previous,
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(),
                    ),
                    proposed,
                  ],
                );
        },
      ),
    ),
  );
}

class _ItemSnapshot extends StatelessWidget {
  const _ItemSnapshot({required this.label, this.item});
  final String label;
  final PlanItem? item;
  @override
  Widget build(BuildContext context) {
    final value = item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 10),
        if (value == null)
          Text(tr(context, 'publicReviewNoItem'))
        else ...[
          Text(value.title, style: Theme.of(context).textTheme.titleMedium),
          if (value.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(value.details),
          ],
          const SizedBox(height: 12),
          Text(
            value.dueDate == null
                ? tr(context, 'noDate')
                : trParams(context, 'publicReviewDue', {
                    'date': DateFormat.yMMMd(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(value.dueDate!),
                  }),
          ),
          Text(
            value.amountMinor == null
                ? tr(context, 'noAmount')
                : '${value.currency} ${(value.amountMinor! / 100).toStringAsFixed(2)}',
          ),
          Text(
            '${tr(context, 'owner')}: ${value.ownerId == 'you' ? tr(context, 'publicReviewProjectOwner') : tr(context, 'publicReviewReviewer')}',
          ),
        ],
      ],
    );
  }
}
