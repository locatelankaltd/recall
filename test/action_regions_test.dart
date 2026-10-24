import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/data/recall_controller.dart';
import 'package:recall_next/design/design.dart';
import 'package:recall_next/main.dart';
import 'package:recall_next/ui/project_detail.dart';
import 'package:recall_next/ui/update_editor.dart';
import 'package:recall_next/ui/widgets.dart';

void main() {
  Future<RecallController> openDemo(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = RecallController(repository: MemoryRecallRepository());
    await controller.initialize();
    await controller.loadDemo();
    await tester.pumpWidget(RecallApp(controller: controller));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    return controller;
  }

  for (final layout in [(390.0, 1.0), (320.0, 1.8), (1365.0, 1.0)]) {
    testWidgets(
      'reserved actions do not cover content at ${layout.$1}px and ${layout.$2} text scale',
      (tester) async {
        await openDemo(tester, width: layout.$1, scale: layout.$2);
        await tester.scrollUntilVisible(find.text('Awaiting answers'), 150);
        expect(find.text('Awaiting answers'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
        final shellRegion = tester.getRect(
          find.byKey(const ValueKey('shell-action-region')),
        );
        final body = tester.getRect(find.byType(PageBody));
        expect(body.bottom, lessThanOrEqualTo(shellRegion.top));
        expect(shellRegion.width, lessThanOrEqualTo(860));
        expect(shellRegion.center.dx, closeTo(layout.$1 / 2, .1));
        expect(
          tester
              .getRect(find.byKey(const ValueKey('shell-primary-action')))
              .height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.text('Projects').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Launch films').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Launch films').first);
        await tester.pumpAndSettle();
        expect(find.byType(ProjectDetail), findsOneWidget);
        final projectRegion = tester.getRect(
          find.byKey(const ValueKey('project-action-region')),
        );
        expect(
          tester.getRect(find.byType(PageBody)).bottom,
          lessThanOrEqualTo(projectRegion.top),
        );
        expect(projectRegion.width, lessThanOrEqualTo(860));
        expect(projectRegion.center.dx, closeTo(layout.$1 / 2, .1));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('project-primary-action')));
        await tester.pumpAndSettle();
        expect(find.byType(UpdateEditor), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('correction dialog can close during its exit animation', (
    tester,
  ) async {
    final controller = await openDemo(tester);
    final project = controller.projects.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: RecallTheme.light,
        home: RevisionPage(
          controller: controller,
          projectId: project.id,
          revisionId: project.proposals.first.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Request a correction'), 300);
    await tester.tap(find.text('Request a correction'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Keep my note until dismissed.',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'missing saved recording shows a clear error and keeps its source',
    (tester) async {
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            paths,
            (_) async => '/recall-test-documents',
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(paths, null);
      });
      final source = Evidence(
        id: 'saved-debrief',
        text: 'The written debrief remains available.',
        language: 'en',
        kind: 'personalRecollection',
        createdAt: DateTime(2026, 10, 24),
        attachmentPath: '/unavailable/restored-recording.m4a',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: RecallTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSource(context, source, 'Client work'),
                child: const Text('Open source'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open source'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('export-source-recording')));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This recording is unavailable.'),
        findsOneWidget,
      );
      expect(find.text(source.text), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
