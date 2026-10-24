import '../domain/agreement_engine.dart';
import '../domain/recall_models.dart';

/// Entirely fictional. Only these explicitly labeled projects permit local
/// simulation of another person's confirmation. Never used as real evidence.
RecallWorkspace createDemoWorkspace({DateTime? now}) {
  final time = now ?? DateTime.now();
  final today = DateTime(time.year, time.month, time.day);
  final engine = AgreementEngine(clock: () => time);
  Project baseline(
    String title,
    String client,
    List<PlanItem> items,
    String category,
  ) {
    var project = engine.createProject(
      title: title,
      clientName: client,
      category: category,
      isDemo: true,
    );
    for (final item in items) {
      project = engine.addItem(project, item);
    }
    final revision = PlanRevision(
      id: engine.nextId('sample-version'),
      number: 1,
      createdAt: time.subtract(const Duration(days: 2)),
      authorId: 'you',
      items: items,
      requiredParticipantIds: const ['you', 'client'],
      acceptedBy: const ['you', 'client'],
      status: RevisionStatus.confirmed,
    );
    return project.copyWith(
      currentRevision: revision,
      archivedRevisions: [],
      history: [
        ActivityEvent(
          id: engine.nextId('event'),
          message: 'Fictional sample: both participants confirmed version 1.',
          createdAt: time.subtract(const Duration(days: 2)),
          actorId: 'you',
          revisionId: revision.id,
        ),
      ],
    );
  }

  final video = PlanItem(
    id: 'sample-video',
    title: 'Two launch videos',
    details: 'Two 30-second films, with one round of revisions.',
    ownerId: 'you',
    dueDate: today.add(const Duration(days: 6)),
    amountMinor: 60000,
    currency: 'EUR',
  );
  var north = baseline('Launch films', 'Marta · Studio North', [
    video,
    PlanItem(
      id: 'sample-assets',
      title: 'Send the final brand assets',
      details: 'Logo files, brand colors, and approved product shots.',
      ownerId: 'client',
      dueDate: today.add(const Duration(days: 1)),
    ),
  ], 'Video');
  north = engine.proposeChange(
    north,
    authorId: 'you',
    items: [
      video.copyWith(
        title: 'Three launch videos',
        details: 'Three 30-second films, with one round of revisions.',
        dueDate: today.add(const Duration(days: 10)),
        amountMinor: 85000,
      ),
      north.items[1],
    ],
    evidence: [
      Evidence(
        id: engine.nextId('evidence'),
        text:
            'Could you add a third video? Would delivery four days later work, '
            'for a total of 850 euros?',
        language: 'en',
        kind: 'originalText',
        createdAt: time.subtract(const Duration(hours: 3)),
      ),
    ],
  );
  final bloom = baseline('Bloom brand identity', 'Sam · Bloom', [
    PlanItem(
      id: 'sample-logo',
      title: 'Explore three logo directions',
      details: 'Initial concepts for the new identity.',
      ownerId: 'you',
      dueDate: today.add(const Duration(days: 2)),
      amountMinor: 120000,
      currency: 'USD',
    ),
    PlanItem(
      id: 'sample-feedback',
      title: 'Choose a direction',
      details: 'Consolidate feedback into one response.',
      ownerId: 'client',
      dueDate: today.add(const Duration(days: 4)),
    ),
  ], 'Design');
  final field = baseline('Fieldwork website', 'Jordan · Fieldwork', [
    PlanItem(
      id: 'sample-homepage',
      title: 'Deliver the homepage concept',
      details: 'Desktop and mobile layouts.',
      ownerId: 'you',
      dueDate: today,
    ),
  ], 'Web');
  return RecallWorkspace(projects: [north, bloom, field], isDemo: true);
}
