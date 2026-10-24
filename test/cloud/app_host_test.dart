import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/app_host.dart';
import 'package:recall_next/cloud/recall_cloud.dart';
import 'package:recall_next/data/recall_controller.dart';
import 'package:recall_next/domain/agreement_engine.dart';
import 'package:recall_next/platform/incoming_share_service.dart';
import 'package:recall_next/ui/account_page.dart';
import 'package:recall_next/ui/app_shell.dart';

class HostAuth implements RecallAuthProvider {
  RecallAccount? account;
  final events = StreamController<RecallAuthEvent>.broadcast(sync: true);
  @override
  RecallAccount? get currentAccount => account;
  @override
  Stream<RecallAuthEvent> get changes => events.stream;
  void emit(String? id, {bool recovery = false}) {
    account = id == null
        ? null
        : RecallAccount(id: id, email: '$id@example.com', emailVerified: true);
    events.add(RecallAuthEvent(account, passwordRecovery: recovery));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HostProjects implements CloudProjectGateway {
  HostProjects(this.auth, this.byOwner);
  final HostAuth auth;
  final Map<String, Project> byOwner;
  final fetchedOwners = <String>[];
  int createCalls = 0;
  int mutationCalls = 0;
  @override
  Future<List<Project>> fetchProjects() async {
    final owner = auth.account!.id;
    fetchedOwners.add(owner);
    return [byOwner[owner]!];
  }

  @override
  Future<Project> createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  }) async {
    createCalls++;
    throw UnimplementedError();
  }

  @override
  Future<Project?> mutateProject({
    required String projectId,
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    mutationCalls++;
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = AgreementEngine();
  final privateProject = engine.createProject(
    title: 'Private device project',
    clientName: 'Local client',
  );
  final projectA = engine.createProject(
    title: 'Account A project',
    clientName: 'Client A',
  );
  final projectB = engine.createProject(
    title: 'Account B project',
    clientName: 'Client B',
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  Future<
    ({
      HostAuth auth,
      HostProjects gateway,
      RecallSessionManager session,
      RecallController local,
    })
  >
  start(WidgetTester tester) async {
    final auth = HostAuth()..emit('account-a');
    final session = RecallSessionManager(provider: auth);
    final gateway = HostProjects(auth, {
      'account-a': projectA,
      'account-b': projectB,
    });
    final repository = MemoryRecallRepository();
    await repository.save(RecallWorkspace(projects: [privateProject]));
    final local = RecallController(repository: repository);
    final cloud = RecallCloud.forTesting(session: session, projects: gateway);
    await tester.pumpWidget(
      RecallHost(
        cloud: cloud,
        localController: local,
        shareService: IncomingShareService(platformSupported: false),
      ),
    );
    await tester.pumpAndSettle();
    return (auth: auth, gateway: gateway, session: session, local: local);
  }

  RecallController active(WidgetTester tester) =>
      tester.widget<RecallShell>(find.byType(RecallShell)).controller;

  testWidgets(
    'switching accounts removes previous routes and loads only the new account',
    (tester) async {
      final fixture = await start(tester);
      expect(active(tester).projects.single.id, projectA.id);
      final context = tester.element(find.byType(RecallShell));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Private account A route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private account A route'), findsOneWidget);
      fixture.auth.emit('account-b');
      await tester.pumpAndSettle();
      expect(find.text('Private account A route'), findsNothing);
      expect(active(tester).projects.single.id, projectB.id);
      expect(active(tester).projects.any((p) => p.id == projectA.id), isFalse);
      expect(fixture.local.projects.single.id, privateProject.id);
      expect(fixture.gateway.fetchedOwners, ['account-a', 'account-b']);
      expect(fixture.gateway.createCalls, 0);
      expect(fixture.gateway.mutationCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.session.dispose();
      await fixture.auth.events.close();
    },
  );

  testWidgets(
    'sign out restores device workspace without uploading its projects',
    (tester) async {
      final fixture = await start(tester);
      fixture.auth.emit(null);
      await tester.pumpAndSettle();
      expect(identical(active(tester), fixture.local), isTrue);
      expect(active(tester).isCloud, isFalse);
      expect(active(tester).projects.single.id, privateProject.id);
      expect(fixture.gateway.createCalls, 0);
      expect(fixture.gateway.mutationCalls, 0);
      expect(fixture.session.deletedUserId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.session.dispose();
      await fixture.auth.events.close();
    },
  );

  testWidgets('password recovery event opens the password update screen', (
    tester,
  ) async {
    final fixture = await start(tester);
    fixture.auth.emit('account-a', recovery: true);
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.text('Choose a new password.'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('Update password'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.session.dispose();
    await fixture.auth.events.close();
  });
}
