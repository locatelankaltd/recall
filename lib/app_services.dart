import 'package:flutter/widgets.dart';
import 'cloud/recall_cloud.dart';
import 'platform/deadline_reminders.dart';

class RecallServices extends InheritedWidget {
  const RecallServices({
    super.key,
    required this.cloud,
    required this.openAccount,
    required this.openSharedText,
    required this.hasSharedText,
    this.reminders,
    this.setLocale,
    required super.child,
  });
  final RecallCloud cloud;
  final VoidCallback openAccount;
  final VoidCallback openSharedText;
  final bool hasSharedText;
  final DeadlineReminders? reminders;
  final Future<void> Function(String)? setLocale;
  static RecallServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecallServices>();
  @override
  bool updateShouldNotify(RecallServices oldWidget) =>
      oldWidget.cloud != cloud || oldWidget.hasSharedText != hasSharedText;
}
