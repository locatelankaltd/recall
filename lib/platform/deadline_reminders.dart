import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/recall_models.dart';
import '../l10n/strings.dart';

class PlannedDeadlineReminder {
  const PlannedDeadlineReminder({required this.id, required this.scheduledFor});
  final int id;
  final tz.TZDateTime scheduledFor;
}

/// Date-only plan dates are interpreted in the resolved device IANA location.
/// Construct the previous calendar day at 09:00 rather than subtracting 24h,
/// which would move the local reminder hour across daylight-saving changes.
List<PlannedDeadlineReminder> planDeadlineReminders(
  List<Project> projects, {
  required tz.Location location,
  required DateTime now,
  int maxCount = 32,
}) {
  final localNow = tz.TZDateTime.from(now, location);
  final candidates = <tz.TZDateTime>[];
  final seen = <String>{};
  for (final project in projects) {
    if (project.isDemo) continue;
    for (final item in project.items) {
      if (!seen.add('${project.id}\u0000${item.id}')) continue;
      final status = project.statusFor(item.id);
      if (status != ItemStatus.open && status != ItemStatus.inProgress) {
        continue;
      }
      final due = item.dueDate;
      if (due == null) continue;
      final before = tz.TZDateTime(
        location,
        due.year,
        due.month,
        due.day - 1,
        9,
      );
      final morning = tz.TZDateTime(location, due.year, due.month, due.day, 9);
      final reminder = before.isAfter(localNow) ? before : morning;
      if (reminder.isAfter(localNow)) candidates.add(reminder);
    }
  }
  candidates.sort();
  final count = maxCount.clamp(0, 32);
  return List.unmodifiable([
    for (var index = 0; index < candidates.length && index < count; index++)
      PlannedDeadlineReminder(
        id: 61001 + index,
        scheduledFor: candidates[index],
      ),
  ]);
}

abstract interface class DeadlineReminderAdapter {
  bool get isSupported;
  Future<void> initialize();
  Future<bool> permissionsGranted();
  Future<bool> requestPermission();
  Future<void> cancelAll();
  Future<void> schedule(
    PlannedDeadlineReminder job, {
    required String title,
    required String body,
  });
  Future<bool> openSettings();
}

/// Uses inexact Android alarms; no exact-alarm permission or background worker.
/// Setup/API checked against flutter_local_notifications 22.3.2:
/// https://pub.dev/packages/flutter_local_notifications/versions/22.3.2
class NativeDeadlineReminderAdapter implements DeadlineReminderAdapter {
  NativeDeadlineReminderAdapter({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  @override
  bool get isSupported =>
      !kIsWeb && (_android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> initialize() async {
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('recall_monochrome'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestProvisionalPermission: false,
          requestCriticalPermission: false,
        ),
      ),
    );
    if (initialized != true) {
      throw StateError('Reminder initialization unavailable');
    }
  }

  @override
  Future<bool> permissionsGranted() async {
    if (_android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    final permission = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return permission?.isEnabled == true && permission?.isAlertEnabled == true;
  }

  @override
  Future<bool> requestPermission() async {
    if (_android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          await permissionsGranted();
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, sound: true, badge: false) ??
        false;
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> schedule(
    PlannedDeadlineReminder job, {
    required String title,
    required String body,
  }) => _plugin.zonedSchedule(
    id: job.id,
    title: title,
    body: body,
    scheduledDate: job.scheduledFor,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'recall_deadlines_v1',
        'Deadline reminders',
        channelDescription: 'Optional generic project deadline reminders',
        icon: 'recall_monochrome',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        visibility: NotificationVisibility.private,
      ),
      iOS: DarwinNotificationDetails(
        presentBadge: false,
        threadIdentifier: 'recall_deadlines',
      ),
    ),
    // No project, account, source, amount, client name, or private payload.
  );

  @override
  Future<bool> openSettings() async {
    if (_android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.openAppNotificationSettings() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.openAppNotificationSettings() ??
        false;
  }
}

abstract interface class ReminderPreferences {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool value);
}

class SharedReminderPreferences implements ReminderPreferences {
  SharedReminderPreferences({SharedPreferencesAsync? preferences})
    : _provided = preferences;
  SharedPreferencesAsync? _provided;
  SharedPreferencesAsync get _preferences =>
      _provided ??= SharedPreferencesAsync();
  static const storageKey = 'recall_deadline_reminders_enabled_v1';
  @override
  Future<bool> readEnabled() async =>
      await _preferences.getBool(storageKey) ?? false;
  @override
  Future<void> writeEnabled(bool value) =>
      _preferences.setBool(storageKey, value);
}

/// Default-off local scheduling for one active workspace. Only the non-sensitive
/// enable preference is persisted here; no workspace identity or plan text is.
class DeadlineReminders extends ChangeNotifier {
  DeadlineReminders({
    DeadlineReminderAdapter? adapter,
    ReminderPreferences? preferences,
    Future<String> Function()? resolveTimeZone,
    DateTime Function()? now,
  }) : _adapter = adapter ?? NativeDeadlineReminderAdapter(),
       _preferences = preferences ?? SharedReminderPreferences(),
       _resolveTimeZone = resolveTimeZone ?? _deviceTimeZone,
       _now = now ?? DateTime.now;

  final DeadlineReminderAdapter _adapter;
  final ReminderPreferences _preferences;
  final Future<String> Function() _resolveTimeZone;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _adapterInitialized = false;
  bool _disposed = false;
  bool _enabled = false;
  bool _permissionGranted = false;
  int _generation = 0;
  int _enableVersion = 0;
  int _operations = 0;
  int _scheduledCount = 0;
  String? _workspaceKey;
  String? _scheduledWorkspaceKey;
  String? _lastFingerprint;
  String? _timeZoneName;
  String _languageCode = 'en';
  String _statusKey = 'remindersOff';
  DateTime? _lastSyncedAt;
  List<Project> _projects = const [];

  bool get enabled => _enabled;
  bool get isSupported => _adapter.isSupported;
  bool get permissionGranted => _permissionGranted;
  bool get busy => _operations > 0;
  int get scheduledCount => _scheduledCount;
  String? get timeZoneName => _timeZoneName;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String get statusKey => _statusKey;

  static Future<String> _deviceTimeZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _enqueue(Future<void> Function() operation) {
    if (_disposed) return Future<void>.value();
    final result = Completer<void>();
    _operations++;
    _notify();
    _tail = _tail.then((_) async {
      try {
        if (!_disposed) await operation();
      } catch (_) {
        _statusKey = 'remindersFailed';
        _lastSyncedAt = null;
        _lastFingerprint = null;
        if (_adapterInitialized) {
          try {
            await _cancel();
          } catch (_) {
            /* No private native error output. */
          }
        }
      } finally {
        _operations--;
        _notify();
        result.complete();
      }
    });
    return result.future;
  }

  /// Never requests notification permission. Also clears schedules inherited
  /// from a previous app session before the current account/workspace is known.
  Future<void> initialize() {
    if (_disposed || _initialized) return Future<void>.value();
    if (_initializing != null) return _initializing!;
    final operation = _enqueue(() async {
      if (!isSupported) {
        _statusKey = 'remindersUnavailable';
        _initialized = true;
        return;
      }
      await _adapter.initialize();
      _adapterInitialized = true;
      await _cancel();
      _enabled = await _preferences.readEnabled();
      _permissionGranted = await _adapter.permissionsGranted();
      _initialized = true;
      _statusKey = _enabled ? 'remindersNoWorkspace' : 'remindersOff';
    });
    _initializing = operation;
    return operation.whenComplete(() {
      if (!_initialized) _initializing = null;
    });
  }

  /// The only permission-requesting operation; call from an explicit user tap.
  Future<void> setEnabled(bool value) {
    final enableVersion = ++_enableVersion;
    _generation++;
    final initialized = initialize();
    return _enqueue(() async {
      await initialized;
      if (!_initialized || !isSupported || enableVersion != _enableVersion) {
        return;
      }
      if (!value) {
        _enabled = false;
        await _cancel();
        await _preferences.writeEnabled(false);
        _statusKey = 'remindersOff';
        return;
      }
      final permitted = await _adapter.requestPermission();
      if (_disposed || enableVersion != _enableVersion) return;
      _permissionGranted = permitted;
      _enabled = permitted;
      await _preferences.writeEnabled(permitted);
      if (!permitted) {
        await _cancel();
        _statusKey = 'remindersPermission';
        return;
      }
      await _sync(_generation);
    });
  }

  Future<void> syncFor(
    List<Project> projects, {
    required String workspaceKey,
    String languageCode = 'en',
  }) {
    final generation = ++_generation;
    _projects = List.unmodifiable(projects);
    _workspaceKey = workspaceKey.isEmpty ? null : workspaceKey;
    _languageCode = strings.containsKey(languageCode) ? languageCode : 'en';
    final initialized = initialize();
    return _enqueue(() async {
      await initialized;
      if (_initialized && isSupported && _current(generation)) {
        await _sync(generation);
      }
    });
  }

  Future<void> refresh() => syncFor(
    _projects,
    workspaceKey: _workspaceKey ?? '',
    languageCode: _languageCode,
  );

  Future<void> _cancel() async {
    await _adapter.cancelAll();
    _scheduledCount = 0;
    _scheduledWorkspaceKey = null;
    _lastFingerprint = null;
  }

  Future<void> _sync(int generation) async {
    if (!_current(generation)) return;
    if (!_enabled || _workspaceKey == null) {
      if (_scheduledWorkspaceKey != null || _scheduledCount > 0) {
        await _cancel();
      }
      _statusKey = _enabled ? 'remindersNoWorkspace' : 'remindersOff';
      return;
    }
    // Clear the old account before asynchronous permission/time-zone lookups.
    if (_scheduledWorkspaceKey != _workspaceKey) await _cancel();
    if (!_current(generation)) return;
    _permissionGranted = await _adapter.permissionsGranted();
    if (!_current(generation)) return;
    if (!_permissionGranted) {
      await _cancel();
      _statusKey = 'remindersPermission';
      return;
    }
    tz.Location location;
    try {
      time_zone_data.initializeTimeZones();
      final identifier = await _resolveTimeZone();
      location = tz.getLocation(identifier);
    } catch (_) {
      if (!_current(generation)) return;
      await _cancel();
      _timeZoneName = null;
      _statusKey = 'remindersZoneFailed';
      return;
    }
    if (!_current(generation)) return;
    _timeZoneName = location.name;
    final currentTime = _now();
    final localDay = tz.TZDateTime.from(currentTime, location);
    final jobs = planDeadlineReminders(
      _projects,
      location: location,
      now: currentTime,
    );
    final title =
        strings[_languageCode]?['deadlineNotificationTitle'] ?? 'Recall';
    final body =
        strings[_languageCode]?['deadlineNotificationBody'] ??
        'A project deadline is coming up. Open Recall to review your plan.';
    final fingerprint = jsonEncode([
      _workspaceKey,
      _languageCode,
      location.name,
      localDay.year,
      localDay.month,
      localDay.day,
      title,
      body,
      jobs
          .map((job) => [job.id, job.scheduledFor.millisecondsSinceEpoch])
          .toList(),
    ]);
    if (fingerprint != _lastFingerprint) {
      _statusKey = 'remindersSyncing';
      await _cancel();
      if (!_current(generation)) return;
      for (final job in jobs) {
        await _adapter.schedule(job, title: title, body: body);
        if (!_current(generation)) {
          // A native call already in flight may complete after an account
          // change. Cancel it before the next workspace can schedule anything.
          await _cancel();
          return;
        }
      }
      _scheduledWorkspaceKey = _workspaceKey;
      _scheduledCount = jobs.length;
      _lastFingerprint = fingerprint;
    }
    _lastSyncedAt = currentTime;
    _statusKey = jobs.isEmpty ? 'remindersEmpty' : 'remindersReady';
  }

  Future<void> openSettings() => _enqueue(() async {
    if (isSupported) await _adapter.openSettings();
  });

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    // Successful schedules remain available while the app is closed. Account
    // switches and disabling must use syncFor/setEnabled before disposal.
    super.dispose();
  }
}
