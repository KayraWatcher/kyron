// GOLD v2 - Ana Sayfa "Piyasalar" satir gorunumu.
//
// Kurallar:
//  * Liste gorunumu, Takip Edilenler ile AYNI mevcut asset-row desenini
//    kullanir (WatchRow); ayri bir kopya satir component'i yoktur.
//  * QuoteCompactRow artik ana sayfada KULLANILMAZ.
//  * Satirda sparkline (mevcut sistem), fiyat ve degisim gosterilir;
//    Alis/Satis (spread) gosterilmez.
//  * Izgara (grid) gorunumu QuoteCard ile degismez (regresyon).
//  * Dar ekranda tasma/overflow olmaz (responsive).
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
import 'package:gold/shared/widgets/quote_compact_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sahte kaynak: istenen her varlik icin sabit fiyat + mum serisi dondurur.
class _FakeSource implements MarketDataProvider {
  @override
  String get id => 'fake-row-test';

  @override
  String get displayName => 'Fake Row Test';

  @override
  Duration get refreshInterval => const Duration(milliseconds: 500);

  @override
  bool supports(String assetId) => true;

  @override
  bool supportsCandles(String assetId) => true;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final now = DateTime.now();
    return Success({
      for (final id in assetIds)
        id: Quote(
          assetId: id,
          source: QuoteSourceLabel.market,
          updatedAt: now,
          price: 4100,
          previousClose: 4080,
          currency: 'TRY',
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

Map<String, Quote> _quotes(WidgetRef ref) =>
    ref.read(homeQuotesProvider).value ?? const <String, Quote>{};

/// HomeScreen'i [view] gorunumunde baslatir ve fiyatlarin gelmesini bekler.
Future<WidgetRef> _boot(WidgetTester tester, {required String view}) async {
  SharedPreferences.setMockInitialValues({
    'home_display.v1': 'tumu|varsayilan|1',
    'home_display.view': view,
  });
  final prefs = await SharedPreferences.getInstance();

  WidgetRef? captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        marketSourcesProvider.overrideWithValue([_FakeSource()]),
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
    if (_quotes(captured!).containsKey('gram-altin')) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
  return captured!;
}

void main() {
  testWidgets(
      'liste gorunumu: Piyasalar TAKIP EDILENLER ile ayni WatchRow desenini '
      'kullanir (QuoteCompactRow yok)', (tester) async {
    await _boot(tester, view: 'list');

    expect(find.text('Piyasalar'), findsOneWidget);
    expect(find.byType(QuoteCard), findsNothing,
        reason: 'liste gorunumunde izgara karti olmamali');
    expect(find.byType(QuoteCompactRow), findsNothing,
        reason: 'liste artik ortak satir desenini kullanir, kopya satir yok');
    expect(find.byType(WatchRow), findsWidgets,
        reason: 'satirlar Takip Edilenler ile ayni WatchRow olmali');
    expect(find.byType(Sparkline), findsWidgets,
        reason: 'sparkline mevcut sistemden gelmeli');
    expect(find.byType(AssetIdentity), findsWidgets);
    expect(
      find.text('Al'),
      findsNothing,
      reason: 'liste satirinda Alis/Satis (spread) gosterilmez',
    );
    expect(
      find.text('Sat'),
      findsNothing,
      reason: 'liste satirinda Alis/Satis (spread) gosterilmez',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('liste gorunumu: Takip Edilenler bolumu de ayni WatchRow deseni',
      (tester) async {
    await _boot(tester, view: 'list');

    // Piyasalar satirlari zaten WatchRow; bolumu gorunume alalim.
    final watchHeader = find.text('Takip Edilenler');
    await tester.scrollUntilVisible(
      watchHeader,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(watchHeader, findsOneWidget);
    expect(find.byType(WatchRow), findsWidgets,
        reason: 'Takip Edilenler satirlari da WatchRow');
    expect(find.byType(QuoteCompactRow), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('izgara gorunumu DEGISEZ: QuoteCard + WatchRow (regresyon)',
      (tester) async {
    await _boot(tester, view: 'grid');

    expect(find.byType(QuoteCard), findsWidgets,
        reason: 'izgara kartlari aynen devam etmeli');
    expect(find.byType(QuoteCompactRow), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WatchRow dar ekranda (360dp) tasma/overflow yapmaz', (tester) async {
    // Dar ekran: satirin KENDISI responsive mi? (Ana sayfanin diger kartlari
    // haric birakilir; onlar kapsam disi ve test fontu metrikleriyle zaten
    // dar ekranla ilgisi yok.)
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final quote = Quote(
      assetId: 'gram-altin',
      source: QuoteSourceLabel.market,
      updatedAt: DateTime.now(),
      price: 4100,
      previousClose: 4080,
      currency: 'TRY',
      freshness: DataFreshness.daily,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          marketSourcesProvider.overrideWithValue([_FakeSource()]),
          isOfflineProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WatchRow(assetId: 'gram-altin', quote: quote),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(WatchRow), findsOneWidget);
    expect(find.byType(Sparkline), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'dar ekranda satir responsive kalmali (overflow olmamali)',
    );
  });
}
