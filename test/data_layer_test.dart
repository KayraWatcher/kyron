// Aşama 17 - Veri katmani: saglayici arayuzleri, ayristirma, onbellek,
// XML/JSON/RSS ayrıştırma ve ekonomik takvim dürüstlüğü.
//
// Bu dosyada **ag yoktur**: `http.MockClient` ile yanitlar sabittir.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/cache/cache_policy.dart';
import 'package:gold/core/error/failures.dart';
import 'package:gold/core/error/state_failure.dart';
import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/news_rss_provider.dart';
import 'package:gold/data/providers/tcmb_currency_provider.dart';
import 'package:gold/data/providers/tcmb_fx_market_data_provider.dart';
import 'package:gold/data/providers/yahoo_finance_provider.dart';
import 'package:gold/data/providers/yahoo_market_data_provider.dart';
import 'package:gold/data/repositories/economic_calendar_repository_impl.dart';
import 'package:gold/data/repositories/market_data_repository_impl.dart';
import 'package:gold/data/repositories/news_repository_impl.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/economic_event.dart';
import 'package:gold/domain/entities/news_item.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/economic_calendar_provider.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:gold/domain/providers/news_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// -----------------------------------------------------------------------------
// Sahte saglayicilar
// -----------------------------------------------------------------------------

/// Kontrollu piyasa saglayicisi - kaynak secimi ve onbellek testleri icin.
class FakeMarketSource implements MarketDataProvider {
  FakeMarketSource({
    required this.id,
    required this.supported,
    this.quoteFactory,
    this.fail = false,
    this.refreshInterval = const Duration(minutes: 5),
  });

  @override
  final String id;

  /// Besleyen saglayicinin en hizli guncelleme araligi (gercek saglayicidan
  /// okunur; arayuzun zorunlu uyesi).
  @override
  final Duration refreshInterval;

  final Set<String> supported;
  final Quote Function(String assetId)? quoteFactory;
  final bool fail;

  int calls = 0;
  final List<List<String>> requested = [];

  @override
  String get displayName => 'Sahte($id)';

  @override
  bool supports(String assetId) => supported.contains(assetId);

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    calls++;
    requested.add(assetIds);
    if (fail) return const Err(NetworkFailure('Sahte ag hatasi.'));

    final out = <String, Quote>{};
    for (final a in assetIds) {
      final f = quoteFactory;
      if (f == null) continue;
      out[a] = f(a);
    }
    return Success(out);
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err(EmptyFailure('Mum desteklenmiyor.'));
}

/// Kontrollu haber saglayicisi.
class FakeNewsSource implements NewsProvider {
  FakeNewsSource({this.fail = false});

  final bool fail;
  int calls = 0;

  @override
  String get id => 'fake-news';

  @override
  String get displayName => 'Sahte Haber';

  @override
  Future<Result<List<NewsItem>>> fetchAll({int limit = 30}) async {
    calls++;
    if (fail) return const Err(NetworkFailure('Sahte ag hatasi.'));
    return Success([
      NewsItem(
        id: 'n1',
        title: 'TCMB faizi sabit tuttu',
        source: displayName,
        publishedAt: DateTime(2026, 10, 2, 10, 0),
        category: NewsCategory.merkezBankasi,
        url: 'https://example.com/haber/1',
        summary: 'Kisa ozet.',
      ),
    ]);
  }
}

/// Kontrollu takvim saglayicisi.
class FakeCalendarSource implements EconomicCalendarProvider {
  FakeCalendarSource({this.fail = false});

  final bool fail;
  int calls = 0;

  @override
  String get id => 'fake-calendar';

  @override
  String get displayName => 'Sahte Takvim';

  @override
  Future<Result<List<EconomicEvent>>> fetchEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    if (fail) return const Err(NetworkFailure('Sahte ag hatasi.'));
    return const Success([]);
  }
}

Quote _directQuote(String id, {required double price, double? pct}) => Quote(
      assetId: id,
      source: QuoteSourceLabel.market,
      updatedAt: DateTime(2026, 10, 2, 12, 0),
      price: price,
      changePercent: pct,
    );

void main() {
  // ---------------------------------------------------------------------------
  group('ApiClient - HTTP durum kodlari', () {
    test('200 -> Success', () async {
      final client = ApiClient(
        client: MockClient((_) async => http.Response('ok', 200)),
      );
      final res = await client.getText(Uri.parse('https://example.com'));
      expect(res.dataOrNull, 'ok');
      expect(res.failureOrNull, isNull);
    });

    test('404 -> BadRequestFailure', () async {
      final client = ApiClient(
        client: MockClient((_) async => http.Response('yok', 404)),
      );
      final res = await client.getText(Uri.parse('https://example.com'));
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<BadRequestFailure>());
    });

    test('500 -> ServerFailure', () async {
      final client = ApiClient(
        client: MockClient((_) async => http.Response('hata', 500)),
      );
      final res = await client.getText(Uri.parse('https://example.com'));
      expect(res.failureOrNull, isA<ServerFailure>());
    });

    test('istisna asla disari sizmaz', () async {
      final client = ApiClient(
        client: MockClient((_) async => throw Exception('patlama')),
      );
      final res = await client.getText(Uri.parse('https://example.com'));
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });

    test('charset belirtilmemis UTF-8 govde mojibake olmaz', () async {
      // Eski hata: `response.body` http paketinde charset yokken latin1'e
      // dusuyordu -> "GÜNLÜK" / "İzmir" bozuk cikiyordu.
      const payload = '{"ad":"GÜNLÜK BÜLTEN","sehir":"İzmir Şehri"}';
      final client = ApiClient(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(payload),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
      final res = await client.getText(Uri.parse('https://example.com'));
      expect(res.dataOrNull, payload);
    });
  });

  // ---------------------------------------------------------------------------
  group('TCMB XML ayrıştırma', () {
    const tcmbXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<Tarih_Date Date="02-10-2026">
  <Currency CrossOrder="0" Kod="USD" CurrencyCode="USD">
    <Unit>1</Unit>
    <Isim>ABD DOLARI</Isim>
    <CurrencyName>US DOLLAR</CurrencyName>
    <ForexBuying>48.9699</ForexBuying>
    <ForexSelling>49.0582</ForexSelling>
    <BanknoteBuying>48.9357</BanknoteBuying>
    <BanknoteSelling>49.1318</BanknoteSelling>
  </Currency>
  <Currency CrossOrder="1" Kod="EUR" CurrencyCode="EUR">
    <Unit>1</Unit>
    <Isim>EURO</Isim>
    <ForexBuying>57.5000</ForexBuying>
    <ForexSelling>57.9000</ForexSelling>
  </Currency>
</Tarih_Date>
''';

    test('kurlar sayiya donusur, alis < satis', () async {
      final p = TcmbCurrencyProvider(
        ApiClient(
          client: MockClient((_) async => http.Response(tcmbXml, 200)),
        ),
      );

      final res = await p.fetchToday();
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map!.keys, containsAll(['USD', 'EUR']));

      final usd = map['USD']!;
      expect(usd.buying, closeTo(48.9699, 1e-9));
      expect(usd.selling, closeTo(49.0582, 1e-9));
      expect(usd.spread!, greaterThan(0));
      expect(usd.mid!, greaterThan(usd.buying!));
      expect(usd.hasData, isTrue);

      // Banknot yoksa efektif kullanilir.
      final eur = map['EUR']!;
      expect(eur.buying, closeTo(57.5, 1e-9));
      expect(eur.banknoteBuying, isNull);
    });

    test('bozuk XML -> ParseFailure, sahte deger uretilmez', () async {
      final p = TcmbCurrencyProvider(
        ApiClient(
          client: MockClient((_) async => http.Response('<bozuk', 200)),
        ),
      );
      final res = await p.fetchToday();
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<ParseFailure>());
    });

    test('kod listesinde olmayan para birimi secilmez', () async {
      final p = TcmbCurrencyProvider(
        ApiClient(
          client: MockClient((_) async => http.Response(tcmbXml, 200)),
        ),
      );
      final res = await p.fetchCurrencies(const {'GBP'});
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<EmptyFailure>());
    });

    test('TCMB kur verisi "Günlük resmi" tazeliğinde gelir (asla Canlı değil)',
        () async {
      final tcmb = TcmbCurrencyProvider(
        ApiClient(
          client: MockClient((_) async => http.Response(tcmbXml, 200)),
        ),
      );
      final provider = TcmbFxMarketDataProvider(tcmb);

      final res = await provider.fetchQuotes([AssetCatalog.usdTryId]);
      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');

      final q = map![AssetCatalog.usdTryId]!;
      expect(q.freshness, DataFreshness.daily);
      expect(q.freshness.label, 'Günlük resmi');
      expect(q.freshness, isNot(DataFreshness.live));
    });
  });

  // ---------------------------------------------------------------------------
  group('Yahoo JSON ayrıştırma', () {
    const okBody = '''
{"chart":{"result":[{"meta":{
  "currency":"TRY",
  "symbol":"THYAO.IS",
  "regularMarketPrice":292.0,
  "chartPreviousClose":287.0,
  "regularMarketChange":5.0,
  "regularMarketChangePercent":1.7422,
  "regularMarketDayHigh":295.0,
  "regularMarketDayLow":284.0,
  "regularMarketVolume":1234567,
  "fullExchangeName":"Borsa Istanbul"
}}],"error":null}}
''';

    test('fiyat, onceki kapanis ve % degisim okunur', () async {
      final y = YahooFinanceProvider(
        ApiClient(
          client: MockClient((_) async => http.Response(okBody, 200)),
        ),
      );
      final res = await y.fetchQuote('THYAO.IS');
      final m = res.dataOrNull;
      expect(m, isNotNull, reason: '${res.failureOrNull}');
      expect(m!.price, closeTo(292.0, 1e-9));
      expect(m.effectivePreviousClose, closeTo(287.0, 1e-9));
      expect(m.changePercent, closeTo(1.7422, 1e-9));
      expect(m.effectiveChangePercent, closeTo(1.7422, 1e-9));
      expect(m.dayHigh, closeTo(295.0, 1e-9));
      expect(m.currency, 'TRY');
      expect(m.hasData, isTrue);
    });

    test('hata govdesi -> hata doner, fiyat uydurulmaz', () async {
      final y = YahooFinanceProvider(
        ApiClient(
          client: MockClient(
            (_) async => http.Response(
              '{"chart":{"result":null,"error":{"code":"Not Found",'
              '"description":"No data"}}}',
              404,
            ),
          ),
        ),
      );
      final res = await y.fetchQuote('OLMAYAN.IS');
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });

    test('gecersiz JSON -> hata doner', () async {
      final y = YahooFinanceProvider(
        ApiClient(
          client: MockClient((_) async => http.Response('bu json degil', 200)),
        ),
      );
      final res = await y.fetchQuote('THYAO.IS');
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('RSS ayrıştırma (yalnizca baslik/ozet/baglanti)', () {
    const rss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test Beslemesi</title>
    <item>
      <title>TCMB politika faizini sabit tuttu</title>
      <link>https://example.com/haber/1</link>
      <description>&lt;p&gt;Kısa özet metni.&lt;/p&gt;</description>
      <pubDate>Fri, 02 Oct 2026 10:00:00 +0300</pubDate>
      <guid>https://example.com/haber/1</guid>
    </item>
    <item>
      <title>Altın rekor seviyede</title>
      <link>https://example.com/haber/2</link>
      <description>İkinci özet.</description>
      <pubDate>Fri, 02 Oct 2026 09:00:00 +0300</pubDate>
      <guid>https://example.com/haber/2</guid>
    </item>
  </channel>
</rss>
''';

    RssFeed feed() => RssFeed(
          url: Uri.parse('https://example.com/rss'),
          defaultCategory: NewsCategory.ekonomi,
          sourceName: 'Test Kaynak',
        );

    test('baslik, baglanti, ozet ve kategori okunur', () async {
      final p = NewsRssProvider(
        ApiClient(
          client: MockClient(
            (_) async => http.Response(
              rss,
              200,
              headers: const {'content-type': 'text/xml; charset=utf-8'},
            ),
          ),
        ),
      );

      final res = await p.fetchFeed(feed());
      final items = res.dataOrNull;
      expect(
        items,
        isNotNull,
        reason: '${res.failureOrNull} / cause=${res.failureOrNull?.cause}',
      );
      expect(items, hasLength(2));

      final first = items!.first;
      expect(first.title, 'TCMB politika faizini sabit tuttu');
      expect(first.url, 'https://example.com/haber/1');
      expect(first.source, 'Test Kaynak');
      expect(first.category, NewsCategory.ekonomi);
      expect(first.summary, isNotNull);
      expect(first.summary!.length, lessThan(300),
          reason: 'ozet kisa kalmali - tam metin degil');
      expect(first.publishedAt.year, 2026);
      expect(first.publishedAt.month, 10);
      expect(first.publishedAt.day, 2);
      expect(first.publishedAt.hour, 10);
    });

    test('bozuk RSS -> hata, haber uretilmez', () async {
      final p = NewsRssProvider(
        ApiClient(
          client: MockClient((_) async => http.Response('bozuk', 200)),
        ),
      );
      final res = await p.fetchFeed(feed());
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });

    // Cp1254 (ISO-8859-9 ile ayni Turkce karakterler) baytlari.
    List<int> toTurkish1254(String s) {
      const special = <String, int>{
        'Ğ': 0xD0, 'İ': 0xDD, 'Ş': 0xDE,
        'ğ': 0xF0, 'ı': 0xFD, 'ş': 0xFE,
      };
      final out = <int>[];
      for (final r in s.runes) {
        final ch = String.fromCharCode(r);
        if (special.containsKey(ch)) {
          out.add(special[ch]!);
        } else if (r < 0x100) {
          out.add(r);
        } else {
          throw StateError('cp1254 disi karakter test metninde: $ch');
        }
      }
      return out;
    }

    test('UTF-8 olmayan (windows-1254) besleme dusmez, Turkce dogru okunur',
        () async {
      // Eski hata: getXmlText her govdeyi sikisik UTF-8 ile cozuyordu;
      // bu baytlarda FormatException firlatip haber akisini tamamen
      // dusuruyordu. Charset burada **yalnizca XML declaration'da**.
      const xml = '''
<?xml version="1.0" encoding="windows-1254"?>
<rss version="2.0"><channel><title>Test</title>
<item>
  <title>Gram altın şubat talebiyle yükseldi</title>
  <link>https://example.com/haber/3</link>
  <description>Özet: güçlü talep, ğ İ Ş ı</description>
  <pubDate>Fri, 02 Oct 2026 10:00:00 +0300</pubDate>
  <guid>https://example.com/haber/3</guid>
</item>
</channel></rss>
''';
      final p = NewsRssProvider(
        ApiClient(
          client: MockClient(
            (_) async => http.Response.bytes(
              toTurkish1254(xml),
              200,
              // Content-Type charset **yok** -> XML declaration okunmali.
              headers: const {'content-type': 'application/rss+xml'},
            ),
          ),
        ),
      );

      final res = await p.fetchFeed(feed());
      final items = res.dataOrNull;
      expect(items, isNotNull,
          reason: '${res.failureOrNull} / cause=${res.failureOrNull?.cause}');
      expect(items!.single.title, 'Gram altın şubat talebiyle yükseldi');
      expect(items.single.summary, contains('güçlü'));
      expect(items.single.summary, contains('ğ'));
    });

    test('pubDate ofseti sayilir: +0300 ile +0000 ayni andir', () async {
      // Eski hata: ofset hic okunmuyor, saat cihaz yerel zamani saniliyordu.
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Test</title>
<item>
  <title>Istanbul saatiyle</title>
  <link>https://example.com/haber/a</link>
  <pubDate>Fri, 02 Oct 2026 10:00:00 +0300</pubDate>
  <guid>https://example.com/haber/a</guid>
</item>
<item>
  <title>UTC saatiyle</title>
  <link>https://example.com/haber/b</link>
  <pubDate>Fri, 02 Oct 2026 07:00:00 +0000</pubDate>
  <guid>https://example.com/haber/b</guid>
</item>
<item>
  <title>GMT etiketiyle</title>
  <link>https://example.com/haber/c</link>
  <pubDate>Fri, 02 Oct 2026 07:00:00 GMT</pubDate>
  <guid>https://example.com/haber/c</guid>
</item>
</channel></rss>
''';
      final p = NewsRssProvider(
        ApiClient(
          client: MockClient((_) async => http.Response(xml, 200)),
        ),
      );

      final res = await p.fetchFeed(feed());
      final items = res.dataOrNull;
      expect(items, isNotNull, reason: '${res.failureOrNull}');
      expect(items, hasLength(3));

      NewsItem byGuid(String g) =>
          items!.firstWhere((i) => i.url.endsWith(g));
      final ist = byGuid('/a');
      final utc = byGuid('/b');
      final gmt = byGuid('/c');

      expect(ist.publishedAt.millisecondsSinceEpoch,
          utc.publishedAt.millisecondsSinceEpoch,
          reason: '+0300 10:00 ile +0000 07:00 ayni an olmali');
      expect(gmt.publishedAt.millisecondsSinceEpoch,
          utc.publishedAt.millisecondsSinceEpoch);
      // Gercek an dogrulamasi (cihaz saat diliminden bagimsiz):
      expect(ist.publishedAt.toUtc(), DateTime.utc(2026, 10, 2, 7, 0));
    });
  });

  // ---------------------------------------------------------------------------
  group('Haber repository - arayuz takas + onbellek', () {
    test('NewsProvider uzerinden calisir ve onbellekler', () async {
      final src = FakeNewsSource();
      final repo = NewsRepositoryImpl(
        src,
        cacheTtl: const Duration(minutes: 5),
      );

      final a = await repo.getBreakingNews(limit: 5);
      final b = await repo.getBreakingNews(limit: 5);

      expect(a.dataOrNull, isNotNull);
      expect(b.dataOrNull, isNotNull);
      expect(src.calls, 1, reason: 'ikinci cagri onbellekten gelmeli');
      expect(a.dataOrNull!.single.title, 'TCMB faizi sabit tuttu');
    });

    test('kaynak hatasi haber uretmez', () async {
      final repo = NewsRepositoryImpl(FakeNewsSource(fail: true));
      final res = await repo.getBreakingNews();
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('Ekonomik takvim - dürüstlük', () {
    test('kaynak null ise EmptyFailure (uydurma olay yok)', () async {
      final repo = EconomicCalendarRepositoryImpl(null);
      final res = await repo.getEvents(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 8),
      );
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<EmptyFailure>());
    });

    test('gecersiz aralik -> BadRequestFailure', () async {
      final repo = EconomicCalendarRepositoryImpl(FakeCalendarSource());
      final t = DateTime(2026, 10, 1);
      final res = await repo.getEvents(from: t, to: t);
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<BadRequestFailure>());
    });

    test('ayni aralik ikinci kez sorgulanmaz (onbellek)', () async {
      final src = FakeCalendarSource();
      final repo = EconomicCalendarRepositoryImpl(src);
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 10, 8);

      await repo.getEvents(from: from, to: to);
      await repo.getEvents(from: from, to: to);
      expect(src.calls, 1);

      await repo.getEvents(from: from, to: DateTime(2026, 10, 15));
      expect(src.calls, 2, reason: 'farkli aralik onbellek disidir');
    });

    test('kaynak hatasi ve onbellek yoksa hata doner', () async {
      final repo = EconomicCalendarRepositoryImpl(FakeCalendarSource(fail: true));
      final res = await repo.getEvents(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 8),
      );
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isA<NetworkFailure>());
    });
  });

  // ---------------------------------------------------------------------------
  group('MarketDataRepository - kaynak secimi ve turev hesap', () {
    Quote factory(String id) {
      switch (id) {
        case AssetCatalog.onsAltinId:
          return _directQuote(id, price: 4000, pct: 1.0);
        case AssetCatalog.usdTryId:
          return _directQuote(id, price: 50, pct: 2.0);
        default:
          return _directQuote(id, price: 100);
      }
    }

    MarketDataRepositoryImpl build() => MarketDataRepositoryImpl(
          sources: [
            FakeMarketSource(
              id: 'alpha',
              supported: const {
                AssetCatalog.onsAltinId,
                AssetCatalog.bist100Id,
              },
              quoteFactory: factory,
            ),
            FakeMarketSource(
              id: 'beta',
              supported: const {
                AssetCatalog.usdTryId,
                AssetCatalog.eurTryId,
              },
              quoteFactory: factory,
            ),
          ],
          staleAfter: const Duration(minutes: 5),
        );

    test('her varlik kendi kaynagindan gelir', () async {
      final repo = build();
      final res = await repo.getQuotes(const [
        AssetCatalog.bist100Id,
        AssetCatalog.usdTryId,
      ]);

      final map = res.dataOrNull;
      expect(map, isNotNull, reason: '${res.failureOrNull}');
      expect(map!.keys, containsAll([
        AssetCatalog.bist100Id,
        AssetCatalog.usdTryId,
      ]));
      expect(map[AssetCatalog.bist100Id]!.price, 100);
      expect(map[AssetCatalog.usdTryId]!.price, 50);
    });

    test('gram altin bilesenlerinden hesaplanir (kaynak etiketi Hesaplanan)',
        () async {
      final repo = build();
      final res = await repo.getQuotes(const [AssetCatalog.gramAltinId]);

      final gram = res.dataOrNull?[AssetCatalog.gramAltinId];
      expect(gram, isNotNull, reason: '${res.failureOrNull}');

      // gram = ons * USD/TRY / 31.1034768
      const expected = 4000.0 * 50 / 31.1034768;
      expect(gram!.price!, closeTo(expected, 1e-6));
      expect(gram.source, QuoteSourceLabel.calculated);

      // Iki bileşenli getiri: %1 (ons) + %2 (kur) -> %3,02
      expect(gram.changePercent, closeTo(3.02, 1e-9));
      expect(gram.changePercent!.isFinite, isTrue);
    });

    test('ceyrek altin gram altinin carpanidir', () async {
      final repo = build();
      final res = await repo.getQuotes(const [
        AssetCatalog.gramAltinId,
        AssetCatalog.ceyrekAltinId,
      ]);

      final map = res.dataOrNull!;
      final gram = map[AssetCatalog.gramAltinId]!.price!;
      final ceyrek = map[AssetCatalog.ceyrekAltinId]!;
      expect(ceyrek.price!, closeTo(gram * 1.75, 1e-9));
      expect(ceyrek.source, QuoteSourceLabel.calculated);
    });

    test('kaynagi olmayan varlik icin fiyat uydurulmaz', () async {
      final repo = build();
      final res = await repo.getQuotes(const [
        AssetCatalog.gramAltinId, // gelir
        'olmayan-varlik', // tanimsiz
      ]);

      final map = res.dataOrNull;
      expect(map, isNotNull);
      expect(map!.containsKey('olmayan-varlik'), isFalse);
      expect(map[AssetCatalog.gramAltinId], isNotNull);
    });

    test('hicbir kaynak desteklemiyorsa hata doner, bos fiyat degil', () async {
      final repo = MarketDataRepositoryImpl(
        sources: [FakeMarketSource(id: 'bos', supported: const {})],
        staleAfter: const Duration(minutes: 5),
      );
      final res = await repo.getQuotes(const [AssetCatalog.bist100Id]);
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });

    test('bos liste -> EmptyFailure', () async {
      final repo = build();
      final res = await repo.getQuotes(const []);
      expect(res.failureOrNull, isA<EmptyFailure>());
    });

    test('onbellek TTL icinde tekrar cagri yapmaz', () async {
      final repo = build();
      await repo.getQuotes(const [AssetCatalog.bist100Id]);

      final alpha = repo.sources.first as FakeMarketSource;
      final first = alpha.calls;
      expect(first, greaterThan(0));

      await repo.getQuotes(const [AssetCatalog.bist100Id]);
      expect(alpha.calls, first, reason: 'TTL icinde onbellek kullanilmali');

      repo.invalidateCache();
      await repo.getQuotes(const [AssetCatalog.bist100Id]);
      expect(alpha.calls, first + 1, reason: 'invalidate sonrasi yeniden cagri');
    });
  });

  // ---------------------------------------------------------------------------
  // AKIS: Data Provider -> Stream -> Repository -> UI  (GOLD v2)
  // ---------------------------------------------------------------------------
  group('Fiyat akisi (watchQuotes)', () {
    test('refreshInterval besleyen saglayicidan okunur', () {
      final repo = MarketDataRepositoryImpl(
        sources: [
          FakeMarketSource(
            id: 'hizli',
            supported: const {AssetCatalog.bist100Id},
            refreshInterval: const Duration(seconds: 30),
          ),
          FakeMarketSource(
            id: 'yavas',
            supported: const {AssetCatalog.usdTryId},
            refreshInterval: const Duration(minutes: 5),
          ),
        ],
      );

      expect(repo.refreshInterval(const [AssetCatalog.bist100Id]),
          const Duration(seconds: 30));
      expect(repo.refreshInterval(const [AssetCatalog.usdTryId]),
          const Duration(minutes: 5));
      // Liste ritmini en hizli saglayici belirler.
      expect(
        repo.refreshInterval(const [
          AssetCatalog.bist100Id,
          AssetCatalog.usdTryId,
        ]),
        const Duration(seconds: 30),
      );
    });

    test('kadans: liste 3 sn, odaklanmis detay 1 sn, TCMB 5 dk aynen kalir',
        () {
      final yahoo = YahooMarketDataProvider(
        YahooFinanceProvider(
          ApiClient(client: MockClient((_) async => http.Response('ok', 200))),
        ),
      );
      final tcmb = TcmbFxMarketDataProvider(
        TcmbCurrencyProvider(
          ApiClient(client: MockClient((_) async => http.Response('ok', 200))),
        ),
      );

      // V2: kullanici "ana sayfada her 2-3 saniyede yenilensin" istemisti.
      expect(yahoo.refreshInterval, const Duration(seconds: 3));

      // Detay ekraninda tek varlik izlenir -> listelerden daha hizli.
      expect(CachePolicy.focusedQuoteRefreshInterval,
          const Duration(seconds: 1));

      // Gunluk resmi kur **hizlandirilmaz**: yeni veri getirmez.
      expect(tcmb.refreshInterval, const Duration(minutes: 5));
    });

    test('ilk deger saglayicidan gelir, aralik istegi tetikler', () async {
      final src = FlakyMarketSource();
      final repo = MarketDataRepositoryImpl(sources: [src]);

      final events = <Map<String, Quote>>[];
      final sub = repo
          .watchQuotes(const [AssetCatalog.bist100Id])
          .listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      await sub.cancel();

      expect(events, isNotEmpty, reason: 'ilk deger akisa gecmis olmali');
      expect(events.first[AssetCatalog.bist100Id], isNotNull);
      expect(events.first[AssetCatalog.bist100Id]!.isStale, isFalse);
      expect(src.calls, greaterThan(1),
          reason: 'zamanlayici aralikta tekrar istek atmis olmali');
    });

    test('ag kopmasinda son GERCEK veri isStale ile korunur', () async {
      final src = FlakyMarketSource();
      final repo = MarketDataRepositoryImpl(sources: [src]);

      final events = <Map<String, Quote>>[];
      final sub = repo
          .watchQuotes(const [AssetCatalog.bist100Id])
          .listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 130));
      expect(events, isNotEmpty);
      expect(events.last[AssetCatalog.bist100Id]!.isStale, isFalse);
      expect(events.last[AssetCatalog.bist100Id]!.price, isNotNull);

      src.failNext = true;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await sub.cancel();

      expect(src.failures, greaterThan(0), reason: 'gercekten hata alindi');
      expect(events.length, greaterThan(1), reason: 'akisa hata sonrasi veri');

      final last = events.last[AssetCatalog.bist100Id]!;
      expect(last.isStale, isTrue,
          reason: 'son gercek veri "guncel degil" isaretlenmeli');
      expect(last.price, isNotNull,
          reason: 'eski fiyat korunur; sifirlanmaz/uydurulmaz');
      expect(last.price!.isFinite, isTrue);
      // Akis hata sirasinda uydurma fiyat uretmez: goruntulenen deger
      // saglayicidan gercekten gelmis bir fiyat olmalidir.
      expect(src.deliveredPrices.contains(last.price), isTrue,
          reason: 'gosterilen fiyat saglayicidan gelmis olmali');
    });

    test('ilk istek basarisiz ve hic veri yoksa akis hata yayar', () async {
      final src = FlakyMarketSource()..failNext = true;
      final repo = MarketDataRepositoryImpl(sources: [src]);

      await expectLater(
        repo.watchQuotes(const [AssetCatalog.bist100Id]).first,
        throwsA(isA<StateFailure>()),
      );
    });

    test('isActive false iken ag istegi atilmaz', () async {
      final src = FlakyMarketSource();
      final repo = MarketDataRepositoryImpl(sources: [src]);
      var active = false;

      final events = <Map<String, Quote>>[];
      final sub = repo
          .watchQuotes(
            const [AssetCatalog.bist100Id],
            isActive: () => active,
          )
          .listen(events.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(src.calls, 0, reason: 'arka planda istek atilmamali');
      expect(events, isEmpty);

      active = true; // One donuldu
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      expect(src.calls, greaterThan(0), reason: 'one donunce tazelenmeli');
      expect(events, isNotEmpty);
    });

    test('ag hatasinda ritim ustel olarak yavaslar, basarida normale doner',
        () async {
      final src = FlakyMarketSource();
      final repo = MarketDataRepositoryImpl(sources: [src]);

      final sub =
          repo.watchQuotes(const [AssetCatalog.bist100Id]).listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(src.calls, greaterThan(1),
          reason: 'basariliyken 40 ms ritminde birden cok istek atilmali');

      // Ag gider: bekleme 2x, 4x, 8x ... olarak uzar (istek limitine
      // takilmamak icin); hep 40 ms ile deneseydi ~16 istek giderdi.
      src.failNext = true;
      final beforeFail = src.calls;
      await Future<void>.delayed(const Duration(milliseconds: 640));
      final duringFail = src.calls - beforeFail;
      expect(duringFail, lessThanOrEqualTo(5),
          reason: '640 ms boyunca surekli hatada en fazla birkac istek '
              'atilmali; bulunan: $duringFail');

      // Ag geri geldi: geri cekilme sifirlanir ve ritim normale doner.
      src.failNext = false;
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      final t0 = src.calls;
      await Future<void>.delayed(const Duration(milliseconds: 240));
      final recovered = src.calls - t0;
      expect(recovered, greaterThanOrEqualTo(3),
          reason: 'basari sonrasi 240 ms icinde ~6 istek beklenir; '
              'bulunan: $recovered');

      await sub.cancel();
    });

    test('bos liste -> akis hata yayar (sahte deger uretilmez)', () async {
      final repo = MarketDataRepositoryImpl(
        sources: [FakeMarketSource(id: 'x', supported: const {})],
      );
      await expectLater(
        repo.watchQuotes(const []).first,
        throwsA(isA<StateFailure>()),
      );
    });
  });
}

/// Basari <-> basarisizlik gecisebilen saglayici (akisa dayanim testleri).
class FlakyMarketSource implements MarketDataProvider {
  bool failNext = false;
  int calls = 0;
  int failures = 0;

  /// Saglayicidan **gercekten** gelmis fiyatlar (uydurma kontrolu icin).
  final Set<double> deliveredPrices = <double>{};

  @override
  String get id => 'flaky';

  @override
  String get displayName => 'Dalgalı';

  /// Cok kisa aralik: testlerin zaman icinde kalmasini saglar.
  @override
  Duration get refreshInterval => const Duration(milliseconds: 40);

  @override
  bool supports(String assetId) => assetId == AssetCatalog.bist100Id;

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    calls++;
    if (failNext) {
      failures++;
      return const Err(NetworkFailure('Sahte ag hatasi.'));
    }
    final price = 100.0 + calls;
    deliveredPrices.add(price);
    return Success({
      for (final id in assetIds)
        id: Quote(
          assetId: id,
          source: QuoteSourceLabel.market,
          updatedAt: DateTime.now(),
          price: price,
          freshness: DataFreshness.delayed,
        ),
    });
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err(EmptyFailure('Mum desteklenmiyor.'));
}
