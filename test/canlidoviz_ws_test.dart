import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/cache/cache_policy.dart';
import 'package:gold/core/error/failures.dart';
import 'package:gold/data/canlidoviz/canlidoviz_protocol.dart';
import 'package:gold/data/canlidoviz/canlidoviz_socket.dart';
import 'package:gold/data/providers/canlidoviz_provider.dart';
import 'package:gold/data/repositories/market_data_repository_impl.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/providers/market_data_provider.dart';
import 'package:http/http.dart' as http;

/// Gercek ag kaydindan alinmis cerceveler (fixture - canli uc test edilmez).
const handshakeFrame =
    '0{"sid":"KHF95MWcbw4GL6ZwAAzu","upgrades":[],"pingInterval":25000,'
    '"pingTimeout":10000,"maxPayload":1000000}';
const namespaceAckFrame = '40{"sid":"CBrSu5IWlxpkI8vPAAzv"}';
const priceFrame =
    '42["c",["12|4147.21|4147.83||","50|55.1154|55.22||"]]';

/// Testlerde gercek WebSocket ACMAZ: provider'a enjekte edilen sahte akis.
class FakePriceStream implements CanlidovizPriceStream {
  FakePriceStream({this.connecting = false, this.connected = false});

  bool connecting;
  bool connected;
  var started = false;
  var stopped = false;
  final Map<int, CanlidovizTick> ticks = <int, CanlidovizTick>{};

  @override
  void start() => started = true;

  @override
  void stop() => stopped = true;

  @override
  bool get isConnecting => connecting;

  @override
  bool get isConnected => connected;

  @override
  CanlidovizTick? latest(int cid) => ticks[cid];
}

/// Gold API benzeri yedek kaynak: CanlıDöviz basarisizken devreye girmeli.
class FakeFallbackSource implements MarketDataProvider {
  var calls = 0;

  @override
  String get id => 'fake-fallback';

  @override
  String get displayName => 'Fake Fallback';

  @override
  Duration get refreshInterval => const Duration(seconds: 60);

  @override
  bool supports(String assetId) => assetId == AssetCatalog.onsAltinId;

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    calls++;
    return Success({
      AssetCatalog.onsAltinId: Quote(
        assetId: AssetCatalog.onsAltinId,
        source: QuoteSourceLabel.market,
        updatedAt: DateTime.now(),
        price: 4137.0,
        currency: 'USD',
        freshness: DataFreshness.live,
      ),
    });
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async =>
      const Err(EmptyFailure('desteklenmiyor'));
}

CanlidovizTick tick({
  int cid = 12,
  double? bid = 4147.21,
  double? ask = 4147.83,
  DateTime? receivedAt,
}) =>
    CanlidovizTick(
      cid: cid,
      bid: bid,
      ask: ask,
      receivedAt: receivedAt ?? DateTime.now(),
    );

/// Testlerde **gercek aga cikilmaz**: `previousClose` arka plan istegini
/// bu sahte istemci yakalar ve 500 dondurur (kapanis alinamaz -> quote
/// previousClose'suz kalir; sahte kapanis URETILMEZ).
class NoNetworkHttpClient extends http.BaseClient {
  final List<Uri> requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
  }
}

CanlidovizProvider buildProvider(FakePriceStream stream) => CanlidovizProvider(
      priceStream: stream,
      httpClient: NoNetworkHttpClient(),
    );

void main() {
  group('CanlidovizProtocol - WebSocket protokolu', () {
    test('abonelik cercevesi birebir ayni bicimde', () {
      expect(
        CanlidovizProtocol.subscriptionFrame(['XAU/USD']),
        '42["us",{"t":[],"c":["XAU/USD"],"m":false}]',
      );
      expect(
        CanlidovizProtocol.subscriptionFrame(['XAU/USD', 'USD']),
        '42["us",{"t":[],"c":["XAU/USD","USD"],"m":false}]',
      );
      // Topic alani sitenin istemcisiyle ayni ("t") - kodlarla birlikte.
      expect(
        CanlidovizProtocol.subscriptionFrame(
          CanlidovizProtocol.streamCodes,
          topics: CanlidovizProtocol.streamTopics,
        ),
        '42["us",{"t":["GOLD"],"c":['
        '"XAU/USD","GA","GAG","C","USD","EUR","GBP","CHF","XU100","XU030",'
        '"XBRUSD","Y","T","JPY","CAD","AUD","CNY","XAG/USD","COIL",'
        '"XPT/USD","DXY","SPX","XU050","BTC","ETH","XPD/USD","GRPLTN",'
        '"COPPER","NGAS"],"m":false}]',
      );
    });

    test('varlik -> abonelik kodu mappingi (kodlu + topic uyeleri)', () {
      expect(
        CanlidovizProtocol.assetToStreamCode(AssetCatalog.onsAltinId),
        'XAU/USD',
      );
      expect(
        CanlidovizProtocol.streamCodes.length,
        CanlidovizProtocol.streamCodesByAsset.length,
      );
      expect(
        CanlidovizProtocol.streamAssetIds.length,
        CanlidovizProtocol.streamCodesByAsset.length +
            CanlidovizProtocol.streamTopicOnlyAssetIds.length,
      );
      expect(
        CanlidovizProtocol.streamAssetIds,
        contains(AssetCatalog.onsAltinId),
      );

      // Topic uyesi olan, kodu OLMAYAN varliklar da akisa baglanir.
      for (final id in [
        AssetCatalog.cumhuriyetAltinId,
        AssetCatalog.ataAltinId,
        AssetCatalog.bilezik22Id,
        AssetCatalog.resatAltinId,
      ]) {
        expect(CanlidovizProtocol.assetToStreamCode(id), isNull, reason: id);
        expect(CanlidovizProtocol.streamAssetIds, contains(id), reason: id);
      }

      // Akisa baglanmayanlar: mum-only (14/18 ayar) + katalog disi.
      expect(
          CanlidovizProtocol.assetToStreamCode(AssetCatalog.ayar14AltinId), isNull);
      expect(
          CanlidovizProtocol.assetToStreamCode(AssetCatalog.ayar18AltinId), isNull);
      expect(
        CanlidovizProtocol.streamAssetIds,
        isNot(contains(AssetCatalog.ayar14AltinId)),
      );
      expect(CanlidovizProtocol.assetToStreamCode('unknown-asset'), isNull);
    });

    test('el sikisma + ping araligi cozumlenir', () {
      expect(CanlidovizProtocol.isHandshake(handshakeFrame), isTrue);
      expect(
        CanlidovizProtocol.handshakePingInterval(handshakeFrame),
        const Duration(seconds: 25),
      );
      expect(CanlidovizProtocol.isHandshake(priceFrame), isFalse);
      expect(CanlidovizProtocol.handshakePingInterval(priceFrame), isNull);
      expect(CanlidovizProtocol.handshakePingInterval('0{bozuk'), isNull);
    });

    test('ping / namespace onayi siniflandirmasi', () {
      expect(CanlidovizProtocol.isPing('2'), isTrue);
      expect(CanlidovizProtocol.isPing('40'), isFalse);
      expect(CanlidovizProtocol.isPing('3'), isFalse);
      expect(CanlidovizProtocol.isNamespaceAck(namespaceAckFrame), isTrue);
      expect(CanlidovizProtocol.isNamespaceAck('42["c",[]]'), isFalse);
      expect(CanlidovizProtocol.isPriceFrame(priceFrame), isTrue);
      expect(CanlidovizProtocol.isPriceFrame('42["us",{}]'), isFalse);
    });

    test('fiyat cercevesi: bid/ask + alim ani', () {
      final at = DateTime.utc(2026, 10, 6, 1, 2, 3);
      final ticks = CanlidovizProtocol.parsePriceFrame(
        priceFrame,
        receivedAt: at,
      );
      expect(ticks, hasLength(2));

      expect(ticks[0].cid, 12);
      expect(ticks[0].bid, 4147.21);
      expect(ticks[0].ask, 4147.83);
      expect(ticks[0].price, 4147.21, reason: 'fiyat = bid (sitenin gosterdigi ana fiyat)');
      expect(ticks[0].receivedAt, at);

      expect(ticks[1].cid, 50);
      expect(ticks[1].price, 55.1154);
    });

    test('tek tarafli kayit: bid yoksa ask, ikisi de yoksa atlanir', () {
      final at = DateTime.now();

      // bid var, ask yok (canli gozlenen bicim: `12|4150.13|||`)
      final bidOnly =
          CanlidovizProtocol.parseTick('12|4150.13|||', receivedAt: at);
      expect(bidOnly, isNotNull);
      expect(bidOnly!.bid, 4150.13);
      expect(bidOnly.ask, isNull);
      expect(bidOnly.price, 4150.13);

      // ask var, bid yok
      final askOnly =
          CanlidovizProtocol.parseTick('1340||97.31|97.31|', receivedAt: at);
      expect(askOnly, isNotNull);
      expect(askOnly!.bid, isNull);
      expect(askOnly.ask, 97.31);
      expect(askOnly.price, 97.31);

      // hic gecerli fiyat yok -> fiyat uretilemez, kayit atlanir
      expect(CanlidovizProtocol.parseTick('12|||', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('12|-1|-2|', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('12|0|0|', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('12|abc|xyz|', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('12|NaN|Infinity|', receivedAt: at), isNull);

      // Tek alan gecersizse diger taraftaki GERCEK deger kullanilir
      // (uydurma fiyat uretilmez, gecersiz sayi asla fiyat olmaz).
      final askFallback = CanlidovizProtocol.parseTick('12|abc|1.0|',
          receivedAt: at)!;
      expect(askFallback.bid, isNull);
      expect(askFallback.ask, 1.0);
      expect(askFallback.price, 1.0);
      expect(
        CanlidovizProtocol.parseTick('12|NaN|1.0|', receivedAt: at)!.price,
        1.0,
      );
      expect(
        CanlidovizProtocol.parseTick('12|Infinity|1.0|', receivedAt: at)!.price,
        1.0,
      );
    });

    test('gecersiz cid / eksik alan -> tick uretilmez', () {
      final at = DateTime.now();
      expect(CanlidovizProtocol.parseTick('0|1|2|', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('-5|1|2|', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('abc|1|2|', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('12', receivedAt: at), isNull);
      expect(CanlidovizProtocol.parseTick('12|100.5', receivedAt: at), isNull);

      // 3 alan yeterli: sonraki alanlar (last/change) opsiyoneldir.
      final minimal =
          CanlidovizProtocol.parseTick('12|100.5|101.5', receivedAt: at)!;
      expect(minimal.bid, 100.5);
      expect(minimal.ask, 101.5);
      expect(minimal.price, 100.5);
    });

    test('fiyat disindaki / bozuk cerceveler bos liste dondurur', () {
      final at = DateTime.now();
      expect(
        CanlidovizProtocol.parsePriceFrame('42["us",{}]', receivedAt: at),
        isEmpty,
      );
      expect(
        CanlidovizProtocol.parsePriceFrame('42["c",bozuk', receivedAt: at),
        isEmpty,
      );
      expect(
        CanlidovizProtocol.parsePriceFrame('40{"sid":"x"}', receivedAt: at),
        isEmpty,
      );
      expect(
        CanlidovizProtocol.parsePriceFrame('42["c",[123]]', receivedAt: at),
        isEmpty,
      );
      // Gecersiz kayitlar elenir, gecerli olan kalir.
      final mixed = CanlidovizProtocol.parsePriceFrame(
        '42["c",["bozuk","12|100|101||","x|1|2|"]]',
        receivedAt: at,
      );
      expect(mixed, hasLength(1));
      expect(mixed.single.cid, 12);
    });

    test('wsUrl kanitli adres', () {
      expect(
        CanlidovizProtocol.wsUrl,
        'wss://s.canlidoviz.com/socket.io/?EIO=4&transport=websocket',
      );
    });
  });

  group('CanlidovizProvider - anlik fiyat (P1)', () {
    late FakePriceStream stream;

    setUp(() => stream = FakePriceStream());

    CanlidovizProvider build() => buildProvider(stream);

    test('taze tik + bagli akis -> Success (price=bid, live, Piyasa)', () async {
      stream
        ..connected = true
        ..ticks[12] = tick(bid: 4147.21, ask: 4147.83);

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
      final map = r.dataOrNull;
      expect(map, isNotNull);

      final q = map![AssetCatalog.onsAltinId]!;
      expect(q.price, 4147.21);
      expect(q.bid, 4147.21);
      expect(q.ask, 4147.83);
      expect(q.currency, 'USD');
      expect(q.source, QuoteSourceLabel.market);
      expect(q.freshness, DataFreshness.live);
      expect(q.isStale, isFalse);
      expect(
        q.updatedAt.difference(stream.ticks[12]!.receivedAt).inMilliseconds,
        0,
        reason: 'updatedAt = tikin alim ani',
      );
    });

    test('ask-only tik -> fiyat ask olur', () async {
      stream
        ..connected = true
        ..ticks[12] = tick(bid: null, ask: 4148.5);

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
      expect(r.dataOrNull![AssetCatalog.onsAltinId]!.price, 4148.5);
    });

    test('akis bagli degilse EmptyFailure (fallback zinciri devreye girer)', () async {
      stream.connected = false;
      stream.ticks[12] = tick(); // tik olsa bile bagli degil -> fiyat yok

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('tik bayatsa (2 dk) fiyat verilmez - bayat fiyat satisi yok', () async {
      stream
        ..connected = true
        ..ticks[12] = tick(
          receivedAt: DateTime.now().subtract(
            CanlidovizProvider.maxTickAge + const Duration(seconds: 1),
          ),
        );

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([AssetCatalog.onsAltinId]);
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('akisa baglanmayan varlik (14/18 ayar) istenirse fiyat uretilmez',
        () async {
      // 14/18 ayar CanlıDöviz'de MUM kaynagidir; akis uyesi DEGILDIR
      // (kodu/topic uyesi dogrulanmadi) - quote uydurulmaz.
      stream
        ..connected = true
        ..ticks[16] = tick(cid: 16, bid: 3738.92);

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([
        AssetCatalog.ayar14AltinId,
        AssetCatalog.ayar18AltinId,
        'unknown-asset',
      ]);
      expect(r.isFailure, isTrue);
      expect(r.failureOrNull, isA<EmptyFailure>());
    });

    test('tik gelmeyen varlik yalnizca ons doner', () async {
      stream
        ..connected = true
        ..ticks[12] = tick();

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([
        AssetCatalog.onsAltinId,
        AssetCatalog.onsGumusId,
      ]);
      final map = r.dataOrNull!;
      expect(map.keys, [AssetCatalog.onsAltinId]);
    });

    test('topic uyesi varlik (cumhuriyet, kodu yok) tick ile fiyat doner',
        () async {
      stream
        ..connected = true
        ..ticks[27] = tick(cid: 27, bid: 43046.74, ask: 43784.11);

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([AssetCatalog.cumhuriyetAltinId]);
      final q = r.dataOrNull![AssetCatalog.cumhuriyetAltinId]!;
      expect(q.price, 43046.74);
      expect(q.ask, 43784.11);
    });

    test('coklu varlik: altin + doviz + endeks tek tik karesinden beslenir',
        () async {
      stream
        ..connected = true
        ..ticks[32] = tick(cid: 32, bid: 6527.16, ask: 6528.11)
        ..ticks[1] = tick(cid: 1, bid: 49.1812, ask: 49.2412)
        ..ticks[846] = tick(cid: 846, bid: 102.184, ask: 102.184);

      final provider = build();
      addTearDown(provider.dispose);

      final r = await provider.fetchQuotes([
        AssetCatalog.gramAltinId,
        AssetCatalog.usdTryId,
        AssetCatalog.dxyId,
        AssetCatalog.platinId, // tik yok -> dusurulur
      ]);
      final map = r.dataOrNull!;
      expect(map.keys, hasLength(3));
      expect(map[AssetCatalog.gramAltinId]!.price, 6527.16);
      expect(map[AssetCatalog.usdTryId]!.price, 49.1812);
      expect(map[AssetCatalog.dxyId]!.price, 102.184);
      expect(map.containsKey(AssetCatalog.platinId), isFalse);
    });
  });

  group('CanlidovizProvider - refreshInterval (ritim)', () {
    late FakePriceStream stream;

    setUp(() => stream = FakePriceStream());

    CanlidovizProvider build() => buildProvider(stream);

    test('akis baslamadi (idle) -> fallback 60 sn', () {
      final provider = build();
      addTearDown(provider.dispose);
      expect(provider.refreshInterval, CanlidovizProvider.fallbackRefreshInterval);
      expect(provider.refreshInterval, const Duration(seconds: 60));
    });

    test('baglanti denemesi sirasinda kisa ritim (acilis yarisi)', () {
      stream.connecting = true;
      final provider = build();
      addTearDown(provider.dispose);
      expect(provider.refreshInterval, CanlidovizProvider.liveRefreshInterval);
      expect(provider.refreshInterval, const Duration(seconds: 2));
    });

    test('bagli + taze tik -> kisa ritim (ekran canli guncellenir)', () {
      stream
        ..connected = true
        ..ticks[12] = tick();
      final provider = build();
      addTearDown(provider.dispose);
      expect(provider.refreshInterval, CanlidovizProvider.liveRefreshInterval);
    });

    test('bagli ama tik bayat -> uzun ritim (yedek kaynak istek seli yok)', () {
      stream
        ..connected = true
        ..ticks[12] = tick(
          receivedAt: DateTime.now().subtract(
            CanlidovizProvider.maxTickAge + const Duration(seconds: 1),
          ),
        );
      final provider = build();
      addTearDown(provider.dispose);
      expect(provider.refreshInterval, CanlidovizProvider.fallbackRefreshInterval);
    });

    test('startStream akisi baslatir, dispose kapatir', () {
      final provider = build();
      expect(stream.started, isFalse);
      provider.startStream();
      expect(stream.started, isTrue);
      provider.dispose();
      expect(stream.stopped, isTrue);
    });
  });

  group('Repository - CanlıDöviz -> Gold API fallback', () {
    late FakePriceStream stream;
    late FakeFallbackSource fallback;
    late MarketDataRepositoryImpl repo;

    setUp(() {
      stream = FakePriceStream();
      fallback = FakeFallbackSource();
      repo = MarketDataRepositoryImpl(
        sources: [buildProvider(stream), fallback],
        staleAfter: CachePolicy.quoteTtl,
      );
    });

    tearDown(() => repo.invalidateCache());

    test('akis tazeyken CanlıDöviz verir, yedek kaynak CAGRILMAZ', () async {
      stream
        ..connected = true
        ..ticks[12] = tick(bid: 4147.21, ask: 4147.83);

      final r = await repo.getQuotes([AssetCatalog.onsAltinId]);
      final q = r.dataOrNull![AssetCatalog.onsAltinId]!;

      expect(q.price, 4147.21, reason: 'WebSocket tikinden gelmeli');
      expect(q.bid, 4147.21);
      expect(fallback.calls, 0, reason: 'taze iken yedek kaynak hic denenmez');
    });

    test('akis kapaliyken yedek kaynak (Gold API) devreye girer', () async {
      stream.connected = false; // CanlıDöviz bagli DEGIL

      final r = await repo.getQuotes([AssetCatalog.onsAltinId]);
      final q = r.dataOrNull![AssetCatalog.onsAltinId]!;

      expect(q.price, 4137.0, reason: 'yedek kaynagin fiyati');
      expect(fallback.calls, 1, reason: 'fallback zinciri calisir');
    });

    test('akis bagli ama tik bayatsa yedek kaynaga dusulur', () async {
      stream
        ..connected = true
        ..ticks[12] = tick(
          receivedAt: DateTime.now().subtract(
            CanlidovizProvider.maxTickAge + const Duration(seconds: 5),
          ),
        );

      final r = await repo.getQuotes([AssetCatalog.onsAltinId]);
      final q = r.dataOrNull![AssetCatalog.onsAltinId]!;

      expect(q.price, 4137.0, reason: 'bayat tik gosterilmez, yedek kullanilir');
      expect(fallback.calls, 1);
    });

    test('tik geldiginde bir sonraki okuma akisa geri doner', () async {
      stream.connected = false;
      await repo.getQuotes([AssetCatalog.onsAltinId]);
      expect(fallback.calls, 1);

      // Akis geldi -> onbellek suresi doldugunda tik okunur.
      repo.invalidateQuotes();
      stream
        ..connected = true
        ..ticks[12] = tick(bid: 4150.5);

      final r = await repo.getQuotes([AssetCatalog.onsAltinId]);
      expect(r.dataOrNull![AssetCatalog.onsAltinId]!.price, 4150.5);
    });

    test('quote zinciri ile mum zinciri ayridir (mum yolu degismez)', () async {
      // CanlıDöviz mum da verir; yedek kaynak mum vermez.
      expect(
        buildProvider(stream).supportsCandles(AssetCatalog.onsAltinId),
        isTrue,
      );
      expect(fallback.supportsCandles(AssetCatalog.onsAltinId), isFalse);
    });
  });
}
