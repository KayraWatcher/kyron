// Ons Altın / Ons Gümüş - fiyat gorunurlugu, sembol ayirimi ve saglayici yedegi.
//
// KOK NEDEN (2026-10-06 - PC uzerinde Dart, cihaz uzerinde tarayici ile canli
// dogrulandi):
//
//  1) `api.gold-api.com`, User-Agent'inda "Dart" (buyuk/kucuk harf farketmez)
//     iceren isteklere **HTTP 429** dondurur; tarayici / curl / python-requests
//     UA'lari HTTP 200 dondurur. `package:http` varsayilan UA'i
//     `Dart/x.y (dart:io)` oldugu icin Gold API'nin fiyatlari sessizce
//     reddediliyordu -> `ons-altin` ve `ons-gumus` **hic quote alamiyordu**.
//
//  2) `MarketDataRepositoryImpl._fetchDirectTryAll` yalnizca ILK destekleyici
//     provider'i denedigi icin, Gold API basarisiz olunca siradaki kaynak
//     (orn. Anlik Altin - Ons Gumus uzerinde calisiyor) hic denenmiyordu.
//
//  3) UI (`markets_screen.dart` / `home_screen.dart`) varligi yalnizca quote
//     map'inde varsa gosterir; bu yuzden quote yokligi **kart + arama +
//     kategori listesinden komple dusus** anlamina geliyordu.
//
//  4) Grafik farkli sembol ister: Yahoo `/v8/finance/chart/XAU` ve `/XAG`
//     kalici HTTP 404; `/GC=F` ve `/SI=F` HTTP 200. Fiyat SPOT XAU/XAG olarak
//     kalir, yalnizca OHLC serisi GC=F/SI=F olur.
//
// Bu dosyada **ag yoktur**: `http.MockClient` ile yanitlar sabittir.
import 'package:flutter_test/flutter_test.dart';

import 'package:gold/core/error/failures.dart';
import 'package:gold/data/providers/gold_api_provider.dart';
import 'package:gold/data/repositories/market_data_repository_impl.dart';
import 'package:gold/domain/entities/asset.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Quote _q(String id) => Quote(
      assetId: id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime.utc(2026, 10, 6, 12),
      price: 1,
      change: 0,
      changePercent: 0,
    );

const String _goldBody = '{"currency":"USD","name":"Gold","price":4135.7,'
    '"symbol":"XAU","updatedAt":"2026-10-06T12:00:00Z"}';

/// Kontrollu piyasa saglayicisi - yedek kaynak zinciri testleri icin.
class _FakeSource implements MarketDataProvider {
  _FakeSource({
    required this.id,
    required this.supported,
    this.fail = false,
  });

  @override
  final String id;

  @override
  String get displayName => 'Sahte($id)';

  @override
  final Duration refreshInterval = const Duration(minutes: 5);

  final Set<String> supported;
  final bool fail;
  int calls = 0;

  @override
  bool supports(String assetId) => supported.contains(assetId);

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    calls++;
    if (fail) return const Err(NetworkFailure('Sahte ag hatasi.'));
    return Success({for (final a in assetIds) a: _q(a)});
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err(EmptyFailure('Mum desteklenmiyor.'));
}

void main() {
  // ---------------------------------------------------------------------------
  group('Ons - gorunurluk (katalog / kategori / one cikanlar)', () {
    test('katalogdan hicbir zaman cikarilmadi', () {
      expect(AssetCatalog.byId(AssetCatalog.onsAltinId), isNotNull);
      expect(AssetCatalog.byId(AssetCatalog.onsGumusId), isNotNull);
      expect(AssetCatalog.all.map((a) => a.id),
          containsAll(<String>[AssetCatalog.onsAltinId, AssetCatalog.onsGumusId]));
    });

    test('Piyasalar kategori listelerinde yer aliyor', () {
      final altin = AssetCatalog.byCategory(AssetCategory.altin).map((a) => a.id);
      final gumus = AssetCatalog.byCategory(AssetCategory.gumus).map((a) => a.id);
      expect(altin, contains(AssetCatalog.onsAltinId));
      expect(gumus, contains(AssetCatalog.onsGumusId));
    });

    test('Ana Sayfa "Öne Çıkanlar" varsayilan listesinde yer aliyor', () {
      expect(
        AssetCatalog.featuredIds,
        containsAll(<String>[
          AssetCatalog.onsAltinId,
          AssetCatalog.onsGumusId,
        ]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('Ons - fiyat sembolu ile grafik sembolu ayrildi', () {
    test('Ons Altin: fiyat SPOT XAU, grafik GC=F', () {
      final a = AssetCatalog.byId(AssetCatalog.onsAltinId)!;
      expect(a.providerSymbol, 'XAU', reason: 'fiyat SPOT XAU olarak kalir');
      expect(a.fetchSymbol, 'XAU');
      expect(a.chartProviderSymbol, 'GC=F');
      expect(a.fetchChartSymbol, 'GC=F',
          reason: 'Yahoo /chart/XAU kalici 404 - mum serisi GC=F olur');
      expect(a.currency, 'USD');
      expect(a.isCalculated, isFalse);
    });

    test('Ons Gumus: fiyat SPOT XAG, grafik SI=F', () {
      final a = AssetCatalog.byId(AssetCatalog.onsGumusId)!;
      expect(a.providerSymbol, 'XAG');
      expect(a.fetchSymbol, 'XAG');
      expect(a.chartProviderSymbol, 'SI=F');
      expect(a.fetchChartSymbol, 'SI=F');
      expect(a.currency, 'USD');
      expect(a.isCalculated, isFalse);
    });

    test('grafik sembolu tanimlanmayan varliklarda hicbir sey degismez', () {
      for (final id in <String>[
        AssetCatalog.gramAltinId,
        AssetCatalog.gramGumusId,
        AssetCatalog.bist100Id,
        AssetCatalog.usdTryId,
        AssetCatalog.wtiCrudeId,
        AssetCatalog.brentCrudeId,
      ]) {
        final a = AssetCatalog.byId(id)!;
        expect(a.fetchChartSymbol, a.fetchSymbol,
            reason: '$id icin grafik sembolu varsayilan ile ayni olmali');
      }
    });

    test('toreyen varliklarin parent baglantisi bozulmadi', () {
      expect(AssetCatalog.byId(AssetCatalog.gramAltinId)!.parentIds,
          [AssetCatalog.onsAltinId, AssetCatalog.usdTryId]);
      expect(AssetCatalog.byId(AssetCatalog.gramGumusId)!.parentIds,
          [AssetCatalog.onsGumusId, AssetCatalog.usdTryId]);
    });
  });

  // ---------------------------------------------------------------------------
  group('Gold API - Dart UA 429 kirilmasi', () {
    test('istanekte User-Agent "Dart" icermiyor (429 tetikleyicisi)', () async {
      String? seenUa;
      final client = MockClient((request) async {
        final headers = <String, String>{
          for (final e in request.headers.entries)
            e.key.toLowerCase(): e.value,
        };
        seenUa = headers['user-agent'];
        return http.Response(_goldBody, 200);
      });

      final p = GoldApiProvider(httpClient: client);
      await p.fetchQuotes([AssetCatalog.onsAltinId]);
      p.dispose();

      expect(seenUa, isNotNull);
      expect(seenUa!.toLowerCase(), isNot(contains('dart')),
          reason: 'gold-api.com Dart UA ile 429 dondurur');
      expect(seenUa, 'KYRON (Flutter)',
          reason: 'tarayici taklidi yok - kendini tanitan UA');
    });

    test('200 geldiginde Ons Altin icin fiyat uretiliyor', () async {
      final client =
          MockClient((_) async => http.Response(_goldBody, 200));
      final p = GoldApiProvider(httpClient: client);

      final res = await p.fetchQuotes(
          [AssetCatalog.onsAltinId, AssetCatalog.onsGumusId]);
      p.dispose();

      final map = res.dataOrNull;
      expect(map, isNotNull, reason: 'hata firlatilmamali: ${res.failureOrNull}');
      expect(map!.keys,
          containsAll([AssetCatalog.onsAltinId, AssetCatalog.onsGumusId]));
      expect(map[AssetCatalog.onsAltinId]!.price, 4135.7);
      expect(map[AssetCatalog.onsAltinId]!.currency, 'USD');
    });

    test('429/500 donse asla yanlis fiyat uretmez', () async {
      final client =
          MockClient((_) async => http.Response('Too Many Requests', 429));
      final p = GoldApiProvider(httpClient: client);

      final res = await p.fetchQuotes([AssetCatalog.onsAltinId]);
      p.dispose();

      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('Repository - saglayici yedegi', () {
    test('ilk saglayici hata donerse siradaki kaynak denenir', () async {
      final first = _FakeSource(
        id: 'gold-api-like',
        supported: const {AssetCatalog.onsAltinId, AssetCatalog.onsGumusId},
        fail: true,
      );
      final second = _FakeSource(
        id: 'fallback-like',
        supported: const {AssetCatalog.onsAltinId, AssetCatalog.onsGumusId},
      );
      final repo = MarketDataRepositoryImpl(sources: [first, second]);

      final res = await repo.getQuotes([AssetCatalog.onsAltinId]);
      final map = res.dataOrNull;

      expect(first.calls, 1);
      expect(second.calls, 1,
          reason: 'ilk kaynak basarisizken yedek kaynak hic denenmiyordu');
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map!.containsKey(AssetCatalog.onsAltinId), isTrue);
    });

    test('ilk saglayici basariliysa yedek gereksiz yere cagrilmaz', () async {
      final first = _FakeSource(
        id: 'primary',
        supported: const {AssetCatalog.onsGumusId},
      );
      final second = _FakeSource(
        id: 'fallback',
        supported: const {AssetCatalog.onsGumusId},
      );
      final repo = MarketDataRepositoryImpl(sources: [first, second]);

      final res = await repo.getQuotes([AssetCatalog.onsGumusId]);

      expect(res.dataOrNull, isNotNull);
      expect(first.calls, 1);
      expect(second.calls, 0);
    });

    test('hicbir kaynak desteklemiyorsa sahte fiyat uretilmez', () async {
      final none = _FakeSource(id: 'baska', supported: const {});
      final repo = MarketDataRepositoryImpl(sources: [none]);

      final res = await repo.getQuotes([AssetCatalog.onsAltinId]);

      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });
  });
}
