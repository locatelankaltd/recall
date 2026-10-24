import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../design/recall_icon.dart';
import '../domain/recall_models.dart';
import '../l10n/strings.dart';
import 'cloud_gateway.dart';

Future<void> showReviewSharing(
  BuildContext context, {
  required CloudReviewGateway gateway,
  required Project project,
  required PlanRevision revision,
  Uri? applicationUrl,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ReviewShareSheet(
    gateway: gateway,
    project: project,
    revision: revision,
    applicationUrl: applicationUrl,
  ),
);

class _ReviewShareSheet extends StatefulWidget {
  const _ReviewShareSheet({
    required this.gateway,
    required this.project,
    required this.revision,
    this.applicationUrl,
  });
  final CloudReviewGateway gateway;
  final Project project;
  final PlanRevision revision;
  final Uri? applicationUrl;
  @override
  State<_ReviewShareSheet> createState() => _ReviewShareSheetState();
}

class _ReviewShareSheetState extends State<_ReviewShareSheet> {
  List<ReviewLink> _links = [];
  ReviewLink? _created;
  String? _error;
  bool _busy = true;
  late final List<String> _changed;
  late final Set<String> _selected;
  int _ttl = 86400;
  Uri? get _applicationUrl {
    final explicit = widget.applicationUrl;
    if (explicit != null) return explicit;
    if (kIsWeb) return Uri.base.replace(query: '', fragment: '');
    const configured = String.fromEnvironment('PUBLIC_APP_URL');
    final uri = Uri.tryParse(configured);
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') return null;
    return uri.replace(query: '', fragment: '');
  }

  @override
  void initState() {
    super.initState();
    final before = {
      for (final item in widget.project.currentRevision.items) item.id: item,
    };
    final after = {for (final item in widget.revision.items) item.id: item};
    _changed = {...before.keys, ...after.keys}
        .where(
          (id) =>
              jsonEncode(before[id]?.toJson()) !=
              jsonEncode(after[id]?.toJson()),
        )
        .toList();
    _selected = _changed.toSet();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final links = await widget.gateway.listLinks(widget.project.id);
      if (mounted) {
        setState(
          () => _links = links
              .where((l) => l.revisionId == widget.revision.id)
              .toList(),
        );
      }
    } catch (problem) {
      if (mounted) {
        setState(
          () => _error = problem is CloudException
              ? problem.message
              : 'Review links could not be loaded. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (_applicationUrl == null || _selected.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await widget.gateway.createLink(
        projectId: widget.project.id,
        revisionId: widget.revision.id,
        participantId: 'client',
        itemIds: _selected.toList(),
        ttlSeconds: _ttl,
      );
      if (mounted) {
        setState(() {
          _created = link;
          _links = [link, ..._links];
        });
      }
    } catch (problem) {
      if (mounted) {
        setState(
          () => _error = problem is CloudException
              ? problem.message
              : 'The review link could not be created. Refresh the list before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(ReviewLink link) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.gateway.revokeLink(link.id);
      if (!mounted) return;
      if (_created?.id == link.id) setState(() => _created = null);
      await _refresh();
    } catch (problem) {
      if (mounted) {
        setState(
          () => _error = problem is CloudException
              ? problem.message
              : 'This link could not be revoked. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _url {
    final base = _applicationUrl;
    return _created == null || base == null
        ? null
        : _created!.urlFor(base).toString();
  }

  Future<void> _copy() async {
    final url = _url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Review link copied.'))),
      );
    }
  }

  Future<void> _share() async {
    final url = _url;
    if (url == null) return;
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: url,
          subject: widget.project.title,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Sharing could not open. Copy the link instead.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final revision = widget.revision;
    final canCreate =
        revision.status == RevisionStatus.proposed &&
        revision.baseRevisionId == widget.project.currentRevision.id &&
        !widget.project.isDemo;
    final url = _url;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, 'Share a review link'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                context,
                'Anyone with a link can respond. The receipt records a link holder, not a verified person. Copying or sharing a link does not mean it was delivered.',
              ),
            ),
            const SizedBox(height: 20),
            if (!canCreate)
              Text(
                tr(
                  context,
                  'This proposal is closed, out of date, or an example. A new link cannot be created.',
                ),
              )
            else ...[
              if (_applicationUrl == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    tr(
                      context,
                      'A public web address is needed before links can be shared from this build.',
                    ),
                  ),
                ),
              Text(
                tr(context, 'Items this reviewer can see'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final id in _changed)
                CheckboxListTile(
                  value: _selected.contains(id),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    [
                      ...revision.items,
                      ...widget.project.currentRevision.items,
                    ].where((i) => i.id == id).first.title,
                  ),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
                ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Source text is included when every changed item is selected. Partial reviews omit source text outside their scope.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _ttl,
                decoration: InputDecoration(
                  labelText: tr(context, 'Link expires after'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 3600,
                    child: Text(tr(context, '1 hour')),
                  ),
                  DropdownMenuItem(
                    value: 86400,
                    child: Text(tr(context, '1 day')),
                  ),
                  DropdownMenuItem(
                    value: 604800,
                    child: Text(tr(context, '7 days')),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _ttl = value ?? 86400),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || _applicationUrl == null || _selected.isEmpty
                    ? null
                    : _create,
                icon: const RecallIcon(RecallGlyph.send),
                label: Text(tr(context, 'Create private review link')),
              ),
            ],
            if (url != null) ...[
              const SizedBox(height: 24),
              SelectableText(url),
              const SizedBox(height: 8),
              Text(
                '${tr(context, 'Expires')}: ${DateFormat.yMMMd(Localizations.localeOf(context).languageCode).add_jm().format(_created!.expires.toLocal())}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _copy,
                    child: Text(tr(context, 'Copy link')),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _share,
                    child: Text(tr(context, 'Share link')),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            Text(
              tr(context, 'Links for this version'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (!_busy && _links.isEmpty)
              Text(tr(context, 'No review links yet.')),
            for (final link in _links)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  link.revoked
                      ? tr(context, 'Revoked')
                      : link.expired
                      ? tr(context, 'Expired')
                      : link.responded
                      ? tr(context, 'Response recorded')
                      : tr(context, 'Awaiting response'),
                ),
                subtitle: Text(
                  '${tr(context, 'Expires')}: ${DateFormat.yMMMd(Localizations.localeOf(context).languageCode).add_jm().format(link.expires.toLocal())}',
                ),
                trailing: link.revoked || link.expired
                    ? null
                    : TextButton(
                        onPressed: _busy ? null : () => _revoke(link),
                        child: Text(tr(context, 'Revoke')),
                      ),
              ),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: Text(tr(context, 'Refresh links')),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
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
          ],
        ),
      ),
    );
  }
}
