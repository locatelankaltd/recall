import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/recall_cloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unconfigured and private-key builds cannot initialize a cloud client',
    () async {
      final cloud = await RecallCloud.initialize(
        config: const RecallCloudConfig(url: '', anonKey: ''),
      );
      expect(cloud.client, isNull);
      expect(cloud.projects, isNull);
      expect(cloud.reviews, isNull);
      expect(cloud.session.configured, isFalse);
      cloud.session.dispose();
      expect(
        const RecallCloudConfig(
          url: 'https://example.supabase.co',
          anonKey: 'sb_secret_private',
        ).validationError,
        contains('public client key'),
      );
      final payload = base64Url.encode(
        utf8.encode(jsonEncode({'role': 'service_role'})),
      );
      expect(
        RecallCloudConfig(
          url: 'https://example.supabase.co',
          anonKey: 'header.$payload.signature',
        ).validationError,
        contains('public client key'),
      );
      expect(
        const RecallCloudConfig(
          url: 'http://public.example',
          anonKey: 'sb_publishable_public',
        ).validationError,
        contains('secure connection'),
      );
    },
  );
  test(
    'session and PKCE storage isolate environments and remove persisted credentials',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = SecureRecallAuthStorage(namespace: 'one');
      final second = SecureRecallAuthStorage(namespace: 'two');
      await first.initialize();
      await first.persistSession('session-one');
      expect(await first.hasAccessToken(), isTrue);
      expect(await second.accessToken(), isNull);
      final pkce = SecureRecallPkceStorage(namespace: 'one');
      await pkce.setItem(key: 'verifier', value: 'private-verifier');
      expect(await first.accessToken(), 'session-one');
      await first.removePersistedSession();
      expect(await first.hasAccessToken(), isFalse);
      expect(await pkce.getItem(key: 'verifier'), 'private-verifier');
      await pkce.removeItem(key: 'verifier');
      expect(await pkce.getItem(key: 'verifier'), isNull);
    },
  );
}
