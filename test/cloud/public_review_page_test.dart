import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/cloud_gateway.dart';
import 'package:recall_next/cloud/public_review_page.dart';
import 'package:recall_next/design/recall_theme.dart';
import 'package:recall_next/domain/recall_models.dart';

class FakeReviews implements CloudReviewGateway {
  PublicReview? review;
  CloudException? failure;
  int fetches = 0;
  final responses = <String>[];
  @override
  Future<PublicReview> fetchReview(String token) async {
    fetches++;
    if (failure != null) throw failure!;
    return review!;
  }

  @override
  Future<ReviewReceipt> respond({
    required String token,
    required String action,
    String note = '',
  }) async {
    responses.add(action);
    return ReviewReceipt(
      receiptId: 'receipt-123',
      revisionId: 'revision-2',
      version: 2,
      action: action,
      status: 'confirmed',
      identity: 'link-holder',
    );
  }

  @override
  Future<ReviewLink> createLink({
    required String projectId,
    required String revisionId,
    required String participantId,
    List<String>? itemIds,
    int ttlSeconds = 604800,
  }) => throw UnimplementedError();
  @override
  Future<List<ReviewLink>> listLinks(String projectId) =>
      throw UnimplementedError();
  @override
  Future<void> revokeLink(String linkId) => throw UnimplementedError();
}

PublicReview review({
  bool canRespond = true,
  String status = 'proposed',
  Map<String, dynamic>? response,
  DateTime? previousDueDate,
  DateTime? proposedDueDate,
}) => PublicReview(
  projectTitle: 'Website redesign',
  participantName: 'Sam',
  revisionId: 'revision-2',
  version: 2,
  status: status,
  changes: [
    ReviewChange(
      itemId: 'item-1',
      previous: PlanItem(
        id: 'item-1',
        title: 'Old title',
        dueDate: previousDueDate,
      ),
      proposed: PlanItem(
        id: 'item-1',
        title: 'New title',
        dueDate: proposedDueDate,
      ),
    ),
  ],
  evidence: [
    Evidence(
      id: 'source-1',
      text: 'Could we update the homepage?',
      language: 'en',
      kind: 'originalText',
      createdAt: DateTime(2026, 10, 24),
    ),
  ],
  evidenceOmitted: false,
  canRespond: canRespond,
  identity: 'link-holder',
  response: response,
);

void main() {
  Future<void> open(WidgetTester tester, FakeReviews gateway) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: RecallTheme.light,
        home: PublicReviewPage(gateway: gateway, token: 'private-token'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'recipient sees bounded before/after and must acknowledge link holder identity',
    (tester) async {
      final gateway = FakeReviews()..review = review();
      await open(tester, gateway);
      expect(find.text('Old title'), findsOneWidget);
      expect(find.text('New title'), findsOneWidget);
      expect(find.textContaining('does not verify the person'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Confirm this version');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(gateway.responses, ['confirm']);
      expect(find.text('Confirmation recorded.'), findsOneWidget);
      expect(find.text('Receipt: receipt-123'), findsOneWidget);
      expect(find.text('Confirm this version'), findsNothing);
    },
  );
  testWidgets('stale review cannot submit a response', (tester) async {
    final gateway = FakeReviews()
      ..review = review(canRespond: false, status: 'stale');
    await open(tester, gateway);
    expect(find.text('This proposal is out of date.'), findsOneWidget);
    expect(find.text('Confirm this version'), findsNothing);
    expect(gateway.responses, isEmpty);
  });
  testWidgets('already recorded response shows the existing receipt', (
    tester,
  ) async {
    final gateway = FakeReviews()
      ..review = review(
        canRespond: false,
        response: {'receiptId': 'original-receipt', 'action': 'decline'},
      );
    await open(tester, gateway);
    expect(find.text('Decline recorded.'), findsOneWidget);
    expect(find.text('Receipt: original-receipt'), findsOneWidget);
    expect(gateway.responses, isEmpty);
  });
  testWidgets('unavailable links show no item details or response action', (
    tester,
  ) async {
    final gateway = FakeReviews()
      ..failure = const CloudException(
        'This review link is unavailable, expired, or revoked.',
      );
    await open(tester, gateway);
    expect(find.text('This review is unavailable.'), findsOneWidget);
    expect(find.text('Old title'), findsNothing);
    expect(find.text('Confirm this version'), findsNothing);
    expect(gateway.responses, isEmpty);
  });

  testWidgets(
    'recipient can switch French and Spanish without translating sources or submitting a response',
    (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final gateway = FakeReviews()
        ..review = review(
          previousDueDate: DateTime(2027, 3, 9),
          proposedDueDate: DateTime(2027, 3, 20),
        );
      const source = 'Could we update the homepage?';
      await open(tester, gateway);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm this version'),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();
      expect(find.text('Les modifications proposées'), findsOneWidget);
      expect(find.text('Échéance : 9 mars 2027'), findsOneWidget);
      expect(find.text('Échéance : 20 mars 2027'), findsOneWidget);
      expect(find.text(source), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmer cette version'),
            )
            .onPressed,
        isNull,
      );

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Español'));
      await tester.pumpAndSettle();
      expect(find.text('Los cambios propuestos'), findsOneWidget);
      expect(find.text('Entrega: 9 mar 2027'), findsOneWidget);
      expect(find.text('Entrega: 20 mar 2027'), findsOneWidget);
      expect(find.text(source), findsOneWidget);
      expect(find.text('Old title'), findsOneWidget);
      expect(find.text('New title'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirmar esta versión'),
            )
            .onPressed,
        isNull,
      );
      expect(gateway.fetches, 1);
      expect(gateway.responses, isEmpty);
      expect(gateway.review!.evidence.single.text, source);
    },
  );
}
