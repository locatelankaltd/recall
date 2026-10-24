import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/recall_controller.dart';
import '../design/design.dart';
import '../l10n/strings.dart';

String dateLabel(BuildContext context, DateTime? date) => date == null
    ? tr(context, 'noDate')
    : DateFormat.yMMMd(
        Localizations.localeOf(context).languageCode,
      ).format(date);
String moneyLabel(BuildContext context, PlanItem item) =>
    item.amountMinor == null
    ? tr(context, 'noAmount')
    : NumberFormat.currency(
        locale: Localizations.localeOf(context).languageCode,
        name: item.currency,
        symbol: '${item.currency} ',
        decimalDigits: 2,
      ).format(item.amountMinor! / 100);
String initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((part) => part.isEmpty ? '' : part.characters.first)
    .join()
    .toUpperCase();

Future<bool> perform(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
    return true;
  } catch (problem) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              problem.toString().replaceFirst('AgreementException: ', ''),
            ),
          ),
        ),
      );
    }
    return false;
  }
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding = 24});
  final List<Widget> children;
  final double padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: ListView(
        padding: EdgeInsets.fromLTRB(padding, 12, padding, 110),
        children: children,
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

class StateLabel extends StatelessWidget {
  const StateLabel(
    this.text, {
    super.key,
    this.pending = false,
    this.change = false,
  });
  final String text;
  final bool pending, change;
  @override
  Widget build(BuildContext context) {
    final p = RecallPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: change
            ? p.changeSurface
            : pending
            ? p.pendingSurface
            : p.confirmedSurface,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: change
              ? p.change
              : pending
              ? p.pending
              : p.confirmed,
        ),
      ),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    super.key,
    this.glyph = RecallGlyph.offline,
    this.warning = false,
  });
  final String text;
  final RecallGlyph glyph;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final p = RecallPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: warning ? p.pendingSurface : p.panel,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RecallIcon(glyph, size: 19, color: warning ? p.pending : p.muted),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: warning ? p.pending : p.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyPage extends StatelessWidget {
  const EmptyPage({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.glyph = RecallGlyph.projects,
  });
  final String title, body;
  final Widget? action;
  final RecallGlyph glyph;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 70,
          height: 70,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: RecallIcon(glyph, size: 32),
        ),
        const SizedBox(height: 24),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: RecallPalette.of(context).muted,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 26), action!],
      ],
    ),
  );
}

class ItemField extends StatelessWidget {
  const ItemField(
    this.label,
    this.value, {
    super.key,
    this.icon,
    this.changed = false,
  });
  final String label, value;
  final RecallGlyph? icon;
  final bool changed;
  @override
  Widget build(BuildContext context) {
    final p = RecallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            RecallIcon(icon!, size: 18, color: p.muted),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 4,
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: TextStyle(
                color: changed ? p.change : p.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
