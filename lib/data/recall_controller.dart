import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../cloud/cloud_gateway.dart';
import '../platform/local_audio_index.dart';
import '../domain/agreement_engine.dart';
import '../domain/recall_models.dart';
import 'demo_workspace.dart';
import 'recall_repository.dart';
import 'recording_files.dart';

export '../domain/recall_models.dart';
export 'recall_repository.dart';

class RecallController extends ChangeNotifier {
  RecallController({
    RecallRepository? repository,
    this.cloudGateway,
    this.audioIndex,
    String initialLocale = 'en',
    AgreementEngine? engine,
    Future<void> Function(String?)? recordingRemover,
  }) : _repository =
           repository ??
           (cloudGateway == null
               ? SecureRecallRepository()
               : MemoryRecallRepository()),
       _engine = engine ?? AgreementEngine(),
       _recordingRemover = recordingRemover ?? discardRecording {
    _workspace = RecallWorkspace(locale: initialLocale);
  }
  final CloudProjectGateway? cloudGateway;
  final LocalAudioIndex? audioIndex;
  bool get isCloud => cloudGateway != null;
  final RecallRepository _repository;
  final AgreementEngine _engine;
  final Future<void> Function(String?) _recordingRemover;
  RecallWorkspace _workspace = RecallWorkspace();
  Future<void> _pendingSave = Future.value();
  bool isLoading = true;
  String? error;
  String? selectedProjectId;
  bool _disposed = false;
  bool _loaded = false;

  List<Project> get projects => _workspace.projects;
  bool get isDemo => _workspace.isDemo;
  String get locale => _workspace.locale;
  List<PlanRevision> get pendingProposals =>
      projects.expand((p) => p.pendingProposals).toList();
  Project? projectById(String? id) =>
      projects.where((p) => p.id == id).firstOrNull;
  String get exportJson =>
      const JsonEncoder.withIndent('  ').convert(_workspace.toJson());

  Future<void> initialize() async {
    final previous = _pendingSave;
    final completed = _loadAfter(previous);
    _pendingSave = completed;
    await completed;
  }

  Future<void> _loadAfter(Future<void> previous) async {
    // Loading participates in the same queue as writes: retrying a load must
    // never replace a change whose save is still in flight.
    await previous;
    if (_disposed) return;
    _loaded = false;
    isLoading = true;
    error = null;
    _notify();
    try {
      _workspace = isCloud
          ? RecallWorkspace(
              projects: await _fetchCloudProjects(),
              locale: locale,
            )
          : await _repository.load() ?? RecallWorkspace();
      _loaded = true;
    } catch (_) {
      error =
          'Your saved work could not be opened. It has not been deleted. '
          'Retry loading or explicitly reset local data.';
    } finally {
      isLoading = false;
      _notify();
    }
  }

  Future<T> _commit<T>(T Function() operation) async {
    final previous = _pendingSave;
    final completed = _runCommit(previous, operation);
    _pendingSave = completed.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return completed;
  }

  Future<T> _runCommit<T>(Future<void> previous, T Function() operation) async {
    await previous;
    final before = _workspace;
    final wasLoaded = _loaded;
    final priorSelection = selectedProjectId;
    try {
      final value = operation();
      if (!isCloud) await _repository.save(_workspace);
      error = null;
      _notify();
      return value;
    } catch (problem) {
      _workspace = before;
      _loaded = wasLoaded;
      selectedProjectId = priorSelection;
      error = problem is AgreementException
          ? problem.message
          : 'Could not save this change. Please try again.';
      _notify();
      rethrow;
    }
  }

  void _ensureLoaded() {
    if (_disposed) {
      throw const AgreementException(
        'This workspace is closed. Open the current workspace before continuing.',
      );
    }
    if (!_loaded) {
      throw const AgreementException(
        'Open your saved work before making changes.',
      );
    }
  }

  void _replace(Project project) {
    _workspace = _workspace.copyWith(
      projects: projects.map((p) => p.id == project.id ? project : p).toList(),
    );
  }

  Project _project(String id) =>
      projectById(id) ??
      (throw const AgreementException('This project could not be found.'));

  Future<String> _localCreateProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  }) => _commit(() {
    _ensureLoaded();
    final project = _engine.createProject(
      title: title,
      clientName: clientName,
      category: category,
    );
    _workspace = _workspace.copyWith(
      projects: [...projects, project],
      isDemo: false,
    );
    selectedProjectId = project.id;
    return project.id;
  });

  Future<void> _localAddItem({
    required String projectId,
    required String title,
    String details = '',
    String ownerId = 'you',
    DateTime? dueDate,
    int? amountMinor,
    String currency = 'USD',
  }) => _commit(() {
    _ensureLoaded();
    _replace(
      _engine.addItem(
        _project(projectId),
        PlanItem(
          id: _engine.nextId('item'),
          title: title.trim(),
          details: details.trim(),
          ownerId: ownerId,
          dueDate: dueDate,
          amountMinor: amountMinor,
          currency: currency,
        ),
      ),
    );
  });

  Future<void> _localProposeChange({
    required String projectId,
    required String itemId,
    String? title,
    String? details,
    DateTime? dueDate,
    int? amountMinor,
    String? currency,
    required String sourceText,
    String sourceLanguage = 'en',
    String sourceKind = 'personalRecollection',
    String? attachmentPath,
    bool clearDueDate = false,
    bool clearAmount = false,
    String? expectedBaseRevisionId,
  }) => _commit(() {
    _ensureLoaded();
    final project = _project(projectId);
    if (expectedBaseRevisionId != null &&
        expectedBaseRevisionId != project.currentRevision.id) {
      throw const AgreementException(
        'The current plan changed while you were editing. '
        'Your source and edits are kept here. Reopen the editor to review the latest plan.',
      );
    }
    if (!project.items.any((item) => item.id == itemId)) {
      throw const AgreementException('That item is not in the current plan.');
    }
    _replace(
      _engine.proposeChange(
        project,
        items: project.items
            .map(
              (item) => item.id != itemId
                  ? item
                  : item.copyWith(
                      title: title?.trim(),
                      details: details?.trim(),
                      dueDate: dueDate,
                      clearDueDate: clearDueDate,
                      amountMinor: amountMinor,
                      clearAmount: clearAmount,
                      currency: currency,
                    ),
            )
            .toList(),
        authorId: 'you',
        evidence: [
          Evidence(
            id: _engine.nextId('evidence'),
            text: sourceText.trim(),
            language: sourceLanguage,
            kind: sourceKind,
            createdAt: DateTime.now(),
            attachmentPath: attachmentPath,
          ),
        ],
      ),
    );
  });

  /// Other people's responses can only be simulated on fictional projects.
  /// Actual remote responses require an authenticated backend; never fabricated.
  void _verifyActor(Project project, String participantId) {
    if (participantId != 'you' && !project.isDemo) {
      throw const AgreementException(
        'Real client responses need a secure shared review service. '
        'You cannot confirm on someone else’s behalf on this device.',
      );
    }
  }

  Future<void> _localConfirmProposal({
    required String projectId,
    required String revisionId,
    required String participantId,
    String? expectedContentKey,
  }) => _commit(() {
    _ensureLoaded();
    final project = _project(projectId);
    _verifyActor(project, participantId);
    final revision = project.proposals
        .where((p) => p.id == revisionId)
        .firstOrNull;
    if (revision == null) {
      throw const AgreementException('This proposal could not be found.');
    }
    _replace(
      _engine.acceptRevision(
        project,
        revisionId: revisionId,
        participantId: participantId,
        expectedContentKey: expectedContentKey ?? revision.contentKey,
      ),
    );
  });
  Future<void> _localRequestCorrection({
    required String projectId,
    required String revisionId,
    required String participantId,
    required String note,
  }) => _commit(() {
    _ensureLoaded();
    final project = _project(projectId);
    _verifyActor(project, participantId);
    _replace(
      _engine.requestCorrection(
        project,
        revisionId: revisionId,
        participantId: participantId,
        note: note,
      ),
    );
  });
  Future<void> _localMarkItemStatus({
    required String projectId,
    required String itemId,
    required ItemStatus status,
    String actorId = 'you',
  }) => _commit(() {
    _ensureLoaded();
    final project = _project(projectId);
    _verifyActor(project, actorId);
    _replace(
      _engine.setItemStatus(
        project,
        itemId: itemId,
        status: status,
        actorId: actorId,
      ),
    );
  });
  Future<void> setLocale(String language) => _commit(() {
    _ensureLoaded();
    if (!['en', 'es', 'fr', 'de', 'pt', 'ar'].contains(language)) {
      throw const AgreementException('This preview language is not available.');
    }
    _workspace = _workspace.copyWith(locale: language);
  });
  Future<void> _localLoadDemo() => _commit(() {
    _ensureLoaded();
    if (projects.any((project) => !project.isDemo)) {
      throw const AgreementException(
        'Your projects are safe. Reset local data before replacing them with samples.',
      );
    }
    _workspace = createDemoWorkspace().copyWith(locale: locale);
  });
  Future<void> _localClearAll() async {
    final paths = await _commit(() {
      final paths = projects
          .expand(
            (project) => [
              project.currentRevision,
              ...project.proposals,
              ...project.archivedRevisions,
            ],
          )
          .expand((revision) => revision.evidence)
          .map((source) => source.attachmentPath)
          .whereType<String>()
          .toSet();
      _workspace = RecallWorkspace(locale: locale);
      _loaded = true;
      selectedProjectId = null;
      return paths;
    });
    var audioRemovalFailed = false;
    for (final path in paths) {
      try {
        await _recordingRemover(path);
      } catch (_) {
        audioRemovalFailed = true;
      }
    }
    if (audioRemovalFailed) {
      error =
          'The local workspace was reset, but some recording files could not be removed.';
      _notify();
    }
  }

  Future<void> _localImportJson(String text) => _commit(() {
    _ensureLoaded();
    if (utf8.encode(text).length > SecureRecallRepository.maxBytes) {
      throw const AgreementException('Choose a Recall export within 1 MB.');
    }
    final imported = RecallWorkspace.fromJson(
      Map<String, dynamic>.from(jsonDecode(text) as Map),
    );
    // A portable JSON file is an editable backup, not evidence that another
    // person authenticated a response. Real external reviews need the shared
    // service's verified response flow; sample projects remain explicit demos.
    for (final project in imported.projects.where((p) => !p.isDemo)) {
      final revisions = [
        project.currentRevision,
        ...project.proposals,
        ...project.archivedRevisions,
      ];
      final claimsExternalReview = revisions.any(
        (revision) =>
            revision.authorId != 'you' ||
            revision.acceptedBy.any((id) => id != 'you'),
      );
      final claimsExternalAcceptance = project.items.any(
        (item) =>
            item.ownerId == 'you' &&
            project.statusFor(item.id) == ItemStatus.accepted,
      );
      if (claimsExternalReview ||
          claimsExternalAcceptance ||
          project.history.any((event) => event.actorId != 'you')) {
        throw const AgreementException(
          'This export claims responses from other people that this local '
          'preview cannot verify. Your existing workspace has been kept. '
          'Use the shared review service for real recipient responses.',
        );
      }
    }
    _workspace = imported;
    selectedProjectId = null;
  });
  Future<Project?> _cloudWrite(
    Future<Project?> Function() operation, {
    String? deletedProjectId,
  }) async {
    final previous = _pendingSave;
    final completed = () async {
      await previous;
      _ensureLoaded();
      try {
        final remote = await operation();
        final saved = remote == null ? null : await _decorate(remote);
        if (saved != null) {
          _workspace = _workspace.copyWith(
            projects: [...projects.where((p) => p.id != saved.id), saved],
          );
        } else if (deletedProjectId != null) {
          _workspace = _workspace.copyWith(
            projects: projects.where((p) => p.id != deletedProjectId).toList(),
          );
        }
        error = null;
        _notify();
        return saved;
      } catch (problem) {
        error = problem is CloudException
            ? problem.message
            : 'Could not reach your account workspace. Your current plan is unchanged here. Retry or refresh before making another change.';
        _notify();
        rethrow;
      }
    }();
    _pendingSave = completed.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return completed;
  }

  Future<String> createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  }) async {
    if (!isCloud) {
      return _localCreateProject(
        title: title,
        clientName: clientName,
        category: category,
      );
    }
    final saved = await _cloudWrite(
      () => cloudGateway!.createProject(
        title: title,
        clientName: clientName,
        category: category,
      ),
    );
    selectedProjectId = saved!.id;
    return saved.id;
  }

  Future<void> addItem({
    required String projectId,
    required String title,
    String details = '',
    String ownerId = 'you',
    DateTime? dueDate,
    int? amountMinor,
    String currency = 'USD',
  }) async {
    if (!isCloud) {
      return _localAddItem(
        projectId: projectId,
        title: title,
        details: details,
        ownerId: ownerId,
        dueDate: dueDate,
        amountMinor: amountMinor,
        currency: currency,
      );
    }
    final item = PlanItem(
      id: _engine.nextId('item'),
      title: title.trim(),
      details: details.trim(),
      ownerId: ownerId,
      dueDate: dueDate,
      amountMinor: amountMinor,
      currency: currency,
    );
    await _cloudWrite(
      () => cloudGateway!.mutateProject(
        projectId: projectId,
        action: 'add_item',
        payload: {'item': item.toJson()},
      ),
    );
  }

  Future<void> proposeChange({
    required String projectId,
    required String itemId,
    String? title,
    String? details,
    DateTime? dueDate,
    int? amountMinor,
    String? currency,
    required String sourceText,
    String sourceLanguage = 'en',
    String sourceKind = 'personalRecollection',
    String? attachmentPath,
    bool clearDueDate = false,
    bool clearAmount = false,
    String? expectedBaseRevisionId,
  }) async {
    if (!isCloud) {
      return _localProposeChange(
        projectId: projectId,
        itemId: itemId,
        title: title,
        details: details,
        dueDate: dueDate,
        amountMinor: amountMinor,
        currency: currency,
        sourceText: sourceText,
        sourceLanguage: sourceLanguage,
        sourceKind: sourceKind,
        attachmentPath: attachmentPath,
        clearDueDate: clearDueDate,
        clearAmount: clearAmount,
        expectedBaseRevisionId: expectedBaseRevisionId,
      );
    }
    await _cloudWrite(() async {
      final project = _project(projectId);
      if (expectedBaseRevisionId != null &&
          project.currentRevision.id != expectedBaseRevisionId) {
        throw const AgreementException(
          'The current plan changed while you were editing. Your source and edits are kept here. Reopen the editor to review the latest plan.',
        );
      }
      if (!project.items.any((i) => i.id == itemId)) {
        throw const AgreementException('That item is not in the current plan.');
      }
      final items = project.items
          .map(
            (item) => item.id != itemId
                ? item
                : item.copyWith(
                    title: title?.trim(),
                    details: details?.trim(),
                    dueDate: dueDate,
                    clearDueDate: clearDueDate,
                    amountMinor: amountMinor,
                    clearAmount: clearAmount,
                    currency: currency,
                  ),
          )
          .toList();
      // Cloud requests intentionally exclude private local recording paths.
      final source = Evidence(
        id: _engine.nextId('evidence'),
        text: sourceText.trim(),
        language: sourceLanguage,
        kind: sourceKind,
        createdAt: DateTime.now(),
      );
      if (attachmentPath != null && audioIndex != null) {
        await audioIndex!.remember(source.id, attachmentPath);
      }
      return cloudGateway!.mutateProject(
        projectId: projectId,
        action: 'propose_change',
        payload: {
          'items': items.map((i) => i.toJson()).toList(),
          'authorId': 'you',
          'evidence': [source.toJson()..remove('attachmentPath')],
        },
      );
    });
  }

  Future<void> confirmProposal({
    required String projectId,
    required String revisionId,
    required String participantId,
    String? expectedContentKey,
  }) async {
    if (!isCloud) {
      return _localConfirmProposal(
        projectId: projectId,
        revisionId: revisionId,
        participantId: participantId,
        expectedContentKey: expectedContentKey,
      );
    }
    await _cloudWrite(() {
      if (participantId != 'you') {
        throw const AgreementException(
          'Only the recipient can respond through their private review link.',
        );
      }
      final revision = _project(
        projectId,
      ).proposals.where((p) => p.id == revisionId).firstOrNull;
      if (revision == null ||
          (expectedContentKey != null &&
              revision.contentKey != expectedContentKey)) {
        throw const AgreementException(
          'This version changed. Refresh and review it again.',
        );
      }
      return cloudGateway!.mutateProject(
        projectId: projectId,
        action: 'confirm',
        payload: {'revisionId': revisionId, 'actorId': 'you'},
      );
    });
  }

  Future<void> requestCorrection({
    required String projectId,
    required String revisionId,
    required String participantId,
    required String note,
  }) async {
    if (!isCloud) {
      return _localRequestCorrection(
        projectId: projectId,
        revisionId: revisionId,
        participantId: participantId,
        note: note,
      );
    }
    await _cloudWrite(() {
      if (participantId != 'you') {
        throw const AgreementException(
          'Only the recipient can respond through their private review link.',
        );
      }
      return cloudGateway!.mutateProject(
        projectId: projectId,
        action: 'correction',
        payload: {'revisionId': revisionId, 'actorId': 'you', 'note': note},
      );
    });
  }

  Future<void> markItemStatus({
    required String projectId,
    required String itemId,
    required ItemStatus status,
    String actorId = 'you',
  }) async {
    if (!isCloud) {
      return _localMarkItemStatus(
        projectId: projectId,
        itemId: itemId,
        status: status,
        actorId: actorId,
      );
    }
    await _cloudWrite(() {
      if (actorId != 'you') {
        throw const AgreementException(
          'You cannot respond on another person’s behalf.',
        );
      }
      return cloudGateway!.mutateProject(
        projectId: projectId,
        action: 'set_status',
        payload: {'itemId': itemId, 'status': status.name},
      );
    });
  }

  Future<void> deleteProject(String projectId) async {
    final paths = <String>{};
    final sourceIds = <String>{};
    void collect() {
      final project = _project(projectId);
      final sources = [
        project.currentRevision,
        ...project.proposals,
        ...project.archivedRevisions,
      ].expand((r) => r.evidence);
      for (final source in sources) {
        sourceIds.add(source.id);
        if (source.attachmentPath != null) paths.add(source.attachmentPath!);
      }
    }

    if (isCloud) {
      await _cloudWrite(() {
        collect();
        return cloudGateway!.mutateProject(
          projectId: projectId,
          action: 'delete',
        );
      }, deletedProjectId: projectId);
    } else {
      await _commit(() {
        _ensureLoaded();
        collect();
        _workspace = _workspace.copyWith(
          projects: projects.where((p) => p.id != projectId).toList(),
        );
      });
    }
    var removalFailed = false;
    for (final path in paths) {
      try {
        await _recordingRemover(path);
      } catch (_) {
        removalFailed = true;
      }
    }
    if (!removalFailed && audioIndex != null) {
      try {
        await audioIndex!.forgetSources(sourceIds);
      } catch (_) {
        removalFailed = true;
      }
    }
    if (removalFailed) {
      error =
          'The project was deleted, but some local recording files could not be removed.';
      _notify();
    }
  }

  Future<void> loadDemo() async {
    if (isCloud) {
      throw const AgreementException(
        'Switch to the local workspace to explore the fictional example.',
      );
    }
    await _localLoadDemo();
  }

  Future<void> clearAll() async {
    if (isCloud) {
      throw const AgreementException(
        'Delete individual account projects or use Delete account in Account settings. Local reset cannot erase a cloud account.',
      );
    }
    await _localClearAll();
  }

  Future<void> importJson(String text) async {
    if (isCloud) {
      throw const AgreementException(
        'Restore a portable export in your local workspace. Cloud review history can only come from the server.',
      );
    }
    await _localImportJson(text);
  }

  Future<Project> _decorate(Project server) async {
    try {
      return await audioIndex?.decorate(server) ?? server;
    } catch (_) {
      return server;
    }
  }

  Future<List<Project>> _fetchCloudProjects() async {
    final result = await cloudGateway!.fetchProjects();
    return Future.wait(result.map(_decorate));
  }

  /// Fetches server replies without replacing routes or pretending an offline
  /// write has synced. It shares the same queue as account mutations.
  Future<void> refreshFromCloud() async {
    if (!isCloud) return;
    final previous = _pendingSave;
    final completed = () async {
      await previous;
      try {
        final remote = await _fetchCloudProjects();
        _workspace = _workspace.copyWith(projects: remote);
        _loaded = true;
        error = null;
      } catch (_) {
        error =
            'Could not refresh your account workspace. Check your connection and try again.';
      }
      _notify();
    }();
    _pendingSave = completed;
    await completed;
  }

  void dismissError() {
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
