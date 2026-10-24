import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_services.dart';
import '../cloud/review_share_sheet.dart';
import '../data/recall_controller.dart';
import '../data/recording_files.dart';
import '../design/design.dart';
import '../l10n/strings.dart';
import 'update_editor.dart';
import 'widgets.dart';

class ProjectDetail extends StatelessWidget {
  const ProjectDetail({
    super.key,
    required this.controller,
    required this.projectId,
  });
  final RecallController controller;
  final String projectId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final project = controller.projectById(projectId);
      if (project == null) {
        return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(tr(context, 'emptyProjects'))),
        );
      }
      final shared = project.currentRevision.requiredParticipantIds.length > 1;
      return Scaffold(
        appBar: AppBar(
          title: Text(project.title),
          actions: [
            IconButton(
              tooltip: tr(context, 'deleteProject'),
              icon: const RecallIcon(RecallGlyph.close),
              onPressed: () => _deleteProject(context),
            ),
            IconButton(
              tooltip: tr(context, 'history'),
              icon: const RecallIcon(RecallGlyph.history),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      HistoryPage(controller: controller, projectId: projectId),
                ),
              ),
            ),
          ],
        ),
        body: PageBody(
          children: [
            const SizedBox(height: 12),
            Text(
              project.clientName,
              style: TextStyle(color: RecallPalette.of(context).muted),
            ),
            const SizedBox(height: 7),
            Text(
              tr(context, 'currentPlan'),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 17),
            Wrap(
              spacing: 9,
              runSpacing: 8,
              children: [
                StateLabel(
                  '${tr(context, 'version')} ${project.currentRevision.number}',
                ),
                StateLabel(tr(context, shared ? 'confirmed' : 'privatePlan')),
              ],
            ),
            const SizedBox(height: 16),
            if (project.isDemo)
              Notice(tr(context, 'sampleNote'), glyph: RecallGlyph.quote),
            if (!shared)
              Notice(tr(context, 'baselineNote'), glyph: RecallGlyph.person),
            if (controller.isCloud && shared)
              Notice(
                tr(context, 'cloudReviewIdentity'),
                glyph: RecallGlyph.person,
              ),
            if (project.items.isEmpty)
              EmptyPage(
                title: tr(context, 'newPlan'),
                body: tr(context, 'newPlanBody'),
                action: FilledButton(
                  onPressed: () => _addItem(context, project),
                  child: Text(tr(context, 'addItem')),
                ),
              ),
            ...project.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(21),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: tr(context, 'addUpdate'),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => UpdateEditor(
                                    controller: controller,
                                    projectId: projectId,
                                    initialItemId: item.id,
                                  ),
                                ),
                              ),
                              icon: const RecallIcon(
                                RecallGlyph.compare,
                                size: 21,
                              ),
                            ),
                          ],
                        ),
                        if (item.details.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            item.details,
                            style: TextStyle(
                              color: RecallPalette.of(context).muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Divider(),
                        ItemField(
                          tr(context, 'owner'),
                          project.participantName(item.ownerId),
                          icon: RecallGlyph.person,
                        ),
                        ItemField(
                          tr(context, 'date'),
                          dateLabel(context, item.dueDate),
                          icon: RecallGlyph.calendar,
                        ),
                        if (item.amountMinor != null)
                          ItemField(
                            tr(context, 'totalFee'),
                            moneyLabel(context, item),
                          ),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, 'markProgress'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<ItemStatus>(
                          initialValue: project.statusFor(item.id),
                          key: ValueKey(
                            '${item.id}-${project.statusFor(item.id).name}',
                          ),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                          ),
                          items: ItemStatus.values
                              .where(
                                (s) =>
                                    s != ItemStatus.accepted ||
                                    item.ownerId == 'client' ||
                                    project.isDemo,
                              )
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(tr(context, s.name)),
                                ),
                              )
                              .toList(),
                          onChanged: (s) {
                            if (s != null) {
                              perform(
                                context,
                                () => controller.markItemStatus(
                                  projectId: projectId,
                                  itemId: item.id,
                                  status: s,
                                  actorId: s == ItemStatus.accepted
                                      ? 'client'
                                      : 'you',
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!shared && project.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: () => _addItem(context, project),
                  icon: const RecallIcon(RecallGlyph.add, size: 19),
                  label: Text(tr(context, 'addItem')),
                ),
              ),
            if (project.pendingProposals.isNotEmpty) ...[
              SectionLabel(tr(context, 'proposed')),
              ...project.pendingProposals.map(
                (revision) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(18),
                    leading: RecallIcon(
                      RecallGlyph.compare,
                      color: RecallPalette.of(context).change,
                    ),
                    title: Text('${tr(context, 'version')} ${revision.number}'),
                    subtitle: Text(
                      tr(
                        context,
                        revision.status == RevisionStatus.correctionRequested
                            ? 'correction'
                            : 'pending',
                      ),
                    ),
                    trailing: const RecallIcon(
                      RecallGlyph.arrowRight,
                      size: 20,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RevisionPage(
                          controller: controller,
                          projectId: projectId,
                          revisionId: revision.id,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Notice(tr(context, 'deliveryNote'), glyph: RecallGlyph.check),
          ],
        ),
        bottomNavigationBar: project.items.isEmpty
            ? null
            : SafeArea(
                top: false,
                child: Align(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Padding(
                      key: const ValueKey('project-action-region'),
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('project-primary-action'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => UpdateEditor(
                                controller: controller,
                                projectId: projectId,
                              ),
                            ),
                          ),
                          icon: const RecallIcon(RecallGlyph.add),
                          label: Text(tr(context, 'addUpdate')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    },
  );
  Future<void> _deleteProject(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'deleteProject')),
        content: Text(tr(ctx, 'deleteProjectBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'deleteAction')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) {
      return;
    }
    final deleted = await perform(
      context,
      () => controller.deleteProject(projectId),
    );
    if (deleted && context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final warning = controller.error;
      Navigator.pop(context);
      if (warning != null) {
        messenger.showSnackBar(SnackBar(content: Text(warning)));
      }
    }
  }

  Future<void> _addItem(BuildContext context, Project project) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ItemSheet(controller: controller, projectId: projectId),
      );
}

class ItemSheet extends StatefulWidget {
  const ItemSheet({
    super.key,
    required this.controller,
    required this.projectId,
  });
  final RecallController controller;
  final String projectId;
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      details = TextEditingController(),
      amount = TextEditingController();
  DateTime? date;
  String currency = 'USD', owner = 'you';
  bool busy = false;
  @override
  void dispose() {
    title.dispose();
    details.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'addItem'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: title,
              decoration: InputDecoration(labelText: tr(context, 'itemTitle')),
              validator: (v) => v == null || v.trim().isEmpty
                  ? tr(context, 'required')
                  : null,
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: details,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr(context, 'details')),
            ),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              initialValue: owner,
              decoration: InputDecoration(labelText: tr(context, 'owner')),
              items: widget.controller
                  .projectById(widget.projectId)!
                  .participants
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.id == 'you' ? tr(context, 'you') : p.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) => owner = v!,
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              icon: const RecallIcon(RecallGlyph.calendar, size: 19),
              label: Text(dateLabel(context, date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => date = picked);
              },
            ),
            const SizedBox(height: 15),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr(context, 'totalFee'),
                    ),
                    validator: (v) =>
                        v == null ||
                            v.isEmpty ||
                            RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(v)
                        ? null
                        : tr(context, 'invalidAmount'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<String>(
                    initialValue: currency,
                    items: ['USD', 'EUR', 'GBP', 'CAD', 'AUD']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    decoration: InputDecoration(
                      labelText: tr(context, 'currency'),
                    ),
                    onChanged: (v) => currency = v!,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setState(() => busy = true);
                        try {
                          await widget.controller.addItem(
                            projectId: widget.projectId,
                            title: title.text,
                            details: details.text,
                            ownerId: owner,
                            dueDate: date,
                            amountMinor: amount.text.isEmpty
                                ? null
                                : (double.parse(
                                            amount.text.replaceAll(',', '.'),
                                          ) *
                                          100)
                                      .round(),
                            currency: currency,
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (context.mounted) {
                            setState(() => busy = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  widget.controller.error ??
                                      tr(context, 'error'),
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: Text(tr(context, 'save')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class RevisionPage extends StatelessWidget {
  const RevisionPage({
    super.key,
    required this.controller,
    required this.projectId,
    required this.revisionId,
    this.recipientPreview = false,
  });
  final RecallController controller;
  final String projectId, revisionId;
  final bool recipientPreview;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final project = controller.projectById(projectId);
      final revision = project?.proposals
          .where((r) => r.id == revisionId)
          .firstOrNull;
      if (project == null || revision == null) {
        return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text(tr(context, 'error'))),
        );
      }
      final changed = revision.items.where((item) {
        final before = [
          ...project.items,
          ...project.archivedRevisions.expand((r) => r.items),
        ].where((p) => p.id == item.id).firstOrNull;
        return before == null ||
            before.toJson().toString() != item.toJson().toString();
      }).toList();
      // Once published the current snapshot matches; show revision items for a readable receipt.
      final visible = changed.isEmpty ? revision.items : changed;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            tr(context, recipientPreview ? 'clientPreview' : 'proposed'),
          ),
        ),
        body: PageBody(
          children: [
            Text(
              project.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              project.clientName,
              style: TextStyle(color: RecallPalette.of(context).muted),
            ),
            const SizedBox(height: 16),
            StateLabel(
              '${tr(context, 'version')} ${revision.number} · ${tr(context, revision.status == RevisionStatus.confirmed
                  ? 'confirmed'
                  : revision.status == RevisionStatus.correctionRequested
                  ? 'correction'
                  : 'pending')}',
              pending: revision.status != RevisionStatus.confirmed,
            ),
            if (project.isDemo)
              Notice(
                tr(context, 'simulation'),
                glyph: RecallGlyph.quote,
                warning: true,
              ),
            if (recipientPreview && !project.isDemo)
              Notice(
                tr(context, 'realSharing'),
                glyph: RecallGlyph.offline,
                warning: true,
              ),
            const SizedBox(height: 14),
            Text(
              tr(context, 'reviewNote'),
              style: TextStyle(color: RecallPalette.of(context).muted),
            ),
            ...visible.map((item) {
              final base = project.currentRevision.id == revision.id
                  ? project.archivedRevisions
                        .where((r) => r.id == revision.baseRevisionId)
                        .firstOrNull
                  : project.currentRevision;
              final old = base?.items.where((p) => p.id == item.id).firstOrNull;
              return Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(21),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        if (old != null) ...[
                          Text(
                            tr(context, 'current'),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(old.title),
                          Text(
                            '${dateLabel(context, old.dueDate)} · ${moneyLabel(context, old)}',
                            style: TextStyle(
                              color: RecallPalette.of(context).muted,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Divider(),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          tr(context, 'new'),
                          style: TextStyle(
                            color: RecallPalette.of(context).change,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (item.details.isNotEmpty) Text(item.details),
                        ItemField(
                          tr(context, 'date'),
                          dateLabel(context, item.dueDate),
                          changed: old?.dueDate != item.dueDate,
                        ),
                        if (item.amountMinor != null)
                          ItemField(
                            tr(context, 'totalFee'),
                            moneyLabel(context, item),
                            changed: old?.amountMinor != item.amountMinor,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            SectionLabel(tr(context, 'sourceEvidence')),
            ...revision.evidence.map(
              (evidence) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: const RecallIcon(RecallGlyph.quote),
                  title: Text(evidence.text),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '${tr(context, evidence.kind == 'originalText' ? 'original' : 'recollection')} · ${evidence.language.toUpperCase()}',
                    ),
                  ),
                  onTap: () => showSource(context, evidence, project.title),
                ),
              ),
            ),
            if (revision.correctionNote != null)
              Notice(revision.correctionNote!, warning: true),
            const SizedBox(height: 25),
            if (controller.isCloud &&
                RecallServices.maybeOf(context)?.cloud.reviews != null &&
                !recipientPreview)
              OutlinedButton.icon(
                icon: const RecallIcon(RecallGlyph.send),
                label: Text(tr(context, 'shareReview')),
                onPressed: () => showReviewSharing(
                  context,
                  gateway: RecallServices.maybeOf(context)!.cloud.reviews!,
                  project: project,
                  revision: revision,
                ),
              ),
            if (revision.status == RevisionStatus.proposed) ...[
              if (!revision.acceptedBy.contains('you') && !recipientPreview)
                FilledButton(
                  onPressed: () => perform(
                    context,
                    () => controller.confirmProposal(
                      projectId: projectId,
                      revisionId: revisionId,
                      participantId: 'you',
                      expectedContentKey: revision.contentKey,
                    ),
                  ),
                  child: Text(tr(context, 'acceptMine')),
                ),
              if (!recipientPreview) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => RevisionPage(
                        controller: controller,
                        projectId: projectId,
                        revisionId: revisionId,
                        recipientPreview: true,
                      ),
                    ),
                  ),
                  icon: const RecallIcon(RecallGlyph.person, size: 19),
                  label: Text(tr(context, 'clientPreview')),
                ),
              ],
              if (recipientPreview && project.isDemo)
                FilledButton(
                  onPressed: () => perform(
                    context,
                    () => controller.confirmProposal(
                      projectId: projectId,
                      revisionId: revisionId,
                      participantId: 'client',
                      expectedContentKey: revision.contentKey,
                    ),
                  ),
                  child: Text(tr(context, 'sampleConfirm')),
                ),
              if (!recipientPreview || project.isDemo) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _correct(context),
                  child: Text(tr(context, 'correct')),
                ),
              ],
            ],
            const SizedBox(height: 15),
            ...revision.requiredParticipantIds.map(
              (id) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    RecallIcon(
                      revision.acceptedBy.contains(id)
                          ? RecallGlyph.check
                          : RecallGlyph.clock,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(project.participantName(id))),
                    Text(
                      tr(
                        context,
                        revision.acceptedBy.contains(id)
                            ? 'confirmed'
                            : 'pending',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> _correct(BuildContext context) async {
    var input = '';
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'correctionNote')),
        content: TextField(
          maxLines: 4,
          autofocus: true,
          onChanged: (value) => input = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () {
              if (input.trim().isNotEmpty) {
                Navigator.pop(ctx, input.trim());
              }
            },
            child: Text(tr(ctx, 'sendCorrection')),
          ),
        ],
      ),
    );
    if (note != null && context.mounted) {
      await perform(
        context,
        () => controller.requestCorrection(
          projectId: projectId,
          revisionId: revisionId,
          participantId: recipientPreview ? 'client' : 'you',
          note: note,
        ),
      );
    }
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.controller,
    required this.projectId,
  });
  final RecallController controller;
  final String projectId;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final project = controller.projectById(projectId);
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'history'))),
        body: PageBody(
          children: [
            Text(
              project?.title ?? '',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            for (final event in project?.history.reversed ?? <ActivityEvent>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: ListTile(
                  leading: const RecallIcon(RecallGlyph.history, size: 19),
                  title: Text(event.message),
                  subtitle: Text(dateLabel(context, event.createdAt)),
                ),
              ),
          ],
        ),
      );
    },
  );
}

void showSource(
  BuildContext context,
  Evidence source,
  String projectName,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(ctx, 'sourceEvidence'),
            style: Theme.of(ctx).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            projectName,
            style: TextStyle(color: RecallPalette.of(ctx).muted),
          ),
          const SizedBox(height: 20),
          StateLabel(
            '${source.language.toUpperCase()} · ${tr(ctx, source.kind == 'originalText' ? 'original' : 'recollection')}',
          ),
          const SizedBox(height: 20),
          SelectableText(source.text, style: Theme.of(ctx).textTheme.bodyLarge),
          if (source.attachmentPath != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const ValueKey('export-source-recording'),
              icon: const RecallIcon(RecallGlyph.export, size: 20),
              label: Text(tr(ctx, 'exportRecording')),
              onPressed: () async {
                var recordingAvailable = false;
                try {
                  final path = await requireOwnedRecordingPath(
                    source.attachmentPath!,
                  );
                  recordingAvailable = true;
                  if (!ctx.mounted) return;
                  final box = ctx.findRenderObject() as RenderBox?;
                  await SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(path, mimeType: 'audio/mp4')],
                      fileNameOverrides: ['recall-recording.m4a'],
                      title: tr(ctx, 'exportRecording'),
                      sharePositionOrigin: box != null && box.hasSize
                          ? box.localToGlobal(Offset.zero) & box.size
                          : const Rect.fromLTWH(20, 20, 100, 100),
                    ),
                  );
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            ctx,
                            recordingAvailable
                                ? 'recordingExportFailed'
                                : 'recordingUnavailable',
                          ),
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ],
          const SizedBox(height: 20),
          Text(
            dateLabel(ctx, source.createdAt),
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  ),
);
