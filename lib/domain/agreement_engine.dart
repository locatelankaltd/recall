import 'dart:math';

import 'recall_models.dart';

class AgreementException implements Exception {
  const AgreementException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AgreementEngine {
  AgreementEngine({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Random _random = Random.secure();
  String nextId(String prefix) =>
      '$prefix-${_clock().microsecondsSinceEpoch}-'
      '${List.generate(12, (_) => _random.nextInt(16).toRadixString(16)).join()}';

  Project createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
    bool isDemo = false,
  }) {
    if (title.trim().isEmpty || clientName.trim().isEmpty) {
      throw const AgreementException('Add a project name and a client name.');
    }
    return Project(
      id: nextId('project'),
      title: title.trim(),
      clientName: clientName.trim(),
      category: category,
      isDemo: isDemo,
      participants: [
        const Participant(id: 'you', name: 'You', role: 'Creator'),
        Participant(id: 'client', name: clientName.trim(), role: 'Client'),
      ],
      currentRevision: PlanRevision(
        id: nextId('revision'),
        number: 1,
        createdAt: _clock(),
        authorId: 'you',
        items: const [],
        requiredParticipantIds: const ['you'],
        acceptedBy: const ['you'],
        status: RevisionStatus.confirmed,
      ),
      history: [
        _event(
          'Created a private project plan. No client confirmation recorded.',
          'you',
        ),
      ],
    );
  }

  /// Editing the creator's private baseline never invents external acceptance.
  /// Once a shared version exists, changes must use proposeChange.
  Project addItem(Project project, PlanItem item) {
    _validateItem(project, item);
    if (project.currentRevision.requiredParticipantIds.any(
      (id) => id != 'you',
    )) {
      throw const AgreementException(
        'This plan is shared. Propose a change to add work.',
      );
    }
    if (project.currentRevision.items.any(
      (existing) => existing.id == item.id,
    )) {
      throw const AgreementException('That item already exists in the plan.');
    }
    final next = PlanRevision(
      id: nextId('revision'),
      number: project.currentRevision.number + 1,
      baseRevisionId: project.currentRevision.id,
      createdAt: _clock(),
      authorId: 'you',
      items: [...project.items, item],
      requiredParticipantIds: const ['you'],
      acceptedBy: const ['you'],
      status: RevisionStatus.confirmed,
    );
    return project.copyWith(
      currentRevision: next,
      archivedRevisions: [
        ...project.archivedRevisions,
        project.currentRevision,
      ],
      history: [
        ...project.history,
        _event('Added “${item.title}” to your private plan.', 'you', next.id),
      ],
    );
  }

  Project proposeChange(
    Project project, {
    required List<PlanItem> items,
    required String authorId,
    required List<Evidence> evidence,
  }) {
    _requireParticipant(project, authorId);
    if (items.isEmpty) {
      throw const AgreementException('A plan needs at least one item.');
    }
    if (items.map((i) => i.id).toSet().length != items.length) {
      throw const AgreementException(
        'Each plan item must have a unique identity.',
      );
    }
    for (final item in items) {
      _validateItem(project, item);
    }
    if (evidence.isEmpty || evidence.any((e) => e.text.trim().isEmpty)) {
      throw const AgreementException(
        'Add the source or your recollection for this request.',
      );
    }
    if (evidence.any(
      (source) =>
          source.text.length > 30000 ||
          source.language.trim().isEmpty ||
          source.language.length > 80 ||
          !['originalText', 'personalRecollection'].contains(source.kind),
    )) {
      throw const AgreementException(
        'Keep each source within 30,000 characters and include its language '
        'and whether it is original text or a personal recollection.',
      );
    }
    final largestNumber = [
      project.currentRevision.number,
      ...project.proposals.map((p) => p.number),
    ].reduce(max);
    final revision = PlanRevision(
      id: nextId('revision'),
      number: largestNumber + 1,
      createdAt: _clock(),
      authorId: authorId,
      items: items,
      baseRevisionId: project.currentRevision.id,
      requiredParticipantIds: project.participants.map((p) => p.id).toList(),
      acceptedBy: [authorId],
      evidence: evidence,
    );
    return project.copyWith(
      proposals: [...project.proposals, revision],
      history: [
        ...project.history,
        _event(
          'Proposed version ${revision.number}. '
          'The current plan stays unchanged.',
          authorId,
          revision.id,
        ),
      ],
    );
  }

  Project acceptRevision(
    Project project, {
    required String revisionId,
    required String participantId,
    required String expectedContentKey,
  }) {
    _requireParticipant(project, participantId);
    final revision = _findRevision(project, revisionId);
    if (revision.contentKey != expectedContentKey) {
      throw const AgreementException(
        'The plan changed. Review the latest version before confirming.',
      );
    }
    if (!revision.requiredParticipantIds.contains(participantId)) {
      throw const AgreementException(
        'This participant is not a reviewer of this version.',
      );
    }
    if (revision.status == RevisionStatus.confirmed &&
        revision.acceptedBy.contains(participantId)) {
      return project;
    }
    if (revision.status != RevisionStatus.proposed) {
      throw const AgreementException(
        'This request needs a new proposal before it can be confirmed.',
      );
    }
    if (revision.baseRevisionId != project.currentRevision.id) {
      throw const AgreementException(
        'The current plan changed. Compare this request with the latest plan.',
      );
    }
    if (revision.acceptedBy.contains(participantId)) return project;
    final accepted = [...revision.acceptedBy, participantId];
    final complete = revision.requiredParticipantIds.every(accepted.contains);
    final reviewed = revision.withReview(
      acceptedBy: accepted,
      status: complete ? RevisionStatus.confirmed : RevisionStatus.proposed,
    );
    return project.copyWith(
      currentRevision: complete ? reviewed : project.currentRevision,
      itemStatuses: complete
          ? {
              for (final item in reviewed.items)
                item.id:
                    _sameItem(
                      project.items
                          .where((old) => old.id == item.id)
                          .firstOrNull,
                      item,
                    )
                    ? project.statusFor(item.id)
                    : ItemStatus.open,
            }
          : project.itemStatuses,
      archivedRevisions: complete
          ? [...project.archivedRevisions, project.currentRevision]
          : project.archivedRevisions,
      proposals: project.proposals
          .map((p) => p.id == revisionId ? reviewed : p)
          .toList(),
      history: [
        ...project.history,
        _event(
          complete
              ? 'All required participants confirmed version ${revision.number}.'
              : '${project.participantName(participantId)} confirmed version ${revision.number}.',
          participantId,
          revisionId,
        ),
      ],
    );
  }

  Project requestCorrection(
    Project project, {
    required String revisionId,
    required String participantId,
    required String note,
  }) {
    _requireParticipant(project, participantId);
    final revision = _findRevision(project, revisionId);
    if (!revision.requiredParticipantIds.contains(participantId)) {
      throw const AgreementException(
        'This participant is not a reviewer of this version.',
      );
    }
    if (revision.status != RevisionStatus.proposed) {
      throw const AgreementException(
        'Only an open proposal can receive a correction request.',
      );
    }
    if (note.trim().isEmpty) {
      throw const AgreementException('Describe what needs to change.');
    }
    final corrected = revision.withReview(
      status: RevisionStatus.correctionRequested,
      acceptedBy: const [],
      correctionNote: note.trim(),
    );
    return project.copyWith(
      proposals: project.proposals
          .map((p) => p.id == revisionId ? corrected : p)
          .toList(),
      history: [
        ...project.history,
        _event(
          'Correction requested: ${note.trim()}',
          participantId,
          revisionId,
        ),
      ],
    );
  }

  Project setItemStatus(
    Project project, {
    required String itemId,
    required ItemStatus status,
    required String actorId,
  }) {
    _requireParticipant(project, actorId);
    final item = project.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      throw const AgreementException(
        'That item is not part of the current plan.',
      );
    }
    final prior = project.statusFor(itemId);
    if (prior == status) return project;
    if (status == ItemStatus.accepted && prior != ItemStatus.delivered) {
      throw const AgreementException(
        'Record delivery before recording acceptance.',
      );
    }
    if (status == ItemStatus.accepted && actorId == item.ownerId) {
      throw const AgreementException(
        'Recipient acceptance must be recorded by the recipient.',
      );
    }
    if (status != ItemStatus.accepted && actorId != item.ownerId) {
      throw const AgreementException(
        'Only the item owner can record their progress or delivery.',
      );
    }
    return project.copyWith(
      itemStatuses: {...project.itemStatuses, itemId: status},
      history: [
        ...project.history,
        _event(
          'Item progress: ${status.name}. '
          'This does not record payment.',
          actorId,
        ),
      ],
    );
  }

  bool _sameItem(PlanItem? a, PlanItem b) =>
      a != null &&
      a.title == b.title &&
      a.details == b.details &&
      a.ownerId == b.ownerId &&
      a.dueDate == b.dueDate &&
      a.amountMinor == b.amountMinor &&
      a.currency == b.currency;

  void _validateItem(Project project, PlanItem item) {
    if (item.title.trim().isEmpty) {
      throw const AgreementException('Add a title for this item.');
    }
    _requireParticipant(project, item.ownerId);
    if (item.amountMinor != null && item.amountMinor! < 0) {
      throw const AgreementException('An amount cannot be negative.');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(item.currency)) {
      throw const AgreementException('Choose a three-letter currency code.');
    }
  }

  void _requireParticipant(Project project, String actorId) {
    if (!project.participants.any((p) => p.id == actorId)) {
      throw const AgreementException(
        'This person is not part of this project.',
      );
    }
  }

  PlanRevision _findRevision(Project project, String id) =>
      project.proposals.where((r) => r.id == id).firstOrNull ??
      (throw const AgreementException('This proposal could not be found.'));
  ActivityEvent _event(String message, String actorId, [String? revisionId]) =>
      ActivityEvent(
        id: nextId('event'),
        message: message,
        createdAt: _clock(),
        actorId: actorId,
        revisionId: revisionId,
      );
}
