import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../platform/deadline_reminders.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key, required this.service});
  final DeadlineReminders service;
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.service.initialize());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final service = widget.service;
      final synced = service.lastSyncedAt;
      final text = Theme.of(context).textTheme;
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'remindersTitle'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
            children: [
              Text(tr(context, 'remindersIntro'), style: text.bodyLarge),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                key: const ValueKey('deadline-reminders-toggle'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'remindersToggle')),
                value: service.enabled,
                onChanged: service.isSupported && !service.busy
                    ? service.setEnabled
                    : null,
              ),
              if (service.busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  tr(context, service.statusKey),
                  style: text.titleMedium,
                ),
              ),
              const SizedBox(height: 20),
              Text(tr(context, 'remindersTiming')),
              const SizedBox(height: 12),
              Text(tr(context, 'remindersPrivacy')),
              const SizedBox(height: 12),
              Text(tr(context, 'remindersDelivery')),
              const SizedBox(height: 24),
              if (service.isSupported) ...[
                Text(
                  trParams(context, 'remindersScheduleCount', {
                    'count': '${service.scheduledCount}',
                  }),
                ),
                if (service.timeZoneName != null)
                  Text(
                    trParams(context, 'remindersZone', {
                      'zone': service.timeZoneName!,
                    }),
                  ),
                if (synced != null)
                  Text(
                    trParams(context, 'remindersLastSync', {
                      'date': DateFormat.yMMMd(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).add_jm().format(synced.toLocal()),
                    }),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: service.busy ? null : service.refresh,
                  child: Text(tr(context, 'remindersRefresh')),
                ),
                TextButton(
                  onPressed: service.busy ? null : service.openSettings,
                  child: Text(tr(context, 'remindersSettings')),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
