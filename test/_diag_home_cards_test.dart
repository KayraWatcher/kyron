// Diagnostik (gecici) - Ana Sayfa: Ons Altin / Ons Gumus kartlari.
//
// Cihazda raporlanan hata: "Ons Altin ve Ons Gumüş kartları ana ekranda bazen
// gelip gidiyor."
//
// Kart uyesligi tek bir kosula baglidir:
//   `applyHomeDisplay(...).where(map.containsKey)`  (home_screen.dart)
// Yani fiyat haritasindan bir id dustugu an kart ekrandan kaybolur.
//
// Bu test gercek HomeScreen + homeQuotesProvider + repository zinciri uzerinde
// **saglayici sembol atlattiginda** (GC=F / SI=F donmediginde) kartlarin
// kaybolip kaybolmadigini olcer:
//   1) sessiz zamanlayici tiklemesinde,
//   2) kullanici cekip-yenilediginde (RefreshIndicator -> refresh()).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold/core/error/failures.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/news_item.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:gold/domain/repositories/news_repository.dart';
import 'package:gold/features/home/home_providers.dart';
import 'package:gold/features/home/home_screen.dart';
import 'package:gold/shared/widgets/quote_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sahte kaynak: istendiginde Ons Altin / Ons Gumus sembollerini **atlar**.
class OnsOmittingSource implements MarketDataProvider {
  bool omitOns = false;
  int calls = 0;

  static const Set<String> onsIds = {'ons-altin', 'ons-gumus'};

  @override
  String get id => 'ons-omit-test';

  @override
  String get displayName => 'Ons Omit Test';

  @override
  Duration get refreshInterval => const Duration(milliseconds: 500);

  @override
  bool supports(String assetId) => true;

  @override
  bool supportsCandles(String assetId) => true;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    calls++;
    final now = DateTime.now();
    return Success({
      for (final id in assetIds)
        if (!(omitOns && onsIds.contains(id)))
          id: Quote(
            assetId: id,
            source: QuoteSourceLabel.market,
            updatedAt: now,
            price: 4100,
            previousClose: 4080,
            currency: 'USD',
            freshness: DataFreshness.daily,
          ),
    });
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    final base = DateTime(2024, 1, 1).millisecondsSinceEpoch;
    return Success(
      CandleSeries(
        assetId: assetId,
        interval: interval,
        candles: [
          for (var i = 0; i < limit; i++)
            Candle(
              time: base + i * 86400000,
              open: 4100.0 + i,
              high: 4110.0 + i,
              low: 4090.0 + i,
              close: 4105.0 + i,
            ),
        ],
      ),
    );
  }
}

class _EmptyNewsRepository implements NewsRepository {
  const _EmptyNewsRepository();

  @override
  Future<Result<List<NewsItem>>> getNews({
    NewsCategory category = NewsCategory.sonDakika,
    int limit = 30,
  }) async =>
      const Success([]);

  @override
  Future<Result<List<NewsItem>>> getBreakingNews({int limit = 20}) async =>
      const Success([]);

  @override
  Future<Result<List<NewsItem>>> getNewsForAssets(
    List<String> assetIds, {
    int limit = 20,
  }) async =>
      const Success([]);

  @override
  void invalidateCache() {}
}

const String _onsAltin = 'ons-altin';
const String _onsGumus = 'ons-gumus';
const String _gramAltin = 'gram-altin';
const String _gramGumus = 'gram-gumus';

Map<String, Quote> _map(WidgetRef ref) =>
    ref.read(homeQuotesProvider).value ?? const <String, Quote>{};

Future<WidgetRef> _boot(
  WidgetTester tester,
  OnsOmittingSource source, {
  bool omitFromStart = false,
}) async {
  source.omitOns = omitFromStart;
  SharedPreferences.setMockInitialValues({
    // Filtre "Tümü": katalogdaki tum varliklar (Ons kartlari dahil).
    'home_display.v1': 'tumu|varsayilan|1',
  });
  final prefs = await SharedPreferences.getInstance();

  WidgetRef? captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        marketSourcesProvider.overrideWithValue([source]),
        isOfflineProvider.overrideWithValue(false),
        newsRepositoryProvider.overrideWithValue(const _EmptyNewsRepository()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const HomeScreen();
            },
          ),
        ),
      ),
    ),
  );

  for (var i = 0; i < 60; i++) {
    if (_map(captured!).containsKey(_onsAltin)) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
  return captured!;
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('ana sayfa: saglayici sembol atlattiginda Ons kartlari KALIR '
      '(sessiz tikleme)', (tester) async {
    final source = OnsOmittingSource();
    final ref = await _boot(tester, source);

    var map = _map(ref);
    expect(map.keys, containsAll([_onsAltin, _onsGumus, _gramAltin, _gramGumus]),
        reason: 'ilk yuklemede tum kartlarin verisi olmali');
    expect(find.byType(QuoteCard), findsWidgets,
        reason: 'grid kartlar gostermeli');

    // ---- Saglayici artik GC=F / SI=F sembollerini ATLATIYOR ----
    source.omitOns = true;
    // Not: TTL gercek saatle, zamanlayici ise testin sahte saatiyle calisir.
    // Onbellegi temizleyerek bir sonraki tikin **kesinlikle** istek atmasini
    // sagliyoruz (uygulama kodunda refresh() de aynisini yapar).
    ref.read(marketRepositoryImplProvider).invalidateCache();
    final callsBefore = source.calls;
    for (var i = 0; i < 60 && source.calls <= callsBefore; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    map = _map(ref);
    expect(source.calls, greaterThan(callsBefore),
        reason: 'zamanlayici taze istek atmali');
    expect(map.containsKey(_onsAltin), isTrue,
        reason: 'Ons Altin karti sessiz yenilemede KAYBOLMAMALI');
    expect(map.containsKey(_onsGumus), isTrue,
        reason: 'Ons Gümüş karti sessiz yenilemede KAYBOLMAMALI');
    expect(map.containsKey(_gramAltin), isTrue,
        reason: 'Gram Altin (turev) karti KAYBOLMAMALI');
    expect(map.containsKey(_gramGumus), isTrue,
        reason: 'Gram Gümüş (turev) karti KAYBOLMAMALI');
    expect(map[_onsAltin]!.isStale, isTrue,
        reason: 'eksik gelen veri bayat olarak isaretlenmeli');
    expect(find.byType(QuoteCard), findsWidgets,
        reason: 'grid kart gostermeye devam etmeli');

    // ---- Saglayici tekrar dondukce kartlar geri gelmeli ----
    source.omitOns = false;
    ref.read(marketRepositoryImplProvider).invalidateCache();
    final back = source.calls;
    for (var i = 0; i < 60 && source.calls <= back; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    map = _map(ref);
    expect(map[_onsAltin]!.isStale, isFalse,
        reason: 'veri geldiginde bayatlik kalkmali');

    await _teardown(tester);
  });

  testWidgets('ana sayfa: cekip-yenileme (refresh) Ons kartlarini KAYBETTIRMEZ',
      (tester) async {
    final source = OnsOmittingSource();
    final ref = await _boot(tester, source);

    expect(_map(ref).keys, containsAll([_onsAltin, _onsGumus]));

    // Simdi saglayici sembolleri atlatiyor + kullanici cekip yeniliyor.
    source.omitOns = true;
    final callsBefore = source.calls;

    // ignore: unawaited_futures
    final pending = ref.read(homeQuotesProvider.notifier).refresh();

    await tester.pump();
    // YUKLEME SIRASINDA: deger sifirlanmamali - sifirlanirsa tum grid anlik
    // olarak kaybolur (toViewState -> Loading) ve eksik donen yanitta kalir.
    expect(ref.read(homeQuotesProvider).value, isNotNull,
        reason: 'refresh sirasinda onceki deger korunmali (kartlar kaybolmasin)');
    expect(find.byType(QuoteCard), findsWidgets,
        reason: 'refresh sirasinda grid spinnera donmemeli');

    for (var i = 0; i < 40 && source.calls == callsBefore; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    // ignore: unawaited_futures
    pending;

    final map = _map(ref);
    expect(source.calls, greaterThan(callsBefore),
        reason: 'refresh gercekten istek atmis olmali');
    expect(map.containsKey(_onsAltin), isTrue,
        reason: 'Ons Altin refresh sonrasi KAYBOLMAMALI');
    expect(map.containsKey(_onsGumus), isTrue,
        reason: 'Ons Gümüş refresh sonrasi KAYBOLMAMALI');
    expect(map.containsKey(_gramAltin), isTrue,
        reason: 'Gram Altin refresh sonrasi KAYBOLMAMALI');
    expect(map.containsKey(_gramGumus), isTrue,
        reason: 'Gram Gümüş refresh sonrasi KAYBOLMAMALI');
    expect(find.byType(QuoteCard), findsWidgets);

    await _teardown(tester);
  });

  testWidgets('ana sayfa: refresh sonrasi da sessiz tikleme kartlari korumali',
      (tester) async {
    final source = OnsOmittingSource();
    final ref = await _boot(tester, source);

    source.omitOns = true;
    // ignore: unawaited_futures
    ref.read(homeQuotesProvider.notifier).refresh();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    // Birkaç sessiz tikleme daha: birlesik merge zinciri kopmamali.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump();

    final map = _map(ref);
    expect(map.keys, containsAll([_onsAltin, _onsGumus, _gramAltin, _gramGumus]),
        reason: 'refresh + sessiz tiklemelerden sonra kartlar yerinde kalmali');
    expect(find.byType(QuoteCard), findsWidgets);

    await _teardown(tester);
  });
}
