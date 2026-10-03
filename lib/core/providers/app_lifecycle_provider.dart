import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appInForegroundProvider.notifier).set(
          state == AppLifecycleState.resumed,
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
