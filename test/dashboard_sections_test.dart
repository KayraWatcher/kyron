import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/features/home/dashboard_sections.dart';

import 'helpers/fake_market_repository.dart';

/// Ana sayfa dashboard bolumleri: canli baglanti durumu, en cok hareket
/// edenler ve kategori navigasyonu.
void main() {
  Widget app(Widget child) => ProviderScope(
        overrides: [
          marketRepositoryProvider.overrideWithValue(FakeMarketRepository()),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  group('LiveConnectionBar - durum dogrusu', () {
    testWidgets('veri yukleniyorken acikca yazar', (tester) async {
      await tester.pumpWidget(
        app(
          const LiveConnectionBar(
            quotes: null,
            loading: true,
            offline: false,
          ),
        ),
      );
      expect(find.textContaining('Veri bağlantısı kuruluyor'), findsOneWidget);
    });

    testWidgets('canli fiyat varsa "Canlı veriler" yazar', (tester) async {
      await tester.pumpWidget(
        app(
          LiveConnectionBar(
            quotes: {
              AssetCatalog.onsAltinId: Quote(
                assetId: AssetCatalog.onsAltinId,
                source: QuoteSourceLabel.market,
                updatedAt: DateTime.now(),
                price: 4100,
                freshness: DataFreshness.live,
              ),
            },
            loading: false,
            offline: false,
          ),
        ),
      );
      expect(find.textContaining('Canlı veriler'), findsOneWidget);
    });

    testWidgets('cevrimdisi durumu acikca yazilir', (tester) async {
      await tester.pumpWidget(
        app(
          const LiveConnectionBar(quotes: null, loading: false, offline: true),
        ),
      );
      expect(find.textContaining('Çevrimdışısınız'), findsOneWidget);
    });

    testWidgets('tum veriler bayatsa "yenileniyor" yazar', (tester) async {
      await tester.pumpWidget(
        app(
          LiveConnectionBar(
            quotes: {
              AssetCatalog.onsAltinId: Quote(
                assetId: AssetCatalog.onsAltinId,
                source: QuoteSourceLabel.market,
                updatedAt: DateTime.now(),
                price: 4100,
                changePercent: 1,
                freshness: DataFreshness.live,
                isStale: true,
              ),
            },
            loading: false,
            offline: false,
          ),
        ),
      );
      expect(find.textContaining('yenileniyor'), findsOneWidget);
    });

    testWidgets('canli olmayan taze veride piyasa kapali yazar', (tester) async {
      await tester.pumpWidget(
        app(
          LiveConnectionBar(
            quotes: {
              AssetCatalog.bist100Id: Quote(
                assetId: AssetCatalog.bist100Id,
                source: QuoteSourceLabel.market,
                updatedAt: DateTime.now(),
                price: 12443,
                freshness: DataFreshness.closed,
              ),
            },
            loading: false,
            offline: false,
          ),
        ),
      );
      expect(find.textContaining('piyasa kapalı'), findsOneWidget);
    });
  });

  group('TopMoversSection - veri yoksa hic gosterilmez', () {
    testWidgets('hareket verisi yoksa bolum render edilmez', (tester) async {
      await tester.pumpWidget(app(const TopMoversSection()));
      await tester.pumpAndSettle();
      expect(find.text('Günün En Çok Hareket Edenleri'), findsNothing);
    });
  });

  group('CategoryNavSection', () {
    testWidgets('katalogdaki kategorileri sayilariyla listeler', (tester) async {
      await tester.pumpWidget(app(const CategoryNavSection()));
      await tester.pumpAndSettle();

      expect(find.text('Kategoriler'), findsOneWidget);
      expect(find.text('Kripto'), findsOneWidget);
      expect(find.text('Emtia'), findsOneWidget);
      // Katalogda varligi olmayan kategori GOSTERILMEZ.
      expect(find.text('Fonlar'), findsNothing);
    });
  });
}
