import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/anlik_altin_fiyatlari_provider.dart';
import '../../data/providers/news_rss_provider.dart';
import '../../data/providers/tcmb_currency_provider.dart';
import '../../data/providers/tcmb_fx_market_data_provider.dart';
import '../../data/providers/yahoo_finance_provider.dart';
import '../../data/providers/yahoo_market_data_provider.dart';
import '../../data/repositories/economic_calendar_repository_impl.dart';
import '../../data/repositories/market_data_repository_impl.dart';
import '../../data/repositories/news_repository_impl.dart';
import '../../domain/providers/economic_calendar_provider.dart';
import '../../domain/providers/market_data_provider.dart';
import '../../domain/repositories/economic_calendar_repository.dart';
import '../../domain/repositories/market_data_repository.dart';
import '../../domain/repositories/news_repository.dart';
import '../cache/cache_policy.dart';
import '../network/api_client.dart';
import '../telemetry/telemetry_service.dart';
import '../theme/app_theme.dart';

/// Tekil HTTP istemcisi.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Yerel tercihler (ayarlar, portfoy, alarmlar, takip listesi).
///
/// `main()` icinde `overrides` ile saglanir; saglanmazsa anlasilir bir
/// hata firlatilir.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider ProviderScope overrides ile saglanmalidir.',
  );
});

// ---------------------------------------------------------------------------
// DATA PROVIDERS (API'ye dogrudan baglanan tek katman)
// ---------------------------------------------------------------------------

final tcmbProvider = Provider<TcmbCurrencyProvider>((ref) {
  return TcmbCurrencyProvider(ref.watch(apiClientProvider));
});

final yahooProvider = Provider<YahooFinanceProvider>((ref) {
  return YahooFinanceProvider(ref.watch(apiClientProvider));
});

final newsRssProvider = Provider<NewsRssProvider>((ref) {
  return NewsRssProvider(ref.watch(apiClientProvider));
});

final anlikAltinFiyatlariProvider = Provider<AnlikAltinFiyatlariProvider>((ref) {
  return AnlikAltinFiyatlariProvider();
});

// ---------------------------------------------------------------------------
// REPOSITORIES (UI'nin goruntuledigi tek arayuz)
// ---------------------------------------------------------------------------

/// Piyasa verisi **kaynak listesi** - takas edilebilir.
///
/// Sira onemlidir: bir varligi birden fazla kaynak destekliyorsa ilk kaynak
/// kazanir. Yeni saglayici eklemek icin [MarketDataProvider] uygulayip
/// listeye eklemek yeterlidir; baska hicbir dosya degismez.
final marketSourcesProvider = Provider<List<MarketDataProvider>>((ref) {
  final tcmb = ref.watch(tcmbProvider);
  final yahoo = ref.watch(yahooProvider);
  final anlik = ref.watch(anlikAltinFiyatlariProvider);
  return [
    // Döviz: fiyat/alış-satış TCMB (resmi), %değişim Yahoo paritesi.
    TcmbFxMarketDataProvider(tcmb, yahoo: yahoo),
    // BIST + ons metal: dogrudan Yahoo.
    YahooMarketDataProvider(yahoo),
    // Altın/Gümüş: Anlık Altın Fiyatları (canli ~60sn).
    anlik,
  ];
});

final marketRepositoryProvider = Provider<MarketDataRepository>((ref) {
  return MarketDataRepositoryImpl(
    sources: ref.watch(marketSourcesProvider),
    staleAfter: CachePolicy.quoteTtl,
  );
});

/// Somut tip - onbellek temizleme gibi islemler icin.
final marketRepositoryImplProvider = Provider<MarketDataRepositoryImpl>((ref) {
  final repo = ref.watch(marketRepositoryProvider);
  return repo as MarketDataRepositoryImpl;
});

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepositoryImpl(
    ref.watch(newsRssProvider),
    cacheTtl: CachePolicy.newsTtl,
  );
});

// ---------------------------------------------------------------------------
// EKONOMIK TAKVIM
// ---------------------------------------------------------------------------

/// Ekonomik takvim veri **kaynagi**.
///
/// **DURUM: `null` - henuz hicbir kaynak yapilandirilmadi.**
///
/// Neden: uygun ve hukuki acidan net bir kaynak secilmedi (lisans/ kullanim
/// kosullari degerlendirmesi kullanici onayina bagli - bkz. asama 15 notlari).
/// Boylece uygulama **sahte olay, uydurma beklenti/onceki/gerceklesen deger
/// uretmez**; takvim ekrani "veri yok" durumunu gosterir.
///
/// Kaynak eklenince bu provider override edilerek gercek [EconomicCalendarProvider]
/// dondurulmesi yeterlidir - repository, state ve UI **degismez**.
final economicCalendarSourceProvider = Provider<EconomicCalendarProvider?>(
  (ref) => null,
);

final economicCalendarRepositoryProvider =
    Provider<EconomicCalendarRepository>((ref) {
  return EconomicCalendarRepositoryImpl(
    ref.watch(economicCalendarSourceProvider),
    cacheTtl: CachePolicy.calendarTtl,
  );
});

// ---------------------------------------------------------------------------
// BAGLANTI DURUMU
// ---------------------------------------------------------------------------

/// Gercek baglanti durumu.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged;
});

/// Cevrimdisi mi?
final isOfflineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider);
  return results.when(
    data: (list) =>
        list.isEmpty || list.every((r) => r == ConnectivityResult.none),
    loading: () => false,
    error: (_, Object _) => false,
  );
});

// ---------------------------------------------------------------------------
// AYARLAR
// ---------------------------------------------------------------------------

/// Tema tercihi: 'system' | 'light' | 'dark'
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Tercih senkron okunur: build sirasinda `state` yazmak yerine ilk
    // deger dogrudan donulur. (Eski hali `_load()` ile `state` yazip sonra
    // `ThemeMode.system` dondugu icin kaydedilmis tema **hiç uygulanmiyordu**;
    // ustelik build sirasinda state yazimi Riverpod init asserti uretebilir.)
    try {
      final raw =
          ref.read(sharedPreferencesProvider).getString(ThemeKeys.themeMode);
      return switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      return ThemeMode.system;
    }
  }

  void set(ThemeMode mode) {
    state = mode;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString(ThemeKeys.themeMode, switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
    } catch (_) {
      // Kayit basarisizsa tercih bellekte kalir; uygulama calismaya devam eder.
    }
  }
}

// ---------------------------------------------------------------------------
// ANONIM TELEMETRI
// ---------------------------------------------------------------------------


/// Anonim kurulum telemetrisi (Supabase `telemetry_ping` RPC).
///
/// * `--dart-define` ile `SUPABASE_URL` + `SUPABASE_ANON_KEY` verilmemis ise
///   servis **pasiftir**: ag cagrisi yapmaz, kimlik uretmez.
/// * UI'dan/finans veri yolundan **bagimsizdir**: hata uygulamayi etkilemez.
/// * Service-role key bu projede hicbir yerde bulunmaz.
final telemetryProvider = Provider<TelemetryService>((ref) {
  final service = TelemetryService(prefs: ref.watch(sharedPreferencesProvider));
  ref.onDispose(service.dispose);
  return service;
});

// NOT: `updateNotifierProvider` BURADA tanimli degildir.
// Tanim yalnizca `core/update/update_notifier.dart` icinde tek yerde durur.
// Burada ikinci bir kopyasi bulunmasi, `app_providers.dart`'i `hide
// updateNotifierProvider` kullanmadan import eden bir dosyayi sessizce FARKLI
// bir provider instance'ina yonlendirir; boylece UpdateChecker sonucu gormez
// ve update ekrani hicbir zaman gorunmez.