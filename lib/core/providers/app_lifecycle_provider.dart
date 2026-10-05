import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';
import '../update/update_notifier.dart';
import '../update/update.dart';

/// Uygulama su an **on planda** mi?
///
/// Neden gerekli:
///  * Zamanlayicilar arka planda da calisir ve gereksiz API istegi atar
///    (pil + saglayici istek butcesi + gereksiz ag trafigi).
///  * One donuldugunde ekrandaki fiyat **bayat** kalmistir; kullanici
///    uygulamayi acar acmaz taze veri gormek ister.
///
/// Bu nedenle tum periyodik zamanlayicilar bu degeri okur:
///
///     if (!ref.read(appInForegroundProvider)) return;   // arka planda atla
///
/// ve yeniden on plana donuldugunde **bir kez** hemen yenileme yapilir.
///
/// Durum [AppLifecycleBinder] ile Android/iOS hayat dongusunden gelir;
/// hicbir izin (notifications/alarm) gerektirmez.
final appInForegroundProvider =
    NotifierProvider<ForegroundNotifier, bool>(ForegroundNotifier.new);

class ForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool foreground) {
    if (state == foreground) return;
    state = foreground;
  }
}

/// Hayat dongusunu [appInForegroundProvider]'a yazan kok widget'i.
///
/// `ref.read` ile yazar; yani yalnizca **bu degere abone olan** (zamanlayici
/// vb.) parcalar etkilenir, tam ekran yeniden kurulmaz.
class AppLifecycleBinder extends ConsumerStatefulWidget {
  const AppLifecycleBinder({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleBinder> createState() => _AppLifecycleBinderState();
}

class _AppLifecycleBinderState extends ConsumerState<AppLifecycleBinder>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Anonim telemetri (FAZ 6): UI acilisini ASLA beklemez; servis tum
    // hatalari yutar. Yapilandirma yoksa tamamen pasiftir.
    Future.microtask(_telemetryPing);

    // App update check (FAZ 17): config'i arka planda cek, UI'yi bloklama.
    // Zorunlu update sonucu gelirse UpdateChecker dialog/ekrani gosterir.
    Future.microtask(_checkForUpdates);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    final wasForeground = ref.read(appInForegroundProvider);
    ref.read(appInForegroundProvider.notifier).set(resumed);
    if (resumed && !wasForeground) {
      // One donus: last_seen guncellenir; event/throttle karari serviste.
      unawaited(_telemetryPing());
    }
  }

  /// Telemetri ping'i: arka planda, hata yutulu (asla rethrow etmez).
  Future<void> _telemetryPing() async {
    try {
      await ref.read(telemetryProvider).trackAppOpen();
    } catch (_) {
      // Telemetri uygulamayi asla etkilemez.
    }
  }

  /// App update check: config'i arka planda cek, sonuca gore UI goster.
  Future<void> _checkForUpdates() async {
    try {
      await ref.read(updateNotifierProvider.notifier).checkForUpdates();
      // Sonuc UpdateChecker widget'i tarafindan islenecek.
    } catch (_) {
      // Update check hatasi uygulamayi etkilemez.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
