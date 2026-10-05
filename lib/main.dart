import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/cache/cache_policy.dart';
import 'core/providers/app_lifecycle_provider.dart';
import 'core/providers/app_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/update/update.dart';
import 'features/alerts/notification_service.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/home/home_screen.dart';
import 'features/markets/markets_screen.dart';
import 'features/news/news_screen.dart';
import 'features/portfolio/portfolio_screen.dart';
import 'shared/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Onbellek/zamanlayici politikasi tutarliligi (yalnizca debug'da assert).
  CachePolicy.ensureValid();

  // Yukleme hatasi uygulamayi durdurmaz; provider uyarisi gosterilir.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null;
  }

  runApp(
    ProviderScope(
      overrides: [
        if (prefs != null)
          sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const GoldApp(),
    ),
  );

  // Bildirim izni: alarm ozelligi Android 13+ icin acik izin ister.
  // Hata firlatmaz - izin verilmezse uygulama normal calisir, yalnizca
  // bildirim gozukmez.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await NotificationService.init();
    await NotificationService.requestPermission();
  });
}

/// KYRON uygulama kok widget'i.
class GoldApp extends ConsumerWidget {
  const GoldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'KYRON',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Hayat dongusu: zamanlayicilar arka planda durur, one donunce
      // hemen bir kez yenilenir (bkz. appInForegroundProvider).
      home: AppLifecycleBinder(
        child: UpdateChecker(child: const GoldHome()),
      ),
    );
  }
}

/// 5 bolumlu ana kabuk.
class GoldHome extends ConsumerWidget {
  const GoldHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AppShell(
      children: [
        HomeScreen(),
        MarketsScreen(),
        PortfolioScreen(),
        NewsScreen(),
        CalendarScreen(),
      ],
    );
  }
}
