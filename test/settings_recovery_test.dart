import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/data/recall_controller.dart';
import 'package:recall_next/design/design.dart';
import 'package:recall_next/ui/settings_page.dart';

class _FailingRepository extends MemoryRecallRepository {
  bool failWrites = false;

  @override
  Future<void> save(RecallWorkspace workspace) async {
    if (failWrites) throw StateError('Storage is unavailable');
    await super.save(workspace);
  }
}

void main() {
  testWidgets('failed delete keeps Settings open and retains the workspace', (
    tester,
  ) async {
    final repository = _FailingRepository();
    final controller = RecallController(repository: repository);
    await controller.initialize();
    await controller.createProject(
      title: 'Client work',
      clientName: 'Marta',
      category: 'Design',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: RecallTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(controller: controller),
                ),
              ),
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Delete local workspace'), 350);
    await tester.tap(find.text('Delete local workspace'));
    await tester.pumpAndSettle();
    repository.failWrites = true;
    await tester.tap(find.text('Delete local data'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.textContaining('Storage is unavailable'), findsOneWidget);
    expect(controller.projects.single.title, 'Client work');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
