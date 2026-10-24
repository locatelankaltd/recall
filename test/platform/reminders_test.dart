import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/domain/agreement_engine.dart';
import 'package:recall_next/domain/recall_models.dart';
import 'package:recall_next/platform/deadline_reminders.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class MemoryReminderPreferences implements ReminderPreferences {
  MemoryReminderPreferences({this.enabled = false});
  bool enabled;
  final writes = <bool>[];
  @override
  Future<bool> readEnabled() async => enabled;
  @override
  Future<void> writeEnabled(bool value) async {
    enabled = value;
    writes.add(value);
  }
}

class FakeDeadlineAdapter implements DeadlineReminderAdapter {
  bool supported = true;
  bool granted = false;
  bool grantOnRequest = true;
  int initializes = 0;
  int permissionRequests = 0;
  int cancellations = 0;
  final events = <String>[];
  final scheduled = <int, PlannedDeadlineReminder>{};
  final copy = <({String title, String body})>[];
  Completer<void>? holdNextSchedule;
  Completer<void>? scheduleEntered;
  @override
  bool get isSupported => supported;
  @override
  Future<void> initialize() async {
    initializes++;
  }

  @override
  Future<bool> permissionsGranted() async => granted;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    granted = grantOnRequest;
    return granted;
  }

  @override
  Future<void> cancelAll() async {
    cancellations++;
    events.add('cancel');
    scheduled.clear();
  }

  @override
  Future<void> schedule(
    PlannedDeadlineReminder job, {
    required String title,
    required String body,
  }) async {
    final pending = holdNextSchedule;
    holdNextSchedule = null;
    if (scheduleEntered?.isCompleted == false) scheduleEntered!.complete();
    if (pending != null) await pending.future;
    events.add('schedule:${job.id}');
    scheduled[job.id] = job;
    copy.add((title: title, body: body));
  }

  @override
  Future<bool> openSettings() async => true;
}

Project reminderProject({
  required String title,
  required DateTime deadline,
  String itemId = 'item-1',
  ItemStatus status = ItemStatus.open,
  bool demo = false,
}) {
  final engine = AgreementEngine();
  var project = engine.addItem(
    engine.createProject(title: title, clientName: 'Private client name'),
    PlanItem(id: itemId, title: 'Private deliverable name', dueDate: deadline),
  );
  project = project.copyWith(itemStatuses: {itemId: status});
  return demo
      ? Project(
          id: project.id,
          title: project.title,
          clientName: project.clientName,
          participants: project.participants,
          currentRevision: project.currentRevision,
          itemStatuses: project.itemStatuses,
          isDemo: true,
        )
      : project;
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test(
    'day-before reminders use civil 09:00 across spring and autumn DST changes',
    () {
      final location = tz.getLocation('America/New_York');
      final spring = planDeadlineReminders(
        [
          reminderProject(
            title: 'Spring project',
            deadline: DateTime(2027, 3, 15),
          ),
        ],
        location: location,
        now: tz.TZDateTime(location, 2027, 3, 12, 12),
      );
      expect(
        spring.single.scheduledFor,
        tz.TZDateTime(location, 2027, 3, 14, 9),
      );
      expect(spring.single.scheduledFor.toUtc(), DateTime.utc(2027, 3, 14, 13));
      final autumn = planDeadlineReminders(
        [
          reminderProject(
            title: 'Autumn project',
            deadline: DateTime(2026, 11, 2),
          ),
        ],
        location: location,
        now: tz.TZDateTime(location, 2026, 10, 30, 12),
      );
      expect(
        autumn.single.scheduledFor,
        tz.TZDateTime(location, 2026, 11, 1, 9),
      );
      expect(autumn.single.scheduledFor.toUtc(), DateTime.utc(2026, 11, 1, 14));
    },
  );

  test(
    'past day-before time falls back to future deadline 09:00 and skips elapsed deadlines',
    () {
      final location = tz.getLocation('Asia/Colombo');
      final tomorrow = reminderProject(
        title: 'Tomorrow',
        deadline: DateTime(2026, 10, 25),
      );
      final today = reminderProject(
        title: 'Today',
        deadline: DateTime(2026, 10, 24),
      );
      final overdue = reminderProject(
        title: 'Overdue',
        deadline: DateTime(2026, 10, 23),
      );
      final afterNine = planDeadlineReminders(
        [tomorrow, today, overdue],
        location: location,
        now: tz.TZDateTime(location, 2026, 10, 24, 10),
      );
      expect(afterNine, hasLength(1));
      expect(
        afterNine.single.scheduledFor,
        tz.TZDateTime(location, 2026, 10, 25, 9),
      );
      final beforeNine = planDeadlineReminders(
        [today],
        location: location,
        now: tz.TZDateTime(location, 2026, 10, 24, 8),
      );
      expect(
        beforeNine.single.scheduledFor,
        tz.TZDateTime(location, 2026, 10, 24, 9),
      );
      expect(
        planDeadlineReminders(
          [today],
          location: location,
          now: tz.TZDateTime(location, 2026, 10, 24, 9),
        ),
        isEmpty,
      );
    },
  );

  test(
    'only open current plans generate reminders, excluding delivery examples and proposal dates',
    () {
      final location = tz.getLocation('Asia/Colombo');
      final deadline = DateTime(2026, 10, 28);
      final open = reminderProject(title: 'Open', deadline: deadline);
      final delivered = reminderProject(
        title: 'Delivered',
        deadline: deadline,
        status: ItemStatus.delivered,
      );
      final accepted = reminderProject(
        title: 'Accepted',
        deadline: deadline,
        status: ItemStatus.accepted,
      );
      final demo = reminderProject(
        title: 'Example',
        deadline: deadline,
        demo: true,
      );
      final engine = AgreementEngine();
      final proposed = engine.proposeChange(
        open,
        items: [open.items.single.copyWith(dueDate: DateTime(2026, 10, 26))],
        authorId: 'you',
        evidence: [
          Evidence(
            id: 'evidence-proposal',
            text: 'Tentative earlier date',
            language: 'en',
            kind: 'personalRecollection',
            createdAt: DateTime(2026),
          ),
        ],
      );
      final jobs = planDeadlineReminders(
        [proposed, delivered, accepted, demo],
        location: location,
        now: tz.TZDateTime(location, 2026, 10, 24, 8),
      );
      expect(jobs, hasLength(1));
      expect(
        jobs.single.scheduledFor,
        tz.TZDateTime(location, 2026, 10, 27, 9),
      );
    },
  );

  test(
    'planner bounds earliest scheduled jobs to 32 and gives stable unique IDs',
    () {
      final location = tz.getLocation('Asia/Colombo');
      final projects = List.generate(
        40,
        (index) => reminderProject(
          title: 'Project $index',
          deadline: DateTime(2026, 11, index + 1),
          itemId: 'item-$index',
        ),
      ).reversed.toList();
      final now = tz.TZDateTime(location, 2026, 10, 24);
      final first = planDeadlineReminders(
        projects,
        location: location,
        now: now,
      );
      final second = planDeadlineReminders(
        projects.reversed.toList(),
        location: location,
        now: now,
      );
      expect(first, hasLength(32));
      expect(first.map((job) => job.id).toSet(), hasLength(32));
      expect(first.map((job) => job.id), second.map((job) => job.id));
      expect(
        first.first.scheduledFor,
        tz.TZDateTime(location, 2026, 10, 31, 9),
      );
      expect(
        planDeadlineReminders(
          projects,
          location: location,
          now: now,
          maxCount: 5,
        ),
        hasLength(5),
      );
    },
  );

  test(
    'initialization never prompts for notification permission and starts off by default',
    () async {
      final adapter = FakeDeadlineAdapter();
      final reminders = DeadlineReminders(
        adapter: adapter,
        preferences: MemoryReminderPreferences(),
        resolveTimeZone: () async => 'Asia/Colombo',
      );
      addTearDown(reminders.dispose);
      await reminders.initialize();
      expect(reminders.enabled, isFalse);
      expect(adapter.permissionRequests, 0);
      expect(adapter.scheduled, isEmpty);
    },
  );

  test('permission denial creates no scheduled notifications', () async {
    final adapter = FakeDeadlineAdapter()..grantOnRequest = false;
    final reminders = DeadlineReminders(
      adapter: adapter,
      preferences: MemoryReminderPreferences(),
      resolveTimeZone: () async => 'Asia/Colombo',
      now: () => DateTime.utc(2026, 10, 24),
    );
    addTearDown(reminders.dispose);
    await reminders.initialize();
    await reminders.syncFor([
      reminderProject(
        title: 'Private project',
        deadline: DateTime(2026, 10, 28),
      ),
    ], workspaceKey: 'account:A');
    await reminders.setEnabled(true);
    expect(adapter.permissionRequests, 1);
    expect(reminders.permissionGranted, isFalse);
    expect(reminders.scheduledCount, 0);
    expect(adapter.scheduled, isEmpty);
  });

  test('unknown device timezone never silently schedules using UTC', () async {
    final adapter = FakeDeadlineAdapter()..granted = true;
    final reminders = DeadlineReminders(
      adapter: adapter,
      preferences: MemoryReminderPreferences(enabled: true),
      resolveTimeZone: () async => throw StateError('Timezone unavailable'),
      now: () => DateTime.utc(2026, 10, 24),
    );
    addTearDown(reminders.dispose);
    await reminders.initialize();
    await reminders.syncFor([
      reminderProject(
        title: 'Private project',
        deadline: DateTime(2026, 10, 28),
      ),
    ], workspaceKey: 'account:A');
    expect(reminders.timeZoneName, isNull);
    expect(reminders.scheduledCount, 0);
    expect(adapter.scheduled, isEmpty);
  });

  test(
    'explicit disabling cancels scheduled notifications and persists the choice',
    () async {
      final adapter = FakeDeadlineAdapter()..granted = true;
      final preferences = MemoryReminderPreferences(enabled: true);
      final reminders = DeadlineReminders(
        adapter: adapter,
        preferences: preferences,
        resolveTimeZone: () async => 'Asia/Colombo',
        now: () => DateTime.utc(2026, 10, 24),
      );
      addTearDown(reminders.dispose);
      await reminders.initialize();
      await reminders.syncFor([
        reminderProject(
          title: 'Private project',
          deadline: DateTime(2026, 10, 28),
        ),
      ], workspaceKey: 'account:A');
      expect(adapter.scheduled, isNotEmpty);
      final prior = adapter.cancellations;
      await reminders.setEnabled(false);
      expect(reminders.enabled, isFalse);
      expect(preferences.writes.last, isFalse);
      expect(adapter.cancellations, greaterThan(prior));
      expect(adapter.scheduled, isEmpty);
    },
  );

  test(
    'unchanged plan fingerprint does not repeatedly cancel and reschedule',
    () async {
      final adapter = FakeDeadlineAdapter()..granted = true;
      final reminders = DeadlineReminders(
        adapter: adapter,
        preferences: MemoryReminderPreferences(enabled: true),
        resolveTimeZone: () async => 'Asia/Colombo',
        now: () => DateTime.utc(2026, 10, 24),
      );
      addTearDown(reminders.dispose);
      final projects = [
        reminderProject(
          title: 'Private project',
          deadline: DateTime(2026, 10, 28),
        ),
      ];
      await reminders.initialize();
      await reminders.syncFor(projects, workspaceKey: 'account:A');
      final cancels = adapter.cancellations;
      final scheduled = adapter.copy.length;
      await reminders.syncFor(projects, workspaceKey: 'account:A');
      expect(adapter.cancellations, cancels);
      expect(adapter.copy.length, scheduled);
    },
  );

  test(
    'switching workspace during asynchronous scheduling cancels old jobs before new jobs remain',
    () async {
      final adapter = FakeDeadlineAdapter()..granted = true;
      final now = DateTime.utc(2026, 10, 24);
      final reminders = DeadlineReminders(
        adapter: adapter,
        preferences: MemoryReminderPreferences(enabled: true),
        resolveTimeZone: () async => 'Asia/Colombo',
        now: () => now,
      );
      addTearDown(reminders.dispose);
      await reminders.initialize();
      adapter.events.clear();
      final projectA = reminderProject(
        title: 'Account A private project',
        deadline: DateTime(2026, 10, 28),
      );
      final projectB = reminderProject(
        title: 'Account B private project',
        deadline: DateTime(2026, 10, 29),
      );
      adapter.holdNextSchedule = Completer<void>();
      final release = adapter.holdNextSchedule!;
      adapter.scheduleEntered = Completer<void>();
      final syncA = reminders.syncFor([projectA], workspaceKey: 'account:A');
      await adapter.scheduleEntered!.future;
      final syncB = reminders.syncFor([projectB], workspaceKey: 'account:B');
      release.complete();
      await syncA;
      await syncB;
      final expectedB = planDeadlineReminders(
        [projectB],
        location: tz.getLocation('Asia/Colombo'),
        now: now,
      ).single;
      expect(adapter.scheduled.keys, [expectedB.id]);
      expect(
        adapter.scheduled.values.single.scheduledFor,
        expectedB.scheduledFor,
      );
      final firstSchedule = adapter.events.indexWhere(
        (event) => event.startsWith('schedule:'),
      );
      final lastSchedule = adapter.events.lastIndexWhere(
        (event) => event.startsWith('schedule:'),
      );
      expect(lastSchedule, greaterThan(firstSchedule));
      expect(
        adapter.events.sublist(firstSchedule + 1, lastSchedule),
        contains('cancel'),
      );
      expect(reminders.scheduledCount, 1);
    },
  );

  test(
    'notification copy is localized and contains no private names or workspace IDs',
    () async {
      final adapter = FakeDeadlineAdapter()..granted = true;
      final reminders = DeadlineReminders(
        adapter: adapter,
        preferences: MemoryReminderPreferences(enabled: true),
        resolveTimeZone: () async => 'Asia/Colombo',
        now: () => DateTime.utc(2026, 10, 24),
      );
      addTearDown(reminders.dispose);
      final projects = [
        reminderProject(
          title: 'Secret project title',
          deadline: DateTime(2026, 10, 28),
        ),
      ];
      await reminders.initialize();
      await reminders.syncFor(
        projects,
        workspaceKey: 'account:private-user-uuid',
        languageCode: 'en',
      );
      final english = adapter.copy.last;
      await reminders.syncFor(
        projects,
        workspaceKey: 'account:private-user-uuid',
        languageCode: 'es',
      );
      final spanish = adapter.copy.last;
      expect(spanish.body, isNot(english.body));
      for (final message in [english, spanish]) {
        for (final secret in [
          'Secret project title',
          'Private client name',
          'Private deliverable name',
          'private-user-uuid',
          'item-1',
        ]) {
          expect('${message.title} ${message.body}', isNot(contains(secret)));
        }
      }
    },
  );
}
