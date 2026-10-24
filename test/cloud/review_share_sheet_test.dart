import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/cloud_gateway.dart';
import 'package:recall_next/cloud/review_share_sheet.dart';
import 'package:recall_next/design/recall_theme.dart';
import 'package:recall_next/domain/agreement_engine.dart';
import 'package:recall_next/domain/recall_models.dart';

class OwnerReviews implements CloudReviewGateway {
  final createdScopes = <List<String>>[];
  final revoked = <String>[];
  final links = <ReviewLink>[];
  @override
  Future<List<ReviewLink>> listLinks(String projectId) async => List.of(links);
  @override
  Future<ReviewLink> createLink({
    required String projectId,
    required String revisionId,
    required String participantId,
    List<String>? itemIds,
    int ttlSeconds = 604800,
  }) async {
    expect(participantId, 'client');
    createdScopes.add(List.of(itemIds!));
    final link = ReviewLink(
      id: 'link-1',
      token: 'private-token',
      expires: DateTime.utc(2100),
      revisionId: revisionId,
      participantId: participantId,
      itemIds: itemIds,
    );
    links.add(link);
    return link;
  }

  @override
  Future<void> revokeLink(String linkId) async {
    revoked.add(linkId);
    links.clear();
  }

  @override
  Future<PublicReview> fetchReview(String token) => throw UnimplementedError();
  @override
  Future<ReviewReceipt> respond({
    required String token,
    required String action,
    String note = '',
  }) => throw UnimplementedError();
}

void main() {
  final engine = AgreementEngine();
  var project = engine.createProject(title: 'Website', clientName: 'Sam');
  project = engine.addItem(
    project,
    const PlanItem(id: 'item-1', title: 'Homepage'),
  );
  project = engine.addItem(
    project,
    const PlanItem(id: 'item-2', title: 'Contact page'),
  );
  project = engine.proposeChange(
    project,
    items: project.items
        .map((i) => i.copyWith(details: 'Revised scope'))
        .toList(),
    authorId: 'you',
    evidence: [
      Evidence(
        id: 'evidence-1',
        text: 'The requested change',
        language: 'en',
        kind: 'originalText',
        createdAt: DateTime(2026),
      ),
    ],
  );
  final revision = project.proposals.single;

  Future<void> open(
    WidgetTester tester,
    OwnerReviews gateway, {
    Uri? url,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: RecallTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showReviewSharing(
                context,
                gateway: gateway,
                project: project,
                revision: revision,
                applicationUrl: url,
              ),
              child: const Text('Open sharing'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sharing'));
    await tester.pumpAndSettle();
  }

  testWidgets('native builds without public URL never create unusable links', (
    tester,
  ) async {
    final gateway = OwnerReviews();
    await open(tester, gateway);
    final button = find.widgetWithText(
      FilledButton,
      'Create private review link',
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(gateway.createdScopes, isEmpty);
    expect(find.textContaining('public web address is needed'), findsOneWidget);
  });
  testWidgets(
    'owner explicitly chooses scope and can revoke the created bearer link',
    (tester) async {
      final gateway = OwnerReviews();
      await open(tester, gateway, url: Uri.parse('https://recall.example/'));
      expect(gateway.createdScopes, isEmpty);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Contact page'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create private review link'),
      );
      await tester.pumpAndSettle();
      expect(gateway.createdScopes, [
        ['item-1'],
      ]);
      expect(
        find.text('https://recall.example/#review=private-token'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
      await tester.pumpAndSettle();
      expect(gateway.revoked, ['link-1']);
      expect(
        find.text('https://recall.example/#review=private-token'),
        findsNothing,
      );
    },
  );
}
