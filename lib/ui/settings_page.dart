import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../app_services.dart';
import 'subscription_page.dart';
import 'reminders_page.dart';
import '../data/recall_controller.dart';
import '../design/design.dart';
import '../l10n/strings.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final RecallController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'settings'))),
    body: PageBody(
      children: [
        const SizedBox(height: 16),
        const RecallBrand(size: 42),
        const SizedBox(height: 25),
        Notice(
          tr(context, controller.isCloud ? 'cloudWorkspaceNote' : 'noCloud'),
          glyph: controller.isCloud ? RecallGlyph.person : RecallGlyph.offline,
        ),
        if (RecallServices.maybeOf(context) != null)
          OutlinedButton.icon(
            onPressed: RecallServices.maybeOf(context)!.openAccount,
            icon: const RecallIcon(RecallGlyph.person),
            label: Text(tr(context, 'accountTitle')),
          ),
        if (RecallServices.maybeOf(context) != null)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SubscriptionPage(
                  client: RecallServices.maybeOf(context)?.cloud.client,
                ),
              ),
            ),
            icon: const RecallIcon(RecallGlyph.person),
            label: Text(tr(context, 'subscription')),
          ),
        if (RecallServices.maybeOf(context)?.reminders != null)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RemindersPage(
                  service: RecallServices.maybeOf(context)!.reminders!,
                ),
              ),
            ),
            icon: const RecallIcon(RecallGlyph.clock),
            label: Text(tr(context, 'remindersTitle')),
          ),
        SectionLabel(tr(context, 'language')),
        DropdownButtonFormField<String>(
          initialValue: ['en', 'es', 'fr'].contains(controller.locale)
              ? controller.locale
              : 'en',
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'es', child: Text('Español')),
            DropdownMenuItem(value: 'fr', child: Text('Français')),
          ],
          onChanged: (v) {
            if (v != null) {
              perform(
                context,
                () =>
                    RecallServices.maybeOf(context)?.setLocale?.call(v) ??
                    controller.setLocale(v),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        Text(
          tr(context, 'interfaceLanguageNote'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SectionLabel(tr(context, 'privacy')),
        Text(tr(context, 'privacyBody')),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const RecallIcon(RecallGlyph.export, size: 20),
          onPressed: () => _export(context),
          label: Text(tr(context, 'export')),
        ),
        const SizedBox(height: 10),
        if (!controller.isCloud)
          OutlinedButton.icon(
            icon: const RecallIcon(RecallGlyph.file, size: 20),
            onPressed: () => perform(context, () => _import(context)),
            label: Text(tr(context, 'import')),
          ),
        SectionLabel(tr(context, 'support')),
        Text(tr(context, 'supportBody')),
        const SizedBox(height: 12),
        Text(
          tr(context, 'appearance'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Recall',
            applicationVersion: '0.2.0',
          ),
          child: Text(tr(context, 'licenses')),
        ),
        if (controller.isDemo) ...[
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => _delete(context),
            child: Text(tr(context, 'resetDemo')),
          ),
        ],
        const SizedBox(height: 32),
        if (!controller.isCloud)
          TextButton(
            onPressed: () => _delete(context),
            child: Text(
              tr(context, 'delete'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );

  Future<void> _export(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(ctx, 'export'),
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Text(tr(ctx, 'exportNote')),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const RecallIcon(RecallGlyph.export, size: 19),
                label: Text(tr(ctx, 'export')),
                onPressed: () async {
                  await perform(ctx, () async {
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [
                          XFile.fromData(
                            Uint8List.fromList(
                              utf8.encode(controller.exportJson),
                            ),
                            mimeType: 'application/json',
                          ),
                        ],
                        fileNameOverrides: ['recall-workspace.json'],
                        title: 'Recall workspace export',
                        sharePositionOrigin: const Rect.fromLTWH(
                          20,
                          20,
                          100,
                          100,
                        ),
                      ),
                    );
                  });
                },
              ),
              TextButton(
                onPressed: () async {
                  final copied = await perform(
                    ctx,
                    () => Clipboard.setData(
                      ClipboardData(text: controller.exportJson),
                    ),
                  );
                  if (copied && ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text(tr(ctx, 'copied'))));
                  }
                },
                child: Text(tr(ctx, 'copy')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (file == null || !context.mounted) return;
    if (file.files.single.size > 1000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an export smaller than 1 MB.')),
      );
      return;
    }
    final bytes = file.files.single.bytes;
    if (bytes == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'import')),
        content: const Text(
          'Restoring replaces the local workspace. Export your current work first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'import')),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await perform(context, () => controller.importJson(utf8.decode(bytes)));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'deleteConfirm')),
        content: Text(tr(ctx, 'deleteBody')),
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
    if (yes == true && context.mounted) {
      final deleted = await perform(context, controller.clearAll);
      if (deleted && context.mounted) Navigator.pop(context);
    }
  }
}
