import 'dart:convert';

enum RevisionStatus { proposed, correctionRequested, confirmed, rejected }

enum ItemStatus { open, inProgress, delivered, accepted }

class Participant {
  const Participant({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final String role;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};
  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
  );
}

class Evidence {
  const Evidence({
    required this.id,
    required this.text,
    required this.language,
    required this.kind,
    required this.createdAt,
    this.attachmentPath,
  });
  final String id;
  final String text;
  final String language;

  /// originalText | personalRecollection. Never upgrades recollection to a quote.
  final String kind;
  final DateTime createdAt;

  /// Private on-device recording path, never an uploaded or verified document.
  final String? attachmentPath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'language': language,
    'kind': kind,
    'createdAt': createdAt.toIso8601String(),
    'attachmentPath': attachmentPath,
  };
  factory Evidence.fromJson(Map<String, dynamic> json) => Evidence(
    id: json['id'] as String,
    text: json['text'] as String,
    language: json['language'] as String,
    kind: json['kind'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    attachmentPath: json['attachmentPath'] as String?,
  );
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    this.details = '',
    this.ownerId = 'you',
    this.dueDate,
    this.amountMinor,
    this.currency = 'USD',
  });
  final String id;
  final String title;
  final String details;
  final String ownerId;

  /// Date-only deadlines. Local midnight does not imply a promised exact time.
  final DateTime? dueDate;
  final int? amountMinor;
  final String currency;

  PlanItem copyWith({
    String? title,
    String? details,
    String? ownerId,
    DateTime? dueDate,
    bool clearDueDate = false,
    int? amountMinor,
    bool clearAmount = false,
    String? currency,
  }) => PlanItem(
    id: id,
    title: title ?? this.title,
    details: details ?? this.details,
    ownerId: ownerId ?? this.ownerId,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    amountMinor: clearAmount ? null : amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'details': details,
    'ownerId': ownerId,
    'dueDate': dueDate?.toIso8601String(),
    'amountMinor': amountMinor,
    'currency': currency,
  };
  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
    id: json['id'] as String,
    title: json['title'] as String,
    details: json['details'] as String? ?? '',
    ownerId: json['ownerId'] as String? ?? 'you',
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.parse(json['dueDate'] as String),
    amountMinor: json['amountMinor'] as int?,
    currency: json['currency'] as String? ?? 'USD',
  );
}

class PlanRevision {
  PlanRevision({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.authorId,
    required List<PlanItem> items,
    required List<String> requiredParticipantIds,
    this.baseRevisionId,
    this.status = RevisionStatus.proposed,
    List<String> acceptedBy = const [],
    List<Evidence> evidence = const [],
    this.correctionNote,
  }) : items = List.unmodifiable(items),
       requiredParticipantIds = List.unmodifiable(requiredParticipantIds),
       acceptedBy = List.unmodifiable(acceptedBy),
       evidence = List.unmodifiable(evidence) {
    if (id.isEmpty ||
        number < 1 ||
        requiredParticipantIds.isEmpty ||
        requiredParticipantIds.toSet().length !=
            requiredParticipantIds.length ||
        acceptedBy.toSet().length != acceptedBy.length ||
        acceptedBy.any((actor) => !requiredParticipantIds.contains(actor)) ||
        items.map((item) => item.id).toSet().length != items.length ||
        items.any(
          (item) =>
              item.id.isEmpty ||
              item.title.trim().isEmpty ||
              (item.amountMinor != null && item.amountMinor! < 0) ||
              !RegExp(r'^[A-Z]{3}$').hasMatch(item.currency),
        ) ||
        evidence.map((source) => source.id).toSet().length != evidence.length ||
        evidence.any(
          (source) =>
              source.id.isEmpty ||
              source.text.trim().isEmpty ||
              source.text.length > 30000 ||
              source.language.trim().isEmpty ||
              source.language.length > 80 ||
              !['originalText', 'personalRecollection'].contains(source.kind),
        )) {
      throw const FormatException(
        'This revision contains invalid identifiers or reviews.',
      );
    }
    if (status == RevisionStatus.confirmed &&
        !requiredParticipantIds.every(acceptedBy.contains)) {
      throw const FormatException(
        'A confirmed plan must include every required review.',
      );
    }
  }
  final String id;
  final int number;
  final String? baseRevisionId;
  final DateTime createdAt;
  final String authorId;
  final List<PlanItem> items;
  final List<String> requiredParticipantIds;
  final List<String> acceptedBy;
  final List<Evidence> evidence;
  final RevisionStatus status;
  final String? correctionNote;

  /// Exact canonical content representation, not a cryptographic signature.
  /// Immutable IDs and this value prevent accepting a changed local snapshot.
  String get contentKey => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'id': id,
        'baseRevisionId': baseRevisionId,
        'authorId': authorId,
        'items': items.map((item) => item.toJson()).toList(),
        'requiredParticipantIds': requiredParticipantIds,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      }),
    ),
  );
  bool get isPending =>
      status == RevisionStatus.proposed ||
      status == RevisionStatus.correctionRequested;

  PlanRevision withReview({
    RevisionStatus? status,
    List<String>? acceptedBy,
    String? correctionNote,
  }) => PlanRevision(
    id: id,
    number: number,
    createdAt: createdAt,
    authorId: authorId,
    items: items,
    requiredParticipantIds: requiredParticipantIds,
    baseRevisionId: baseRevisionId,
    status: status ?? this.status,
    acceptedBy: acceptedBy ?? this.acceptedBy,
    evidence: evidence,
    correctionNote: correctionNote ?? this.correctionNote,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'baseRevisionId': baseRevisionId,
    'createdAt': createdAt.toIso8601String(),
    'authorId': authorId,
    'items': items.map((item) => item.toJson()).toList(),
    'requiredParticipantIds': requiredParticipantIds,
    'acceptedBy': acceptedBy,
    'evidence': evidence.map((item) => item.toJson()).toList(),
    'status': status.name,
    'correctionNote': correctionNote,
  };
  factory PlanRevision.fromJson(Map<String, dynamic> json) => PlanRevision(
    id: json['id'] as String,
    number: json['number'] as int,
    baseRevisionId: json['baseRevisionId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    authorId: json['authorId'] as String,
    items: (json['items'] as List)
        .map(
          (item) => PlanItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    requiredParticipantIds: List<String>.from(
      json['requiredParticipantIds'] as List,
    ),
    acceptedBy: List<String>.from(json['acceptedBy'] as List),
    evidence: (json['evidence'] as List)
        .map(
          (item) => Evidence.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    status: RevisionStatus.values.byName(json['status'] as String),
    correctionNote: json['correctionNote'] as String?,
  );
}

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.message,
    required this.createdAt,
    required this.actorId,
    this.revisionId,
  });
  final String id;
  final String message;
  final DateTime createdAt;
  final String actorId;
  final String? revisionId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
    'actorId': actorId,
    'revisionId': revisionId,
  };
  factory ActivityEvent.fromJson(Map<String, dynamic> json) => ActivityEvent(
    id: json['id'] as String,
    message: json['message'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    actorId: json['actorId'] as String,
    revisionId: json['revisionId'] as String?,
  );
}

class Project {
  Project({
    required this.id,
    required this.title,
    required this.clientName,
    this.category = 'Creative',
    required List<Participant> participants,
    required this.currentRevision,
    List<PlanRevision> proposals = const [],
    List<PlanRevision> archivedRevisions = const [],
    List<ActivityEvent> history = const [],
    Map<String, ItemStatus> itemStatuses = const {},
    this.isDemo = false,
  }) : participants = List.unmodifiable(participants),
       proposals = List.unmodifiable(proposals),
       archivedRevisions = List.unmodifiable(archivedRevisions),
       history = List.unmodifiable(history),
       itemStatuses = Map.unmodifiable(itemStatuses) {
    final participantIds = participants.map((p) => p.id).toSet();
    if (id.isEmpty ||
        title.trim().isEmpty ||
        participants.any((participant) => participant.id.isEmpty) ||
        participantIds.length != participants.length ||
        !participantIds.contains('you') ||
        currentRevision.status != RevisionStatus.confirmed ||
        proposals.map((p) => p.id).toSet().length != proposals.length ||
        [currentRevision, ...proposals, ...archivedRevisions].any(
          (revision) =>
              !participantIds.contains(revision.authorId) ||
              revision.requiredParticipantIds.any(
                (actor) => !participantIds.contains(actor),
              ) ||
              revision.items.any(
                (item) => !participantIds.contains(item.ownerId),
              ),
        )) {
      throw const FormatException(
        'This project contains an invalid current plan or participant identity.',
      );
    }
  }
  final String id;
  final String title;
  final String clientName;
  final String category;
  final List<Participant> participants;
  final PlanRevision currentRevision;
  final List<PlanRevision> proposals;
  final List<PlanRevision> archivedRevisions;
  final List<ActivityEvent> history;

  /// Delivery progress is independent from immutable agreement snapshots.
  final Map<String, ItemStatus> itemStatuses;
  final bool isDemo;
  List<PlanRevision> get pendingProposals =>
      proposals.where((r) => r.isPending).toList(growable: false);
  List<PlanItem> get items => currentRevision.items;
  ItemStatus statusFor(String itemId) =>
      itemStatuses[itemId] ?? ItemStatus.open;
  String participantName(String participantId) =>
      participants
          .where((p) => p.id == participantId)
          .map((p) => p.name)
          .firstOrNull ??
      participantId;
  Project copyWith({
    PlanRevision? currentRevision,
    List<PlanRevision>? proposals,
    List<PlanRevision>? archivedRevisions,
    List<ActivityEvent>? history,
    Map<String, ItemStatus>? itemStatuses,
  }) => Project(
    id: id,
    title: title,
    clientName: clientName,
    category: category,
    participants: participants,
    currentRevision: currentRevision ?? this.currentRevision,
    proposals: proposals ?? this.proposals,
    archivedRevisions: archivedRevisions ?? this.archivedRevisions,
    history: history ?? this.history,
    itemStatuses: itemStatuses ?? this.itemStatuses,
    isDemo: isDemo,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'clientName': clientName,
    'category': category,
    'participants': participants.map((p) => p.toJson()).toList(),
    'currentRevision': currentRevision.toJson(),
    'proposals': proposals.map((p) => p.toJson()).toList(),
    'archivedRevisions': archivedRevisions.map((p) => p.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
    'itemStatuses': itemStatuses.map((k, v) => MapEntry(k, v.name)),
    'isDemo': isDemo,
  };
  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    title: json['title'] as String,
    clientName: json['clientName'] as String,
    category: json['category'] as String,
    participants: (json['participants'] as List)
        .map((p) => Participant.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    currentRevision: PlanRevision.fromJson(
      Map<String, dynamic>.from(json['currentRevision'] as Map),
    ),
    proposals: (json['proposals'] as List)
        .map((p) => PlanRevision.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    archivedRevisions: (json['archivedRevisions'] as List)
        .map((p) => PlanRevision.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    history: (json['history'] as List)
        .map((p) => ActivityEvent.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    itemStatuses: (json['itemStatuses'] as Map).map(
      (k, v) => MapEntry(k as String, ItemStatus.values.byName(v as String)),
    ),
    isDemo: json['isDemo'] as bool,
  );
}

class RecallWorkspace {
  RecallWorkspace({
    List<Project> projects = const [],
    this.locale = 'en',
    this.isDemo = false,
  }) : projects = List.unmodifiable(projects) {
    if (projects.map((project) => project.id).toSet().length !=
        projects.length) {
      throw const FormatException('Each project must have a unique identity.');
    }
  }
  final List<Project> projects;
  final String locale;
  final bool isDemo;
  RecallWorkspace copyWith({
    List<Project>? projects,
    String? locale,
    bool? isDemo,
  }) => RecallWorkspace(
    projects: projects ?? this.projects,
    locale: locale ?? this.locale,
    isDemo: isDemo ?? this.isDemo,
  );
  Map<String, dynamic> toJson() => {
    'format': 'recall-next-local',
    'version': 1,
    'projects': projects.map((p) => p.toJson()).toList(),
    'locale': locale,
    'isDemo': isDemo,
  };
  factory RecallWorkspace.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'recall-next-local' || json['version'] != 1) {
      throw const FormatException(
        'This Recall backup version is not supported.',
      );
    }
    return RecallWorkspace(
      projects: (json['projects'] as List)
          .map((p) => Project.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      locale: json['locale'] as String,
      isDemo: json['isDemo'] as bool,
    );
  }
}
