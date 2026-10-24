import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/recall_controller.dart';
import 'design/recall_theme.dart';
import 'ui/app_shell.dart';

class RecallApp extends StatelessWidget {
  const RecallApp({
    super.key,
    required this.controller,
    this.navigatorKey,
    this.home,
  });
  final RecallController controller;
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget? home;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Recall',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: RecallTheme.light,
      darkTheme: RecallTheme.dark,
      themeMode: ThemeMode.system,
      locale: Locale(controller.locale),
      supportedLocales: const [Locale('en'), Locale('es'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home ?? RecallShell(controller: controller),
    ),
  );
}
