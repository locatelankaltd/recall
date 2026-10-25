import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/recall_cloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unconfigured builds expose no Firebase-backed cloud success', () async {
    final cloud = await RecallCloud.initialize(
      config: const RecallCloudConfig(),
    );
    expect(cloud.client, isNull);
    expect(cloud.projects, isNull);
    expect(cloud.reviews, isNull);
    expect(cloud.session.configured, isFalse);
    cloud.session.dispose();
  });
  test(
    'Firebase config accepts public options and derives one project endpoint',
    () {
      const config = RecallCloudConfig(
        apiKey: 'AIzaTestPublicConfiguration',
        appId: '1:123456789:web:abcdef',
        projectId: 'recall-test',
        messagingSenderId: '123456789',
      );
      expect(config.validationError, isNull);
      expect(
        config.endpoint.toString(),
        'https://europe-west1-recall-test.cloudfunctions.net/recallApi',
      );
      expect(config.options.authDomain, 'recall-test.firebaseapp.com');
      expect(config.options.projectId, 'recall-test');
    },
  );
  test(
    'private credentials and insecure or token-bearing endpoints are rejected',
    () {
      RecallCloudConfig config(String key, String endpoint) =>
          RecallCloudConfig(
            apiKey: key,
            appId: '1:123456789:web:abcdef',
            projectId: 'recall-test',
            messagingSenderId: '123456789',
            apiUrl: endpoint,
          );
      expect(
        config(
          '-----BEGIN PRIVATE KEY-----',
          'https://recall.invalid/api',
        ).validationError,
        isNotNull,
      );
      expect(
        config('AIzaPublicKey', 'http://remote.example/api').validationError,
        contains('secure connection'),
      );
      expect(
        config(
          'AIzaPublicKey',
          'https://recall.invalid/api?token=private',
        ).validationError,
        isNotNull,
      );
      expect(
        config(
          'AIzaPublicKey',
          'http://localhost:5001/test/europe-west1/recallApi',
        ).validationError,
        isNull,
      );
    },
  );
}
