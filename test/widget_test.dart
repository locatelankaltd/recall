import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/main.dart';
import 'package:recall_next/data/recall_controller.dart';

void main() {
  Future<RecallController> open(
    WidgetTester tester, {
    bool demo = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = RecallController(repository: MemoryRecallRepository());
    await controller.initialize();
    if (demo) await controller.loadDemo();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: RecallApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return controller;
  }

  testWidgets('first use is empty and fictional data is opt-in', (
    tester,
  ) async {
    final controller = await open(tester);
    expect(find.text('Create your first project'), findsOneWidget);
    expect(controller.projects, isEmpty);
    await tester.ensureVisible(find.text('Explore the example'));
    await tester.tap(find.text('Explore the example'));
    await tester.pumpAndSettle();
    expect(controller.isDemo, isTrue);
    expect(
      find.text('Fictional projects. Responses here are simulations.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending review does not replace the confirmed plan in navigation',
    (tester) async {
      final controller = await open(tester, demo: true);
      final project = controller.projects.first;
      final original = project.currentRevision.id;
      await tester.tap(find.text('Launch films').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Preview client review'), 350);
      expect(find.text('Preview client review'), findsOneWidget);
      expect(controller.projects.first.currentRevision.id, original);
      expect(find.text('Simulate client confirmation'), findsNothing);
      final preview = find.text('Preview client review');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Example only. This does not send a message or verify a person.',
        ),
        findsOneWidget,
      );
      final confirm = find.text('Simulate client confirmation');
      await tester.scrollUntilVisible(confirm, 350);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(controller.projects.first.currentRevision.id, isNot(original));
      expect(controller.projects.first.items.first.amountMinor, 85000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow and large-text layouts keep navigation accessible', (
    tester,
  ) async {
    await open(tester, demo: true, width: 320, scale: 1.8);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.text('Find a project'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
