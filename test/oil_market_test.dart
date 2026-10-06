// GOLD - Petrol (WTI / Brent) emtia eklentisi.
//
// Kurallar:
//  * Petrol, mevcut piyasa mimarisiyle **ayni** yapiya uyar (Yahoo provider).
//  * Yeni API key eklenmez; mevcut anahtarsiz Yahoo chart endpoint'i kullanilir.
//  * Yeni kategori eklenirken mevcut 5 sekme (0-4) **degismez**.
//  * Var olan BIST/altin gumus/doviz kaynaklari ayni kalir.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/anlik_altin_fiyatlari_provider.dart';
import 'package:gold/data/providers/tcmb_currency_provider.dart';
import 'package:gold/data/providers/tcmb_fx_market_data_provider.dart';
import 'package:gold/data/providers/yahoo_finance_provider.dart';
import 'package:gold/data/providers/yahoo_market_data_provider.dart';
import 'package:gold/domain/entities/asset.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/features/home/home_display.dart';

ApiClient _client() => ApiClient(
      client: MockClient((_) async => http.Response('ok', 200)),
    );

Quote _q(String id) => Quote(
      assetId: id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime.utc(2026, 10, 5, 12),
      price: 1,
      change: 0,
      changePercent: 0,
    );

void main() {
  // ---------------------------------------------------------------------------
  group('Petrol - katalog tanimi', () {
    test('WTI (Ham Petrol) tanimi', () {
      final w = AssetCatalog.wtiCrude;
      expect(w.id, AssetCatalog.wtiCrudeId);
      expect(w.id, 'wti-crude');
      expect(w.symbol, 'WTI');
      expect(w.name, contains('Ham Petrol'));
      expect(w.category, AssetCategory.emtia);
      expect(w.unit, AssetUnit.varil);
      expect(w.currency, 'USD');
      expect(w.providerSymbol, 'CL=F',
          reason: 'Yahoo enerji vadeli sembolu (NYMEX WTI)');
      expect(w.isCalculated, isFalse, reason: 'dogrudan kaynak verisi');
    });

    test('Brent tanimi', () {
      final b = AssetCatalog.brentCrude;
      expect(b.id, AssetCatalog.brentCrudeId);
      expect(b.id, 'brent-crude');
      expect(b.symbol, 'BRENT');
      expect(b.name, contains('Brent'));
      expect(b.category, AssetCategory.emtia);
      expect(b.unit, AssetUnit.varil);
      expect(b.currency, 'USD');
      expect(b.providerSymbol, 'BZ=F',
          reason: 'Yahoo enerji vadeli sembolu (ICE Brent)');
      expect(b.isCalculated, isFalse);
    });

    test('katalogda mevcut, id\'ler benzersiz', () {
      final ids = [for (final a in AssetCatalog.all) a.id];
      expect(ids.toSet(), hasLength(ids.length), reason: 'id tekrari olmamali');
      expect(ids, containsAll(<String>[
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
      ]));

      expect(AssetCatalog.byId(AssetCatalog.wtiCrudeId), isNotNull);
      expect(AssetCatalog.byId(AssetCatalog.brentCrudeId), isNotNull);
    });

    test('Emtia kategorisi: petrol, metaller ve enerji (1.2.0 kapsami)', () {
      final emtia = AssetCatalog.byCategory(AssetCategory.emtia);
      expect(emtia.map((a) => a.id).toSet(), <String>{
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
        AssetCatalog.platinId,
        AssetCatalog.paladyumId,
        AssetCatalog.bakirId,
        AssetCatalog.dogalgazId,
        AssetCatalog.platinGramId,
      });
    });

    test('Paladyum (spot) tanimi - CanliDoviz XPD/USD', () {
      final p = AssetCatalog.paladyum;
      expect(p.id, 'paladyum');
      expect(p.symbol, 'XPD/USD');
      expect(p.category, AssetCategory.emtia);
      expect(p.unit, AssetUnit.ons);
      expect(p.currency, 'USD');
      expect(
        p.providerSymbol,
        isNull,
        reason: 'paladyum icin dogrulanmis yedek kaynak yok; '
            'uydurma sembol verilmez',
      );
    });

    test('Bakir / Dogalgaz tanimlari (CanliDoviz + Yahoo yedegi)', () {
      final b = AssetCatalog.bakir;
      expect(b.symbol, 'COPPER');
      expect(b.providerSymbol, 'HG=F');
      expect(b.unit, AssetUnit.libre);
      expect(b.currency, 'USD');

      final g = AssetCatalog.dogalgaz;
      expect(g.symbol, 'NGAS');
      expect(g.providerSymbol, 'NG=F');
      expect(g.unit, AssetUnit.mmbtu);
      expect(g.currency, 'USD');
    });

    test('Platin (spot) tanimi - CanliDoviz XPT/USD + Yahoo PL=F yedegi', () {
      final p = AssetCatalog.platin;
      expect(p.id, AssetCatalog.platinId);
      expect(p.id, 'platin');
      expect(p.symbol, 'XPT/USD', reason: 'CanlıDöviz urun kodu');
      expect(p.name, contains('Platin'));
      expect(p.category, AssetCategory.emtia);
      expect(p.unit, AssetUnit.ons);
      expect(p.currency, 'USD');
      expect(p.providerSymbol, 'PL=F', reason: 'Yahoo platin vadeli yedegi');
      expect(p.isCalculated, isFalse);
    });

    test('ana sayfa one cikanlarina eklendi (mevcutlar korunur)', () {
      expect(AssetCatalog.featuredIds, containsAll(<String>[
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
      ]));
      // Petrol eklenmeden **onceki** 10 varlik aynen korunmali.
      expect(AssetCatalog.featuredIds, containsAll(<String>[
        AssetCatalog.bist100Id,
        AssetCatalog.bist30Id,
        AssetCatalog.gramAltinId,
        AssetCatalog.ceyrekAltinId,
        AssetCatalog.gramGumusId,
        AssetCatalog.usdTryId,
        AssetCatalog.eurTryId,
      ]));
      expect(AssetCatalog.featuredIds, hasLength(14),
          reason: 'eski 10 + petrol 2 + ons 2 - baska bir sey silinmemeli');
      for (final id in AssetCatalog.featuredIds) {
        expect(AssetCatalog.byId(id), isNotNull,
            reason: 'one cikanlar katalogda tanimli olmali: $id');
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('Petrol - mevcut kategoriler bozulmadi', () {
    test('kategori ve birim etiketleri ayni', () {
      expect(AssetCategory.borsa.label, 'Borsa');
      expect(AssetCategory.altin.label, 'Altın');
      expect(AssetCategory.gumus.label, 'Gümüş');
      expect(AssetCategory.doviz.label, 'Döviz');
      expect(AssetCategory.kripto.label, 'Kripto');
      expect(AssetCategory.emtia.label, 'Emtia');

      expect(AssetUnit.adet.label, 'adet');
      expect(AssetUnit.gram.label, 'gram');
      expect(AssetUnit.ons.label, 'ons');
      expect(AssetUnit.para.label, 'para');
      expect(AssetUnit.puan.label, 'puan');
      expect(AssetUnit.varil.label, 'varil');
    });

    test('etiketler benzersiz', () {
      final catLabels = [for (final c in AssetCategory.values) c.label];
      expect(catLabels.toSet(), hasLength(catLabels.length));
      final unitLabels = [for (final u in AssetUnit.values) u.label];
      expect(unitLabels.toSet(), hasLength(unitLabels.length));
    });

    test('var olan piyasalar hala katalogda', () {
      expect(AssetCatalog.byCategory(AssetCategory.borsa), isNotEmpty);
      expect(AssetCatalog.byCategory(AssetCategory.altin), isNotEmpty);
      expect(AssetCatalog.byCategory(AssetCategory.gumus), isNotEmpty);
      expect(AssetCatalog.byCategory(AssetCategory.doviz), isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('Petrol - provider uyumu', () {
    late YahooMarketDataProvider yahoo;

    setUp(() {
      yahoo = YahooMarketDataProvider(YahooFinanceProvider(_client()));
    });

    test('mevcut Yahoo provider her iki sembolu de destekler', () {
      expect(yahoo.supports(AssetCatalog.wtiCrudeId), isTrue);
      expect(yahoo.supports(AssetCatalog.brentCrudeId), isTrue);
    });

    test('Yahoo kaynagi petrol icin de gecerli kaynak olarak atanir', () {
      // Kaynak onceligi: TCMB (yalniz doviz) -> Yahoo -> Anlik Altin.
      final tcmb = TcmbFxMarketDataProvider(TcmbCurrencyProvider(_client()));
      final anlik = AnlikAltinFiyatlariProvider();

      expect(tcmb.supports(AssetCatalog.wtiCrudeId), isFalse,
          reason: 'TCMB yalnizca doviz saglar');
      expect(tcmb.supports(AssetCatalog.brentCrudeId), isFalse);
      expect(anlik.supports(AssetCatalog.wtiCrudeId), isFalse,
          reason: 'Anlik Altin yalnizca altin/gumus kapsar');
      expect(anlik.supports(AssetCatalog.brentCrudeId), isFalse);

      // Var olan kaynaklarin davranisi degismedi.
      expect(tcmb.supports(AssetCatalog.usdTryId), isTrue);
      expect(anlik.supports(AssetCatalog.gramAltinId), isTrue);
      expect(yahoo.supports(AssetCatalog.onsAltinId), isTrue);
      expect(yahoo.supports(AssetCatalog.bist100Id), isTrue);
    });

    test('grafik/sparkline (mum verisi) petrol icin de calisir', () {
      expect(yahoo.supportsCandles(AssetCatalog.wtiCrudeId), isTrue);
      expect(yahoo.supportsCandles(AssetCatalog.brentCrudeId), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  group('Petrol - ana sayfa filtresi', () {
    test('Emtia filtresi emtiayi getirir (katalog sirasi)', () {
      expect(HomeFilter.emtia.label, 'Emtia');

      final quotes = <String, Quote>{for (final a in AssetCatalog.all) a.id: _q(a.id)};

      final out = applyHomeDisplay(
        featured: AssetCatalog.featuredIds,
        catalog: AssetCatalog.all,
        watchlist: const <String>[],
        quotes: quotes,
        display: HomeDisplayState(
          filter: HomeFilter.emtia,
          sort: HomeSortField.varsayilan,
          ascending: true,
        ),
      );

      expect(out, <String>[
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
        AssetCatalog.platinId,
        AssetCatalog.paladyumId,
        AssetCatalog.bakirId,
        AssetCatalog.dogalgazId,
        AssetCatalog.platinGramId,
      ], reason: 'katalog sirasi korunur');
    });

    test('var olan filtreler petrolu karistirmaz', () {
      final quotes = <String, Quote>{for (final a in AssetCatalog.all) a.id: _q(a.id)};

      List<String> run(HomeFilter f) => applyHomeDisplay(
            featured: AssetCatalog.featuredIds,
            catalog: AssetCatalog.all,
            watchlist: const <String>[],
            quotes: quotes,
            display: HomeDisplayState(
              filter: f,
              sort: HomeSortField.varsayilan,
              ascending: true,
            ),
          );

      expect(run(HomeFilter.altin),
          isNot(contains(AssetCatalog.wtiCrudeId)));
      expect(run(HomeFilter.borsa),
          isNot(contains(AssetCatalog.brentCrudeId)));
      expect(run(HomeFilter.doviz), isNot(contains(AssetCatalog.wtiCrudeId)));
      expect(run(HomeFilter.tumu), containsAll(<String>[
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
      ]));
      expect(run(HomeFilter.onecikanlar), containsAll(<String>[
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
      ]));
    });

    test('petrolun verisi yoksa liste bos kalir (uydurma veri uretilmez)',
        () {
      final out = applyHomeDisplay(
        featured: AssetCatalog.featuredIds,
        catalog: AssetCatalog.all,
        watchlist: const <String>[],
        quotes: const <String, Quote>{},
        display: HomeDisplayState(
          filter: HomeFilter.emtia,
          sort: HomeSortField.varsayilan,
          ascending: true,
        ),
      );
      expect(out, isEmpty);
    });
  });
}
