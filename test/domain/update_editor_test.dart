import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/data/demo_workspace.dart';
import 'package:recall_next/data/recall_controller.dart';
import 'package:recall_next/design/recall_theme.dart';
import 'package:recall_next/ui/update_editor.dart';

void main() {
  Future<RecallController> showEditor(
    WidgetTester tester, {
    RecallWorkspace? workspace,
  }) async {
    final repository = MemoryRecallRepository();
    if (workspace != null) await repository.save(workspace);
    final controller = RecallController(repository: repository);
    await controller.initialize();
    if (workspace == null) await controller.loadDemo();
    await tester.pumpWidget(
      MaterialApp(
        theme: RecallTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => UpdateEditor(
                      controller: controller,
                      projectId: controller.projects.first.id,
                    ),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'saving manually reviewed comma-decimal values keeps current plan unchanged',
    (tester) async {
      final controller = await showEditor(tester);
      final id = controller.projects.first.id;
      final original = controller.projects.first.currentRevision.contentKey;
      final sourceField = find.byKey(const ValueKey('update-source'));
      final titleField = find.byKey(const ValueKey('update-title'));
      final amountField = find.byKey(const ValueKey('update-amount'));
      await tester.scrollUntilVisible(
        sourceField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        sourceField,
        'A client asked for another film for a total of EUR 850.50.',
      );
      await tester.scrollUntilVisible(
        titleField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(titleField, 'Three reviewed launch videos');
      await tester.scrollUntilVisible(
        amountField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(amountField, '850,50');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('update-reviewed')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      final save = find.text('Save proposed change');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final project = controller.projectById(id)!;
      expect(project.currentRevision.contentKey, original);
      expect(project.proposals.last.items.first.amountMinor, 85050);
      expect(
        project.proposals.last.items.first.title,
        'Three reviewed launch videos',
      );
      expect(
        project.proposals.last.evidence.single.kind,
        'personalRecollection',
      );
      expect(find.text('Open editor'), findsOneWidget);
      controller.dispose();
    },
  );

  testWidgets(
    'invalid amount preserves typed source and does not save a proposal',
    (tester) async {
      final controller = await showEditor(tester);
      final before = controller.projects.first.proposals.length;
      final sourceField = find.byKey(const ValueKey('update-source'));
      final titleField = find.byKey(const ValueKey('update-title'));
      final amountField = find.byKey(const ValueKey('update-amount'));
      await tester.scrollUntilVisible(
        sourceField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(sourceField, 'Keep this source intact.');
      await tester.scrollUntilVisible(
        titleField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(titleField, 'A changed title');
      await tester.scrollUntilVisible(
        amountField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(amountField, '1,200.00');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('update-reviewed')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      final save = find.text('Save proposed change');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(controller.projects.first.proposals, hasLength(before));
      expect(
        find.text(
          'Use a non-negative amount, with at most two decimal places.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        sourceField,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      final source = tester.widget<TextFormField>(sourceField);
      expect(source.controller!.text, 'Keep this source intact.');
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
  testWidgets('switching items refreshes the displayed currency', (
    tester,
  ) async {
    final controller = await showEditor(tester);
    await tester.tap(find.byKey(const ValueKey('update-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send the final brand assets').last);
    await tester.pumpAndSettle();
    final currency = find.byKey(
      const ValueKey('update-currency-sample-assets'),
    );
    await tester.scrollUntilVisible(
      currency,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.state<FormFieldState<String>>(currency).value, 'USD');
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets(
    'an unsupported restored currency is preserved and cannot become USD',
    (tester) async {
      final json = createDemoWorkspace().toJson();
      final first = (json['projects'] as List).first as Map<String, dynamic>;
      ((first['currentRevision'] as Map)['items'] as List).first['currency'] =
          'JPY';
      final workspace = RecallWorkspace.fromJson(json);
      final controller = await showEditor(tester, workspace: workspace);
      final currency = find.byKey(
        const ValueKey('update-currency-sample-video'),
      );
      await tester.scrollUntilVisible(
        currency,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.state<FormFieldState<String>>(currency).value, 'JPY');
      final checkbox = find.byKey(const ValueKey('update-reviewed'));
      await tester.scrollUntilVisible(
        checkbox,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('update-save'));
      await tester.ensureVisible(save);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(controller.projects.first.items.first.currency, 'JPY');
      expect(controller.projects.first.items.first.amountMinor, 60000);
      expect(tester.takeException(), isNull);
      controller.dispose();
    },
  );
}
