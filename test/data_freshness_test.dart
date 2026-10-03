// GOLD v2 - Faz A: veri tazeligi (freshness) katmani.
//
// Bu dosyada **ag yoktur**; yanitlar sabit `http.MockClient` govdelidir.
//
// Amaclar:
//  * "Canlı" etiketi yalnizca gercek zamanli akis dogrulandiginda uretilir.
//  * TCMB (gunluk resmi kur) asla "Canlı" gostermez.
//  * Yahoo oturum bilgisinden piyasa acik/kapali turetilir; oturum yoksa
//    tazelik `unknown` kalir (uydurulmaz).
//  * Hesaplanan varliklarin tazeligi bilesenlerinden birlestirilir.
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/error/failures.dart';
import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/yahoo_finance_provider.dart';
import 'package:gold/data/providers/yahoo_market_data_provider.dart';
import 'package:gold/data/repositories/market_data_repository_impl.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Kontrollu saglayici - tazelik birlestirme testleri icin.
class _Source implements MarketDataProvider {
  _Source({required this.id, required this.supported, required this.factory});

  @override
  final String id;

  @override
  final Duration refreshInterval = const Duration(seconds: 30);

  final Set<String> supported;
  final Quote Function(String assetId) factory;

  @override
  String get displayName => 'Sahte($id)';

  @override
  bool supports(String assetId) => supported.contains(assetId);

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> ids) async =>
      Success({for (final id in ids) id: factory(id)});

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err(EmptyFailure('mum yok'));
}

Quote _q(
  String id,
  double price, {
  required DataFreshness freshness,
  QuoteSourceLabel label = QuoteSourceLabel.market,
}) =>
    Quote(
      assetId: id,
      source: label,
      updatedAt: DateTime.now(),
      price: price,
      freshness: freshness,
    );

void main() {
  group('DataFreshness sirasi', () {
    test('canlı > gecikmeli > gunluk > kapali > bilinmiyor', () {
      expect(DataFreshness.live.rank, greaterThan(DataFreshness.delayed.rank));
      expect(
          DataFreshness.delayed.rank, greaterThan(DataFreshness.daily.rank));
      expect(DataFreshness.daily.rank, greaterThan(DataFreshness.closed.rank));
      expect(
          DataFreshness.closed.rank, greaterThan(DataFreshness.unknown.rank));
    });

    test('"Canlı" yazisi yalnizca live durumunda', () {
      expect(DataFreshness.live.label, 'Canlı');
      for (final f in [
        DataFreshness.delayed,
        DataFreshness.daily,
        DataFreshness.closed,
        DataFreshness.unknown,
      ]) {
        expect(f.label, isNot(contains('Canlı')),
            reason: '${f.name} asla "Canlı" gosteremez');
      }
    });
  });

  group('DataFreshness.combine (hesaplanan varliklar)', () {
    test('bilinmeyen bilesen varsa sonuc bilinmiyor olur', () {
      expect(
        DataFreshness.combine(const [
          DataFreshness.delayed,
          DataFreshness.unknown,
        ]),
        DataFreshness.unknown,
      );
    });

    test('bir bilesen kapaliy ise sonuc kapali olur', () {
      expect(
        DataFreshness.combine(const [
          DataFreshness.closed,
          DataFreshness.daily,
        ]),
        DataFreshness.closed,
      );
    });

    test('acik piyasalarda en taze bilesen kazanir', () {
      // gram altin = ons (gecikmeli) x USD/TRY (gunluk) -> guncelleme
      // sikligini onsin akisi belirler.
      expect(
        DataFreshness.combine(const [
          DataFreshness.delayed,
          DataFreshness.daily,
        ]),
        DataFreshness.delayed,
      );
    });

    test('bosluk listesi bilinmiyor doner', () {
      expect(DataFreshness.combine(const []), DataFreshness.unknown);
    });
  });

  group('DataFreshness.freshest (ekran ozeti)', () {
    test('kapali borsa ozeti gostermeyi engellemez', () {
      // Gece BIST kapali + ons acik -> "Gecikmeli", "Piyasa kapalı" degil.
      expect(
        DataFreshness.freshest(const [
          DataFreshness.closed,
          DataFreshness.delayed,
        ]),
        DataFreshness.delayed,
      );
    });

    test('hic veri yoksa bilinmiyor', () {
      expect(DataFreshness.freshest(const []), DataFreshness.unknown);
      expect(DataFreshness.freshest(const [DataFreshness.unknown]),
          DataFreshness.unknown);
    });
  });

  group('Quote tazelik alanlari', () {
    test('varsayilan deger bilinmiyordur (uydurma yok)', () {
      final q = Quote(
        assetId: 'x',
        source: QuoteSourceLabel.market,
        updatedAt: DateTime.now(),
        price: 1,
      );
      expect(q.freshness, DataFreshness.unknown);
      expect(q.marketTime, isNull);
    });

    test('copyWith tazeligi korur / degistirir', () {
      final q = _q('x', 1, freshness: DataFreshness.daily);
      expect(q.copyWith().freshness, DataFreshness.daily);
      expect(q.copyWith(freshness: DataFreshness.delayed).freshness,
          DataFreshness.delayed);
    });

    test('veri yoksa tazelik bilinmiyor', () {
      expect(Quote.unavailableFor('x').freshness, DataFreshness.unknown);
    });
  });

  group('Yahoo oturum bilgisinden turetilen tazelik', () {
    test('oturum acikken gecikmeli (asla canlı degil)', () async {
      final now = DateTime.now().toUtc();
      final y = YahooMarketDataProvider(
        YahooFinanceProvider(
          ApiClient(
            client: MockClient((_) async => http.Response(_body(
              start: now.subtract(const Duration(hours: 1)),
              end: now.add(const Duration(hours: 1)),
            ), 200)),
          ),
        ),
      );
      final res = await y.fetchQuotes([AssetCatalog.onsAltinId]);
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map![AssetCatalog.onsAltinId]!.freshness, DataFreshness.delayed);
    });

    test('oturum kapaliyken piyasa kapali', () async {
      final now = DateTime.now().toUtc();
      final y = YahooMarketDataProvider(
        YahooFinanceProvider(
          ApiClient(
            client: MockClient((_) async => http.Response(_body(
              start: now.subtract(const Duration(hours: 6)),
              end: now.subtract(const Duration(hours: 5)),
            ), 200)),
          ),
        ),
      );
      final res = await y.fetchQuotes([AssetCatalog.onsAltinId]);
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map![AssetCatalog.onsAltinId]!.freshness, DataFreshness.closed);
    });

    test('oturum bilgisi yoksa tazelik bilinmiyor (uydurulmaz)', () async {
      final y = YahooMarketDataProvider(
        YahooFinanceProvider(
          ApiClient(
            client: MockClient((_) async => http.Response(_body(), 200)),
          ),
        ),
      );
      final res = await y.fetchQuotes([AssetCatalog.onsAltinId]);
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map![AssetCatalog.onsAltinId]!.freshness, DataFreshness.unknown);
    });

    test('son islem zamani (regularMarketTime) Quote.marketTime olur', () async {
      final now = DateTime.now().toUtc();
      final y = YahooMarketDataProvider(
        YahooFinanceProvider(
          ApiClient(
            client: MockClient((_) async => http.Response(_body(
              start: now.subtract(const Duration(hours: 1)),
              end: now.add(const Duration(hours: 1)),
            ), 200)),
          ),
        ),
      );
      final res = await y.fetchQuotes([AssetCatalog.onsAltinId]);
      final q = res.dataOrNull![AssetCatalog.onsAltinId]!;
      expect(q.marketTime, isNotNull);
      expect(q.marketTime!.isUtc, isTrue);
    });
  });

  group('Hesaplanan varlik tazeligi (repository)', () {
    MarketDataRepositoryImpl repo({
      required DataFreshness ounce,
      required DataFreshness fx,
    }) =>
        MarketDataRepositoryImpl(sources: [
          _Source(
            id: 'ons',
            supported: {AssetCatalog.onsAltinId},
            factory: (id) => _q(id, 4000, freshness: ounce),
          ),
          _Source(
            id: 'fx',
            supported: {AssetCatalog.usdTryId},
            factory: (id) =>
                _q(id, 42, freshness: fx, label: QuoteSourceLabel.market),
          ),
        ]);

    test('ons gecikmeli + kur gunluk -> gram gecikmeli', () async {
      final r = repo(ounce: DataFreshness.delayed, fx: DataFreshness.daily);
      final res = await r.getQuotes([AssetCatalog.gramAltinId]);
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map![AssetCatalog.gramAltinId]!.freshness,
          DataFreshness.delayed);
    });

    test('ons kapaliyken gram da kapali gosterilir', () async {
      final r = repo(ounce: DataFreshness.closed, fx: DataFreshness.daily);
      final res = await r.getQuotes([AssetCatalog.gramAltinId]);
      expect(res.dataOrNull![AssetCatalog.gramAltinId]!.freshness,
          DataFreshness.closed);
    });

    test('bilesenin tazeligi bilinmiyorsa gram da bilinmiyor', () async {
      final r = repo(ounce: DataFreshness.unknown, fx: DataFreshness.daily);
      final res = await r.getQuotes([AssetCatalog.gramAltinId]);
      expect(res.dataOrNull![AssetCatalog.gramAltinId]!.freshness,
          DataFreshness.unknown);
    });

    test('gram altindan tureyen ceyrek altin da tazeligi devralir', () async {
      final r = repo(ounce: DataFreshness.delayed, fx: DataFreshness.daily);
      final res = await r.getQuotes([AssetCatalog.ceyrekAltinId]);
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map![AssetCatalog.ceyrekAltinId]!.freshness,
          DataFreshness.delayed);
    });
  });
}

/// Yahoo `chart` yanit govdesi - istegi gecmise gore uretilir.
String _body({DateTime? start, DateTime? end}) {
  final session = (start == null || end == null)
      ? ''
      : '"currentTradingPeriod":{"regular":{'
          '"start":${start.millisecondsSinceEpoch ~/ 1000},'
          '"end":${end.millisecondsSinceEpoch ~/ 1000}}}';
  return '''
{"chart":{"result":[{"meta":{
  "currency":"USD",
  "symbol":"GC=F",
  "regularMarketPrice":4000.0,
  "chartPreviousClose":3990.0,
  "regularMarketChange":10.0,
  "regularMarketChangePercent":0.25,
  "regularMarketTime":${DateTime.now().millisecondsSinceEpoch ~/ 1000}
  ${session.isNotEmpty ? ',' : ''}$session
}}],"error":null}}
''';
}
