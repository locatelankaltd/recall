import 'package:flutter/widgets.dart';
import 'app_host.dart';
import 'cloud/recall_cloud.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cloud = await RecallCloud.initialize();
  runApp(RecallHost(cloud: cloud));
}
