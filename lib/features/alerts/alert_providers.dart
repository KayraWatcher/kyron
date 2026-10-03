import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/cache/cache_policy.dart';
import '../../core/providers/app_lifecycle_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../data/storage/alert_store.dart';
import '../../domain/alerts/alert_evaluator.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/entities/price_alert.dart';
import '../../domain/entities/quote.dart';
import 'notification_service.dart';

/// Kullanici alarmlari.
///
/// Ayni zamanda **izleyici** (watchdog) olarak da calisir: 30 saniyede bir
/// gorevli, alarm kosullarini gercek kaynak verisiyle degerlendirir ve
/// gerektiginde yerel bildirim gonderir. Sunucu tarafli zamanlama yoktur.
final alertsProvider =
    NotifierProvider<AlertsNotifier, List<PriceAlert>>(AlertsNotifier.new);

/// Bildirim izni durumu (ilk acilista bir kez istenir).
final notificationPermissionProvider =
    FutureProvider<bool>((ref) async => NotificationService.requestPermission());

class AlertsNotifier extends Notifier<List<PriceAlert>> {
  Timer? _timer;
  bool _busy = false;
  bool _started = false;

  /// Gorulen haber kimlikleri - ayni haber iki kez bildirilmez.
  ///
  /// **Kalici** (SharedPreferences): uygulama her acilisinda sifirlanirsa
  /// akistaki eski haberler yeniden bildirilirdi (bkz. [AlertStore.seenKey]).
  final Set<String> _seenNews = <String>{};

  @override
  List<PriceAlert> build() {
    // Depolama erisilemezse uygulama yine de calisir; liste bos baslar.
    SharedPreferences? prefs;
    try {
      prefs = ref.read(sharedPreferencesProvider);
    } catch (_) {
      prefs = null;
    }

    final loaded = AlertStore.read(prefs);
    final initial = loaded ?? const <PriceAlert>[];

    // Onceki oturumda gorulen haberler: ayni haber uygulama yeniden
    // acildiginda tekrar bildirilmez.
    _seenNews
      ..clear()
      ..addAll(AlertStore.readSeenNews(prefs));

    // Bildirim servisi - hata firlatmaz.
    unawaited(NotificationService.init());

    // One donuldugunde zamanlayiciyi beklemeden alarm degerlendirmesi:
    // Android arka planda zamanlayiciyi kisitladigi icin kullanici
    // uygulamaya dondugunde kosullar saatlerce degerlendirilmemis olabilir.
    ref.listen<bool>(appInForegroundProvider, (bool? prev, bool next) {
      if (next && prev == false) unawaited(evaluateNow());
    });

    if (!_started) {
      _started = true;
      _timer = Timer.periodic(CachePolicy.alertEvaluationInterval, (_) {
        // Arka planda ag isteği yok (pil + saglayici istek butcesi);
        // one donuldugunde listener yukarida hemen degerlendirir.
        if (!ref.read(appInForegroundProvider)) return;
        unawaited(evaluateNow());
      });
      ref.onDispose(() => _timer?.cancel());
    }

    return initial;
  }

  // ---------------------------------------------------------------------------
  // Tanim islemleri
  // ---------------------------------------------------------------------------

  Future<void> add(PriceAlert alert) async {
    if (!alert.isValid) return;
    final next = [...state, alert];
    state = next;
    await _persist(next);
    unawaited(evaluateNow());
  }

  Future<void> remove(String id) async {
    final next = state.where((a) => a.id != id).toList();
    state = next;
    await _persist(next);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final next = [
      for (final a in state)
        if (a.id == id) a.copyWith(enabled: enabled) else a,
    ];
    state = next;
    await _persist(next);
  }

  Future<void> acknowledge(String id) async {
    final next = [
      for (final a in state)
        if (a.id == id)
          a.copyWith(clearTriggered: true)
        else
          a,
    ];
    state = next;
    await _persist(next);
  }

  Future<void> removeAll() async {
    state = const [];
    await _persist(const []);
    await NotificationService.cancelAll();
  }

  /// Belirli bir varliga bagli alarm sayisi (rozet icin).
  int countFor(String assetId) =>
      state.where((a) => a.assetId == assetId).length;

  // ---------------------------------------------------------------------------
  // Izleyici
  // ---------------------------------------------------------------------------

  /// Tum gorevli alarmlari degerlendirir. Yan etkisiz; hata firlatmaz.
  Future<void> evaluateNow() async {
    if (_busy) return;
    _busy = true;
    try {
      final armed = state.where((a) => a.isArmed).toList();
      if (armed.isEmpty) return;

      final ids = <String>{
        for (final a in armed)
          if (a.assetId != null && a.assetId!.isNotEmpty) a.assetId!,
      };

      // 1) Fiyat alarlari icin tek toplu sorgu.
      var quotes = const <String, Quote>{};
      if (ids.isNotEmpty) {
        final repo = ref.read(marketRepositoryProvider);
        final res = await repo.getQuotes(ids.toList());
        if (!ref.mounted) return;
        quotes = res.dataOrNull ?? const {};
      }

      // 2) Onemli haber alarlari icin tek haber sorgusu.
      var news = const <NewsItem>[];
      final wantsNews = armed.any((a) => a.type == AlertType.importantNews);
      if (wantsNews) {
        final repo = ref.read(newsRepositoryProvider);
        final res = await repo.getBreakingNews(limit: 20);
        if (!ref.mounted) return;
        news = res.dataOrNull ?? const [];
      }

      if (!ref.mounted) return;

      final updated = <PriceAlert>[];
      var changed = false;

      for (final a in state) {
        var next = a;
        if (!a.isArmed) {
          updated.add(next);
          continue;
        }

        if (a.type == AlertType.importantNews) {
          // Ilk degerlendirmede eskiden haberlere bildirim gitmez: yalnizca
          // goruldu olarak isaretlenir. Boylece alarm ekleyen kullanici,
          // mevcut haberler icin aninda spam almaz.
          final firstRun = a.triggeredAt == null;

          var next = a;
          if (firstRun && news.isNotEmpty) {
            _markSeen(news, a.newsCategory);
            next = a.copyWith(triggeredAt: DateTime.now());
            changed = true;
          } else if (!firstRun) {
            final ev = AlertEvaluator.evaluateNews(
              alert: a,
              items: news,
              seenNewsIds: _seenNews,
            );
            if (ev.fire) {
              _markSeen(news, a.newsCategory);
              await _notify(a, ev.message);
              next = a.copyWith(triggeredAt: DateTime.now());
              changed = true;
            }
          }
          updated.add(next);
          continue;
        }

        // Tekrarli alarmda kosul saglanmazsa bayrak sifirlanir ki
        // kosul yeniden saglandiginda tekrar bildirilsin.
        final q = quotes[a.assetId];
        if (next.repeat &&
            next.triggeredAt != null &&
            !AlertEvaluator.conditionMet(next, q)) {
          next = next.copyWith(clearTriggered: true);
          changed = true;
        }

        final ev = AlertEvaluator.evaluate(next, q);
        if (ev.fire) {
          next = next.copyWith(triggeredAt: DateTime.now());
          changed = true;
          if (!next.repeat) {
            // Tek seferlik alarm kapanir; kullanici isterse yeniden acar.
            next = next.copyWith(enabled: false);
          }
          await _notify(next, ev.message);
        }
        updated.add(next);
      }

      if (changed) {
        state = updated;
        await _persist(updated);
      }
    } catch (e) {
      // Izleyici hatasi uygulamayi dusurmek zorunda degil; yutulur.
    } finally {
      _busy = false;
    }
  }

  /// Kategoriye uyan gorulmemis haberleri goruldu olarak isaretler.
  ///
  /// Yeni kimlik varsa **kalici** yapilir; bellek tercihi asmasin diye
  /// [AlertStore.maxSeenNews] sinirinda tutulur.
  void _markSeen(List<NewsItem> news, String? category) {
    var added = false;
    for (final item in news) {
      final matches = category == null ||
          category.isEmpty ||
          item.category.name == category ||
          item.category.label == category;
      if (matches && _seenNews.add(item.id)) added = true;
    }
    if (!added) return;

    if (_seenNews.length > AlertStore.maxSeenNews) {
      final trimmed = _seenNews.toList()
        ..removeRange(0, _seenNews.length - AlertStore.maxSeenNews);
      _seenNews
        ..clear()
        ..addAll(trimmed);
    }

    SharedPreferences? prefs;
    try {
      prefs = ref.read(sharedPreferencesProvider);
    } catch (_) {
      prefs = null;
    }
    unawaited(AlertStore.writeSeenNews(prefs, _seenNews));
  }

  Future<void> _notify(PriceAlert alert, String message) async {
    final name = _assetName(alert.assetId);
    final title = alert.type == AlertType.importantNews
        ? 'Önemli haber'
        : 'Alarm · $name';
    await NotificationService.show(
      id: NotificationService.idFor(alert.id),
      title: title,
      body: message,
      payload: alert.assetId ?? 'news',
    );
  }

  String _assetName(String? assetId) {
    if (assetId == null || assetId.isEmpty) return 'GOLD';
    final d = AssetCatalog.byId(assetId);
    return d?.name ?? assetId;
  }

  Future<void> _persist(List<PriceAlert> list) async {
    SharedPreferences? prefs;
    try {
      prefs = ref.read(sharedPreferencesProvider);
    } catch (_) {
      prefs = null;
    }
    await AlertStore.write(prefs, list);
  }
}

/// Sistem bildirim ayari acik mi? (istek uzerine)
final notificationsEnabledProvider = FutureProvider<bool>(
  (ref) => NotificationService.permissionsGranted(),
);
