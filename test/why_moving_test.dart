import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/error/failures.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/news_item.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/repositories/news_repository.dart';
import 'package:gold/features/home/why_moving_card.dart';
import 'package:gold/features/home/why_moving_providers.dart';

import 'helpers/fake_market_repository.dart';

/// Haber deposu sahtesi (yalnizca gercek [NewsItem] dondurur).
class _FakeNewsRepo implements NewsRepository {
  _FakeNewsRepo(this.items);

  final List<NewsItem> items;

  @override
  Future<Result<List<NewsItem>>> getNews({
    NewsCategory category = NewsCategory.sonDakika,
    int limit = 30,
  }) async {
    if (items.isEmpty) return const Err(EmptyFailure('haber yok'));
    return Success(items);
  }

  @override
  Future<Result<List<NewsItem>>> getBreakingNews({int limit = 20}) =>
      getNews(limit: limit);

  @override
  Future<Result<List<NewsItem>>> getNewsForAssets(
    List<String> assetIds, {
    int limit = 20,
  }) =>
      getNews(limit: limit);

  @override
  void invalidateCache() {}
}

Quote _q(String id, double price, double? pct) => Quote(
      assetId: id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime(2026, 10, 6, 12),
      price: price,
      currency: 'TRY',
      changePercent: pct,
    );

NewsItem _news(
  String title, {
  NewsCategory category = NewsCategory.merkezBankasi,
}) =>
    NewsItem(
      id: 'n-$title',
      title: title,
      source: 'Test Kaynak',
      publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
      category: category,
      url: 'https://ornek.com/${title.hashCode}',
    );

void main() {
  group('WhyMovingData - kanit yoksa icerik yok', () {
    test('varsayilan degerde kanit YOK', () {
      const d = WhyMovingData(assetId: 'ons-altin');
      expect(d.hasEvidence, isFalse);
      expect(d.evidences, isEmpty);
    });

    test('haber kategorisi -> kanit turu eslemesi', () {
      expect(
        WhyEvidenceKind.fromNewsCategory(NewsCategory.merkezBankasi),
        WhyEvidenceKind.merkezBankasi,
      );
      expect(
        WhyEvidenceKind.fromNewsCategory(NewsCategory.dunyaEkonomisi),
        WhyEvidenceKind.ekonomikVeri,
      );
      expect(
        WhyEvidenceKind.fromNewsCategory(NewsCategory.ekonomi),
        WhyEvidenceKind.ekonomikVeri,
      );
      expect(
        WhyEvidenceKind.fromNewsCategory(NewsCategory.sirketler),
        WhyEvidenceKind.sirketHaberi,
      );
      expect(
        WhyEvidenceKind.fromNewsCategory(NewsCategory.altin),
        WhyEvidenceKind.haber,
      );
      for (final k in WhyEvidenceKind.values) {
        expect(k.label, isNotEmpty);
      }
    });
  });

  group('whyMovingProvider - kanit toplama', () {
    test('bilesen hareketi + haber kaniti uretilir', () async {
      final container = ProviderContainer(
        overrides: [
          marketRepositoryProvider.overrideWithValue(
            FakeMarketRepository(
              quotes: {
                AssetCatalog.onsAltinId: _q(AssetCatalog.onsAltinId, 4100, -1.2),
                AssetCatalog.usdTryId: _q(AssetCatalog.usdTryId, 49.1, 0.4),
              },
            ),
          ),
          newsRepositoryProvider.overrideWithValue(
            _FakeNewsRepo([_news('Fed faiz kararını açıkladı')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final data = await container
          .read(whyMovingProvider(AssetCatalog.gramAltinId).future);

      expect(data.hasEvidence, isTrue);
      final kinds = data.evidences.map((e) => e.kind).toSet();
      expect(kinds, contains(WhyEvidenceKind.piyasaHareketi));
      expect(kinds, contains(WhyEvidenceKind.merkezBankasi));
      for (final e in data.evidences) {
        expect(e.headline.trim(), isNotEmpty);
      }
    });

    test('veri yoksa kanit URETILMEZ (bos liste)', () async {
      final container = ProviderContainer(
        overrides: [
          marketRepositoryProvider
              .overrideWithValue(FakeMarketRepository()),
          newsRepositoryProvider.overrideWithValue(_FakeNewsRepo(const [])),
        ],
      );
      addTearDown(container.dispose);

      final data = await container
          .read(whyMovingProvider(AssetCatalog.gramAltinId).future);
      expect(data.hasEvidence, isFalse);
      expect(data.evidences, isEmpty);
    });

    test('bileseni olmayan varlikta haber kaniti yeterlidir', () async {
      final container = ProviderContainer(
        overrides: [
          marketRepositoryProvider.overrideWithValue(
            FakeMarketRepository(
              quotes: {
                AssetCatalog.bitcoinId: _q(AssetCatalog.bitcoinId, 85478, 2.1),
              },
            ),
          ),
          newsRepositoryProvider.overrideWithValue(
            _FakeNewsRepo([
              _news('Bitcoin rekor kırdı', category: NewsCategory.sonDakika),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final data =
          await container.read(whyMovingProvider(AssetCatalog.bitcoinId).future);
      expect(data.hasEvidence, isTrue);
      expect(data.evidences.map((e) => e.kind), contains(WhyEvidenceKind.haber));
    });
  });

  group('WhyMovingCard - veri yokken HIC gosterilmez', () {
    Widget app({
      String assetId = AssetCatalog.onsAltinId,
      FakeMarketRepository? repo,
      List<NewsItem>? news,
    }) =>
        ProviderScope(
          overrides: [
            marketRepositoryProvider
                .overrideWithValue(repo ?? FakeMarketRepository()),
            newsRepositoryProvider
                .overrideWithValue(_FakeNewsRepo(news ?? const [])),
          ],
          child: MaterialApp(
            home: Scaffold(body: WhyMovingCard(assetId: assetId)),
          ),
        );

    testWidgets('kanit yoksa baslik hic render edilmez', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.text('Neden Hareket Ediyor?'), findsNothing);
      expect(find.textContaining('yeterli doğrulanabilir'), findsNothing);
      expect(find.textContaining('kanıt bulunamadı'), findsNothing);
      expect(find.textContaining('PIYASA HAREKETI'), findsNothing);
    });

    testWidgets('yukleniyor durumunda da kutu gosterilmez', (tester) async {
      await tester.pumpWidget(
        app(repo: FakeMarketRepository(neverCompletes: true)),
      );
      await tester.pump();

      expect(find.text('Neden Hareket Ediyor?'), findsNothing);
      expect(find.textContaining('Analiz'), findsNothing);
    });

    testWidgets('kanit varsa baslik + kanit turu gorunur', (tester) async {
      // Gram altin bileseni ons altin oldugu icin hem piyasa hareketi hem
      // haber kaniti uretilir.
      await tester.pumpWidget(
        app(
          assetId: AssetCatalog.gramAltinId,
          repo: FakeMarketRepository(
            quotes: {
              AssetCatalog.onsAltinId: _q(AssetCatalog.onsAltinId, 4100, -1.2),
              AssetCatalog.usdTryId: _q(AssetCatalog.usdTryId, 49.1, 0.4),
            },
          ),
          news: [_news('Fed faiz kararını açıkladı')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Neden Hareket Ediyor?'), findsOneWidget);
      expect(find.text('PİYASA HAREKETİ'), findsOneWidget);
      expect(find.text('MERKEZ BANKASI'), findsOneWidget);
      expect(find.text('Fed faiz kararını açıkladı'), findsOneWidget);
    });
  });
}
