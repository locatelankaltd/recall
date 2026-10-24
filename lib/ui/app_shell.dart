import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_services.dart';
import '../data/recall_controller.dart';
import '../design/design.dart';
import '../l10n/strings.dart';
import 'project_detail.dart';
import 'settings_page.dart';
import 'update_editor.dart';
import 'widgets.dart';

class RecallShell extends StatefulWidget {
  const RecallShell({super.key, required this.controller});
  final RecallController controller;
  @override
  State<RecallShell> createState() => _RecallShellState();
}

class _RecallShellState extends State<RecallShell> {
  int selected = 0;
  String search = '';
  RecallController get c => widget.controller;
  void openProject(Project project) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProjectDetail(controller: c, projectId: project.id),
    ),
  );
  Future<void> createProject() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NewProjectSheet(controller: c),
    );
    if (id != null && mounted) openProject(c.projectById(id)!);
  }

  Future<void> addUpdate() async {
    final eligible = c.projects.where((p) => p.items.isNotEmpty).toList();
    if (eligible.isEmpty) {
      await createProject();
      return;
    }
    Project? project;
    if (eligible.length == 1) {
      project = eligible.first;
    } else {
      project = await showModalBottomSheet<Project>(
        context: context,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr(ctx, 'chooseProject'),
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  ...eligible.map(
                    (p) => ListTile(
                      title: Text(p.title),
                      subtitle: Text(p.clientName),
                      trailing: const RecallIcon(RecallGlyph.arrowRight),
                      onTap: () => Navigator.pop(ctx, p),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (project != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UpdateEditor(controller: c, projectId: project!.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (c.isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RecallBrand(size: 52),
              const SizedBox(height: 28),
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(tr(context, 'loading')),
            ],
          ),
        ),
      );
    }
    if (c.projects.isEmpty && c.error == null) return _welcome();
    return Scaffold(
      appBar: AppBar(
        title: const RecallBrand(size: 31),
        actions: [
          if (RecallServices.maybeOf(context)?.hasSharedText == true)
            IconButton(
              tooltip: tr(context, 'sharedTextTitle'),
              onPressed: RecallServices.maybeOf(context)!.openSharedText,
              icon: const RecallIcon(RecallGlyph.paste),
            ),
          if (c.isCloud)
            IconButton(
              tooltip: tr(context, 'retry'),
              onPressed: c.refreshFromCloud,
              icon: const RecallIcon(RecallGlyph.history),
            ),
          if (RecallServices.maybeOf(context) != null)
            IconButton(
              tooltip: tr(context, 'accountTitle'),
              onPressed: RecallServices.maybeOf(context)!.openAccount,
              icon: const RecallIcon(RecallGlyph.person),
            ),
          IconButton(
            tooltip: tr(context, 'settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(controller: c),
              ),
            ),
            icon: const RecallIcon(RecallGlyph.settings),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: c.error != null && c.projects.isEmpty
          ? PageBody(
              children: [
                EmptyPage(
                  title: tr(context, 'error'),
                  body: c.error!,
                  glyph: RecallGlyph.offline,
                  action: FilledButton(
                    onPressed: c.initialize,
                    child: Text(tr(context, 'retry')),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(controller: c),
                    ),
                  ),
                  child: Text(tr(context, 'settings')),
                ),
              ],
            )
          : [today(), projects(), sources()][selected],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  key: const ValueKey('shell-action-region'),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('shell-primary-action'),
                      onPressed: selected == 1 ? createProject : addUpdate,
                      icon: const RecallIcon(RecallGlyph.add),
                      label: Text(
                        tr(context, selected == 1 ? 'newProject' : 'addUpdate'),
                      ),
                    ),
                  ),
                ),
                NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (value) =>
                      setState(() => selected = value),
                  destinations: [
                    NavigationDestination(
                      icon: const RecallIcon(RecallGlyph.today),
                      label: tr(context, 'today'),
                    ),
                    NavigationDestination(
                      icon: const RecallIcon(RecallGlyph.projects),
                      label: tr(context, 'projects'),
                    ),
                    NavigationDestination(
                      icon: const RecallIcon(RecallGlyph.sources),
                      label: tr(context, 'sources'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const RecallBrand(size: 34),
                        IconButton(
                          tooltip: tr(context, 'settings'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SettingsPage(controller: c),
                            ),
                          ),
                          icon: const RecallIcon(RecallGlyph.settings),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    const _LivingPage(),
                    const SizedBox(height: 36),
                    Text(
                      tr(context, 'welcome'),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 17),
                    Text(
                      tr(context, 'welcomeBody'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: RecallPalette.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (RecallServices.maybeOf(context) != null)
                      OutlinedButton.icon(
                        onPressed: RecallServices.maybeOf(context)!.openAccount,
                        icon: const RecallIcon(RecallGlyph.person),
                        label: Text(
                          tr(
                            context,
                            c.isCloud ? 'accountTitle' : 'accountSignIn',
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: createProject,
                        child: Text(tr(context, 'start')),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => perform(context, c.loadDemo),
                        child: Text(tr(context, 'tryExample')),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        RecallIcon(
                          RecallGlyph.offline,
                          size: 16,
                          color: RecallPalette.of(context).muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr(context, 'noCloud'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget today() {
    final review = <(Project, PlanRevision)>[];
    final waiting = <(Project, PlanRevision)>[];
    for (final project in c.projects) {
      for (final revision in project.pendingProposals) {
        (revision.acceptedBy.contains('you') ? waiting : review).add((
          project,
          revision,
        ));
      }
    }
    final due = <(Project, PlanItem)>[];
    for (final project in c.projects) {
      for (final item in project.items) {
        if (item.dueDate != null &&
            project.statusFor(item.id) != ItemStatus.accepted) {
          due.add((project, item));
        }
      }
    }
    due.sort((a, b) => a.$2.dueDate!.compareTo(b.$2.dueDate!));
    return PageBody(
      key: const PageStorageKey('today'),
      children: [
        if (c.isDemo)
          Notice(tr(context, 'sampleNote'), glyph: RecallGlyph.quote),
        const SizedBox(height: 12),
        Text(
          DateFormat.MMMMEEEEd(
            Localizations.localeOf(context).languageCode,
          ).format(DateTime.now()),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'today'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'overview'),
          style: TextStyle(color: RecallPalette.of(context).muted),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: _stat(
                  '${c.projects.length}',
                  tr(context, 'projectCount'),
                ),
              ),
              Container(
                width: 1,
                height: 46,
                color: RecallPalette.of(context).line,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _stat(
                  '${review.length + waiting.length}',
                  tr(context, 'needAnswer'),
                ),
              ),
              const RecallBrand(size: 42, showWordmark: false),
            ],
          ),
        ),
        SectionLabel(tr(context, 'review'), trailing: _count(review.length)),
        if (review.isEmpty)
          _quiet(tr(context, 'noReview'))
        else
          ...review.map((row) => _revisionRow(row.$1, row.$2)),
        if (waiting.isNotEmpty) ...[
          SectionLabel(
            tr(context, 'waiting'),
            trailing: _count(waiting.length),
          ),
          ...waiting.map((row) => _revisionRow(row.$1, row.$2)),
        ],
        SectionLabel(tr(context, 'dueNext')),
        ...due.take(5).map((row) => _dueRow(row.$1, row.$2)),
        if (due.isEmpty) _quiet(tr(context, 'newPlanBody')),
        const SizedBox(height: 24),
        Text(
          tr(context, 'noCloud'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 3),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
  Widget _count(int value) =>
      Text('$value', style: TextStyle(color: RecallPalette.of(context).muted));
  Widget _quiet(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 17),
    child: Text(text, style: TextStyle(color: RecallPalette.of(context).muted)),
  );

  Widget _revisionRow(Project project, PlanRevision revision) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => RevisionPage(
              controller: c,
              projectId: project.id,
              revisionId: revision.id,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: RecallPalette.of(context).changeSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: RecallIcon(
                      RecallGlyph.compare,
                      color: RecallPalette.of(context).change,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          project.clientName,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const RecallIcon(RecallGlyph.arrowRight, size: 20),
                ],
              ),
              const SizedBox(height: 16),
              StateLabel(
                tr(
                  context,
                  revision.status == RevisionStatus.correctionRequested
                      ? 'correction'
                      : revision.acceptedBy.contains('you')
                      ? 'pending'
                      : 'myAnswer',
                ),
                pending: true,
              ),
              const SizedBox(height: 12),
              Text(
                revision.evidence.firstOrNull?.text ??
                    tr(context, 'reviewNote'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                '${tr(context, 'version')} ${project.currentRevision.number} → ${revision.number}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _dueRow(Project project, PlanItem item) => InkWell(
    onTap: () => openProject(project),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RecallIcon(
              item.ownerId == 'you' ? RecallGlyph.calendar : RecallGlyph.person,
              size: 21,
              color: RecallPalette.of(context).muted,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${project.title} · ${project.participantName(item.ownerId)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel(context, item.dueDate),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const RecallIcon(RecallGlyph.arrowRight, size: 18),
        ],
      ),
    ),
  );

  Widget projects() {
    final filtered = c.projects.where(
      (p) => '${p.title} ${p.clientName}'.toLowerCase().contains(
        search.toLowerCase(),
      ),
    );
    return PageBody(
      key: const PageStorageKey('projects'),
      children: [
        const SizedBox(height: 14),
        Text(
          tr(context, 'projects'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 20),
        TextField(
          onChanged: (value) => setState(() => search = value),
          decoration: InputDecoration(
            hintText: tr(context, 'searchProjects'),
            prefixIcon: const Padding(
              padding: EdgeInsets.all(14),
              child: RecallIcon(RecallGlyph.search, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (filtered.isEmpty)
          EmptyPage(
            title: tr(context, 'emptyProjects'),
            body: tr(context, 'emptyProjectsBody'),
          ),
        ...filtered.map(
          (project) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: InkWell(
                onTap: () => openProject(project),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(21),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                            ),
                            child: Text(
                              initials(project.title),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  project.clientName,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const RecallIcon(RecallGlyph.arrowRight, size: 20),
                        ],
                      ),
                      const SizedBox(height: 21),
                      Wrap(
                        spacing: 9,
                        runSpacing: 8,
                        children: [
                          StateLabel(
                            '${tr(context, 'version')} ${project.currentRevision.number}',
                          ),
                          if (project.pendingProposals.isNotEmpty)
                            StateLabel(
                              '${project.pendingProposals.length} ${tr(context, 'proposed').toLowerCase()}',
                              pending: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        project.category,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget sources() {
    final all = <(Project, Evidence)>[];
    for (final project in c.projects) {
      final seen = <String>{};
      for (final revision in [
        project.currentRevision,
        ...project.proposals,
        ...project.archivedRevisions,
      ]) {
        for (final evidence in revision.evidence) {
          if (seen.add(evidence.id)) all.add((project, evidence));
        }
      }
    }
    all.sort((a, b) => b.$2.createdAt.compareTo(a.$2.createdAt));
    return PageBody(
      key: const PageStorageKey('sources'),
      children: [
        const SizedBox(height: 14),
        Text(
          tr(context, 'sources'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 9),
        Text(
          tr(context, 'sourceSaved'),
          style: TextStyle(color: RecallPalette.of(context).muted),
        ),
        if (all.isEmpty)
          EmptyPage(
            title: tr(context, 'emptySources'),
            body: tr(context, 'emptySourcesBody'),
            glyph: RecallGlyph.sources,
          ),
        ...all.map(
          (row) => Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showSource(context, row.$2, row.$1.title),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const RecallIcon(RecallGlyph.quote, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              row.$1.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            row.$2.language.toUpperCase(),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        row.$2.text,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${tr(context, row.$2.kind == 'originalText' ? 'original' : 'recollection')} · ${dateLabel(context, row.$2.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NewProjectSheet extends StatefulWidget {
  const NewProjectSheet({super.key, required this.controller});
  final RecallController controller;
  @override
  State<NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<NewProjectSheet> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), client = TextEditingController();
  String category = 'Creative';
  bool saving = false;
  @override
  void dispose() {
    title.dispose();
    client.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, 'newProject'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(context, 'projectTitle'),
              ),
              validator: requiredValue,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: client,
              decoration: InputDecoration(labelText: tr(context, 'clientName')),
              validator: requiredValue,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: InputDecoration(labelText: tr(context, 'category')),
              items: [
                'Creative',
                'Video',
                'Design',
                'Consulting',
                'Web',
                'Other',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => category = v!),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setState(() => saving = true);
                        try {
                          final id = await widget.controller.createProject(
                            title: title.text,
                            clientName: client.text,
                            category: category,
                          );
                          if (context.mounted) Navigator.pop(context, id);
                        } catch (_) {
                          if (context.mounted) {
                            setState(() => saving = false);
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
                child: Text(tr(context, 'create')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  String? requiredValue(String? value) =>
      value == null || value.trim().isEmpty ? tr(context, 'required') : null;
}

class _LivingPage extends StatelessWidget {
  const _LivingPage();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Two versions of a plan, with a clear change between them',
    image: true,
    child: Container(
      height: 215,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: SizedBox(
          width: 235,
          height: 170,
          child: Stack(
            children: [
              Positioned(
                left: 11,
                top: 12,
                child: Transform.rotate(
                  angle: -.12,
                  child: _page(context, false),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                child: Transform.rotate(
                  angle: .07,
                  child: _page(context, true),
                ),
              ),
              Positioned(
                left: 75,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RecallPalette.of(context).accent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: RecallIcon(
                    RecallGlyph.compare,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _page(BuildContext context, bool front) => Container(
    width: 134,
    height: 150,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: RecallPalette.of(context).panel,
      border: Border.all(color: RecallPalette.of(context).line),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecallIcon(
          front ? RecallGlyph.check : RecallGlyph.sources,
          size: 22,
          color: RecallPalette.of(context).accent,
        ),
        const SizedBox(height: 20),
        ...List.generate(
          3,
          (i) => Container(
            height: 6,
            width: i == 2 ? 53 : 95,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: front && i == 1
                  ? RecallPalette.of(context).change.withValues(alpha: .55)
                  : RecallPalette.of(context).line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ),
  );
}
