import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:recall_next/cloud/cloud_gateway.dart';
import 'package:recall_next/cloud/source_analysis.dart';
import 'package:recall_next/data/recall_controller.dart';
import 'package:recall_next/design/recall_theme.dart';
import 'package:recall_next/domain/agreement_engine.dart';
import 'package:recall_next/l10n/strings.dart';
import 'package:recall_next/ui/update_editor.dart';

const sourceText =
    'Please change the total fee to EUR 850. The delivery date needs clarification.';
String english(String key) => strings['en']?[key] ?? key;

class EditorCloudGateway implements CloudProjectGateway {
  EditorCloudGateway(this.project);
  final Project project;
  final mutations = <String>[];
  @override
  Future<List<Project>> fetchProjects() async => [project];
  @override
  Future<Project> createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  }) async => throw StateError('AI review must not create a project.');
  @override
  Future<Project?> mutateProject({
    required String projectId,
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    mutations.add(action);
    throw StateError('AI review must not mutate an agreement.');
  }
}

class EditorSourceTransport implements SourceAiTransport {
  EditorSourceTransport({this.clarification = false});
  final bool clarification;
  final calls = <({String function, Object body})>[];
  @override
  String? get userId => '11111111-1111-1111-1111-111111111111';
  @override
  Future<Object?> invoke(
    String function, {
    required Object body,
    List<http.MultipartFile>? files,
    Future<void>? abortSignal,
  }) async {
    calls.add((function: function, body: body));
    final item = ((body as Map)['current_items'] as List).single as Map;
    return {
      'status': 'review_required',
      'suggestions': [
        {
          'item_id': item['id'],
          'intent': clarification ? 'unclear' : 'request',
          'needs_clarification': clarification,
          'proposed_value': clarification ? null : 'EUR 850',
          'source_quote': sourceText,
          'question': clarification
              ? 'Which delivery date should be proposed?'
              : null,
        },
      ],
      'warnings': ['aiDraftNote'],
    };
  }
}

class EditorHarness {
  const EditorHarness(this.controller, this.gateway, this.transport);
  final RecallController controller;
  final EditorCloudGateway gateway;
  final EditorSourceTransport transport;
}

Future<EditorHarness> showEditor(
  WidgetTester tester, {
  bool clarification = false,
}) async {
  final engine = AgreementEngine();
  final project = engine.addItem(
    engine.createProject(title: 'Account project', clientName: 'Sam'),
    const PlanItem(
      id: 'item-ai',
      title: 'Original scope',
      details: 'Original details',
      amountMinor: 10000,
      currency: 'EUR',
    ),
  );
  final gateway = EditorCloudGateway(project);
  final controller = RecallController(cloudGateway: gateway);
  await controller.initialize();
  final transport = EditorSourceTransport(clarification: clarification);
  await tester.pumpWidget(
    MaterialApp(
      theme: RecallTheme.light,
      home: UpdateEditor(
        controller: controller,
        projectId: project.id,
        initialSourceText: sourceText,
        sourceAnalysisClient: SourceAnalysisClient(transport: transport),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return EditorHarness(controller, gateway, transport);
}

Future<void> showField(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final scroll = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    200,
    scrollable: scroll,
  );
  await tester.pumpAndSettle();
}

Future<String> fieldText(WidgetTester tester, String key) async {
  await showField(tester, key);
  return tester
      .widget<TextFormField>(find.byKey(ValueKey(key)))
      .controller!
      .text;
}

Future<void> startAnalysis(WidgetTester tester) async {
  await showField(tester, 'analyze-source');
  await tester.tap(find.byKey(const ValueKey('analyze-source')));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> approveAnalysis(WidgetTester tester) async {
  await startAnalysis(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(english('aiSendText')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cancelling AI consent sends nothing and preserves the source and plan',
    (tester) async {
      final harness = await showEditor(tester);
      final before = harness.controller.exportJson;
      await startAnalysis(tester);
      expect(harness.transport.calls, isEmpty);
      expect(find.text(sourceText), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(english('cancel')),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.transport.calls, isEmpty);
      expect(await fieldText(tester, 'update-source'), sourceText);
      expect(await fieldText(tester, 'update-title'), 'Original scope');
      expect(await fieldText(tester, 'update-amount'), '100.00');
      expect(harness.gateway.mutations, isEmpty);
      expect(harness.controller.exportJson, before);
      await tester.pumpWidget(const SizedBox());
      harness.controller.dispose();
    },
  );

  testWidgets(
    'approved analysis shows verbatim drafts without changing typed form values or agreements',
    (tester) async {
      final harness = await showEditor(tester);
      final before = harness.controller.exportJson;
      await showField(tester, 'update-title');
      await tester.enterText(
        find.byKey(const ValueKey('update-title')),
        'My unsaved title',
      );
      await showField(tester, 'update-amount');
      await tester.enterText(
        find.byKey(const ValueKey('update-amount')),
        '987.65',
      );
      await approveAnalysis(tester);
      expect(harness.transport.calls, hasLength(1));
      expect(harness.transport.calls.single.function, 'analyze-source');
      final sent = harness.transport.calls.single.body as Map;
      expect(sent['consent'], true);
      expect(sent['source_text'], sourceText);
      final selected = (sent['current_items'] as List).single as Map;
      expect(selected['id'], 'item-ai');
      expect(selected['value'], contains('EUR 100.00'));
      expect(selected['value'], isNot(contains('987.65')));
      await showField(tester, 'analyze-source');
      await tester.scrollUntilVisible(
        find.text(english('aiDraftTitle')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(english('aiDraftTitle')), findsOneWidget);
      expect(find.text('EUR 850'), findsOneWidget);
      expect(find.text(english('aiSourceQuote')), findsOneWidget);
      expect(await fieldText(tester, 'update-source'), sourceText);
      expect(await fieldText(tester, 'update-title'), 'My unsaved title');
      expect(await fieldText(tester, 'update-amount'), '987.65');
      await showField(tester, 'update-reviewed');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('update-reviewed')),
            )
            .value,
        false,
      );
      expect(harness.gateway.mutations, isEmpty);
      expect(harness.controller.exportJson, before);
      await tester.pumpWidget(const SizedBox());
      harness.controller.dispose();
    },
  );

  testWidgets(
    'unclear analysis shows a question while leaving amount and source untouched',
    (tester) async {
      final harness = await showEditor(tester, clarification: true);
      final before = harness.controller.exportJson;
      await approveAnalysis(tester);
      await showField(tester, 'analyze-source');
      await tester.scrollUntilVisible(
        find.text('Which delivery date should be proposed?'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Which delivery date should be proposed?'),
        findsOneWidget,
      );
      expect(find.text(english('aiQuestion')), findsOneWidget);
      expect(find.text('EUR 850'), findsNothing);
      expect(await fieldText(tester, 'update-source'), sourceText);
      expect(await fieldText(tester, 'update-amount'), '100.00');
      expect(harness.gateway.mutations, isEmpty);
      expect(harness.controller.exportJson, before);
      await tester.pumpWidget(const SizedBox());
      harness.controller.dispose();
    },
  );

  testWidgets(
    'editing source clears stale drafts without rerunning AI or mutating an agreement',
    (tester) async {
      final harness = await showEditor(tester);
      final before = harness.controller.exportJson;
      await approveAnalysis(tester);
      await showField(tester, 'analyze-source');
      await tester.scrollUntilVisible(
        find.text(english('aiDraftTitle')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(english('aiDraftTitle')), findsOneWidget);
      await showField(tester, 'update-source');
      await tester.enterText(
        find.byKey(const ValueKey('update-source')),
        'A different request needs fresh analysis.',
      );
      await tester.pumpAndSettle();
      expect(find.text(english('aiDraftTitle')), findsNothing);
      expect(find.text('EUR 850'), findsNothing);
      expect(harness.transport.calls, hasLength(1));
      expect(harness.gateway.mutations, isEmpty);
      expect(harness.controller.exportJson, before);
      await tester.pumpWidget(const SizedBox());
      harness.controller.dispose();
    },
  );
}
