import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme.dart';
import 'data/db.dart';
import 'screens/home_shell.dart';
import 'screens/lock_screen.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await AppSettings.load();
  await AppFiles.init();
  await Db.i.db;
  try {
    await Notifier.init();
  } catch (_) {}

  Timer? debounce;
  Db.i.addListener(() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 1), Notifier.rescheduleAll);
  });
  unawaited(Notifier.rescheduleAll());

  runApp(const AgendaApp());
}

class AgendaApp extends StatelessWidget {
  const AgendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'أجندة المحامي القانونية',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        builder: (context, child) => LockGate(child: child ?? const SizedBox.shrink()),
        home: const HomeShell(),
      ),
    );
  }
}
