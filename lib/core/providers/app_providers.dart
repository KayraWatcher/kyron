import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/anlik_altin_fiyatlari_provider.dart';
import '../../data/providers/canlidoviz_provider.dart';
import '../../data/providers/frankfurter_provider.dart';
import '../../data/providers/gold_api_provider.dart';
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

final goldApiProvider = Provider<GoldApiProvider>((ref) {
  return GoldApiProvider();
});

/// CanlıDöviz - **Ons Altın geçmiş mum (P0) + anlık fiyat akışı (P1)**.
///
/// Kaynak listesi oluşturulurken fiyat akışı (WebSocket) başlatılır; böylece
/// ilk `watchQuotes` ritmi kısa kalır ve ekran akış bağlanır bağlanmaz
/// CanlıDöviz tiklerine geçer. `dispose` akışı kapatır.
final canlidovizProvider = Provider<CanlidovizProvider>((ref) {
  final provider = CanlidovizProvider();
  ref.onDispose(provider.dispose);
  provider.startStream();
  return provider;
});

final frankfurterProvider = Provider<FrankfurterProvider>((ref) {
  return FrankfurterProvider();
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
  final goldApi = ref.watch(goldApiProvider);
  final canlidoviz = ref.watch(canlidovizProvider);
  final frankfurter = ref.watch(frankfurterProvider);
  return [
    // 1. Birincil kaynak (genis kapsam): anlik fiyat (WebSocket) + gecmis
    //    mum (history API). **Doviz de buna dahil** (kullanici karari:
    //    FX'te canli interbank birincil, TCMB gunde bir aciklanan resmi
    //    kur YEDEK olarak korunur). Kapsam: altin ailesi (ons/gram/ceyrek/
    //    yarim/tam/cumhuriyet/ata/bilezik/resat), gram+ons gumus,
    //    USD/EUR/GBP/CHF/JPY/CAD/AUD/CNY-TRY, BIST100/30/50, DXY, S&P 500,
    //    Brent, WTI, Platin - hepsi `CanlidovizProtocol` map'lerinde
    //    gercek cid/kod dogrulamasiyla. `fetchQuotes` hata dondugunde
    //    (baglanti yok / tik bayat / akis `CANLIDOVIZ_WS_DISABLED`)
    //    `_fetchDirectTryAll` siradaki adayi dener: **fallback zinciri
    //    oldugu gibi korunur**, hicbir yedek kaynak silinmedi.
    canlidoviz,
    // 1b. Ons Altin/Gumus SPOT yedek kaynak (Gold API - real-time, no key,
    //     commercial OK). Ons Gumus artik CanlıDöviz'den de gelir; Gold API
    //     akis yokken/yetersizken YEDEK olarak siradaki adaydir.
    goldApi,
    // 2. Döviz yedek: TCMB (resmi gunde 1-2 kez) - CanlıDöviz akisi
    //    veremediginde devreye girer; %degisim Yahoo paritesinden gelir.
    TcmbFxMarketDataProvider(tcmb, yahoo: yahoo),
    // 3. Döviz fallback: Frankfurter (ECB referans, gunluk) - TCMB basarisiz olursa.
    frankfurter,
    // 4. Emtia/BIST/Endeks yedek: Yahoo (WTI CL=F, Brent BZ=F, BIST
    //    XU100.IS/XU030.IS/XU050.IS, DXY DX-Y.NYB, SPX ^GSPC, Platin PL=F).
    YahooMarketDataProvider(yahoo),
    // 5. Yerel TL altın/gümüş: Anlık Altın Fiyatları (canli ~60sn).
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