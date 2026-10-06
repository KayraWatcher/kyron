import 'dart:async';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/data_freshness.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import '../canlidoviz/canlidoviz_protocol.dart';
import '../canlidoviz/canlidoviz_socket.dart';

/// CanlıDöviz (`canlidoviz.com`) kaynaklı [MarketDataProvider] uygulaması.
///
/// ## İki AYRI kaynak, tek provider (P0 + P1 + kapsam genişletme)
///
/// | İhtiyaç      | Kaynak | Yol |
/// |--------------|--------|-----|
/// | Geçmiş mum   | `GET a.canlidoviz.com/items/history` | [fetchCandles] (P0) |
/// | Güncel fiyat | `wss://s.canlidoviz.com` WebSocket    | [fetchQuotes] (P1) |
///
///  * `supports(...)` = [CanlidovizProtocol.itemIdsByAsset] icinde **ve**
///    akisa bagli (kod veya topic uyesi) **27 varlik**: Ons/Gram Altın,
///    Gram/Ons Gümüş, Çeyrek/Yarım/Tam/Cumhuriyet/Ata/Bilezik/Reşat,
///    USD/EUR/GBP/CHF/JPY/CAD/AUD/CNY-TRY, BIST100/30/50, DXY, S&P 500,
///    Brent, WTI, Platin.
///  * `supportsCandles(...)` = [CanlidovizProtocol.itemIdsByAsset] icindeki
///    **29 varlik** (yukaridakilere ek olarak 14/18 Ayar - bunlarin
///    akista tik uyesi olmadigi dogrulandi, mum history API'den gelir).
///  * **Quote zinciri**: akış (WebSocket) bağlı ve son tik ≤2 dk taze ise
///    bu varlıkların güncel fiyatını **CanlıDöviz verir**. Değilse
///    [fetchQuotes] hata döndürür ve repository sıradaki adayı dener -
///    yani **fallback zinciri olduğu gibi korunur**. Öncelik kuralı:
///    `app_providers.dart` listesinde CanlıDöviz zaten ilk adaydır -
///    **döviz de buna dahil** (kullanıcı kararı: FX'te canlı interbank
///    birincil, TCMB günlük resmi kur **yedek** olarak korunur).
///  * **previousClose**: WS karelerinde değişim yüzdesi yoktur; kapanış
///    referansı geçmiş (DAILY) isteğiyle arka planda çekilir ve quote'a
///    eklenir - böylece % değişim **uydurulmaz**, gerçek kapanıştan
///    hesaplanır.
///  * Quote ve mum yolları birbirinden **bağımsızdır**: akış kopsa bile
///    mum çekimi (HTTP) etkilenmez, akış olsa bile mum yolu değişmez.
///
/// ## Canlı fiyat kuralları (sahte veri yasağı)
///
///  * Fiyat mesajdaki **bid**'dir (sitendi kendi gösterdiği ana fiyat);
///    bid yoksa `ask`. İki taraf da yoksa tik **atlanır**.
///  * `updatedAt` mesajın alım anıdır (mesaj kaynak zaman damgası taşımaz).
///  * Tik 2 dakikadan bayatsa fiyat **verilmez** - bayat fiyat "Canlı"
///    diye gösterilmez; siradaki kaynak (Gold API/TCMB/Yahoo/Anlik) besler.
///
/// ## Kaynak
///
/// Protokol kanıtları ve doğrulanmış kısıtlar için [CanlidovizProtocol],
/// bağlantı yaşam döngüsü için [WsCanlidovizPriceStream].
///
/// **Not (lisans):** kullanım koşulları gözden geçirilmedi; erişim
/// **teknik olarak** açık olsa da hukuki değerlendirme kullanıcıya aittir.
/// Bu provider tek dosyada toplanmıştır ki gerektiğinde kaldırılabilir.
class CanlidovizProvider implements MarketDataProvider {
  CanlidovizProvider({
    http.Client? httpClient,
    CanlidovizPriceStream? priceStream,
  })  : _httpClient = httpClient ?? http.Client(),
        _priceStream = priceStream ??
            WsCanlidovizPriceStream(
              codes: CanlidovizProtocol.streamCodes,
              topics: CanlidovizProtocol.streamTopics,
            );

  final http.Client _httpClient;
  final CanlidovizPriceStream _priceStream;

  /// Akış taze iken quote TTL'i / ekrandaki güncelleme ritmi.
  /// Her tetikleme **bellek içinden** okunur; ağ isteği üretmez.
  static const Duration liveRefreshInterval = Duration(seconds: 2);

  /// Akış yokken (kapalı/bağlantı koptu/bayat) Gold API ritmi korunur -
  /// yedek kaynağa normal hızda gidilir, istek seli oluşturulmaz.
  static const Duration fallbackRefreshInterval = Duration(seconds: 60);

  /// Tik bu süreden bayatsa fiyat verilmez (fallback'e düşülür).
  static const Duration maxTickAge = Duration(minutes: 2);

  /// `--dart-define=CANLIDOVIZ_WS_DISABLED=true` ile fiyat akışı
  /// kapatılabilir (cihazda fallback doğrulaması için).
  static const bool wsDisabled =
      bool.fromEnvironment('CANLIDOVIZ_WS_DISABLED');

  /// `package:http` varsayılan User-Agent'i ile de `200` döndüğü
  /// ölçüldü (2026-10-06: `Dart/3.13 (dart:io)`, `KYRON (Flutter)`, Chrome
  /// UA ve UA'sız isteklerin hepsi aynı gövdeyi verdi). Bu yüzden
  /// taklitçi header gönderilmez.
  static const Map<String, String> _headers = {'Accept': 'application/json'};

  @override
  String get id => 'canlidoviz';

  @override
  String get displayName => 'CanlıDöviz';

  /// Fiyat akışını başlat (idempotent).
  ///
  /// Kaynak listesi oluşturulurken (`app_providers.dart`) çağrılır; böylece
  /// ilk `watchQuotes` akışı kısa ritimle başlar. Testler çağırmaz ve
  /// **hiçbir test gerçek ağa çıkmaz**. `wsDisabled` ise no-op'tur.
  void startStream() {
    if (wsDisabled) return;
    _priceStream.start();
  }

  /// Akış bağlı ve taze tik varsa **2 sn** (ekran tık tık güncellenir; her
  /// tetikleme bellek içinden okunur, ağ isteği üretilmez).
  ///
  /// Değilse Gold API ile aynı **60 sn**: açılışta/kesintide yedek kaynağa
  /// normal hızda gidilir, istek seli oluşmaz. Açılışta akış henüz
  /// bağlanırken de kısa ritim seçilir ki ilk stream periyodu 60 sn'ye
  /// kilitlenmesin; bağlantı başarısız olursa süre 60 sn'ye döner.
  @override
  Duration get refreshInterval {
    if (_priceStream.isConnecting) return liveRefreshInterval;
    final now = DateTime.now();
    for (final id in CanlidovizProtocol.streamAssetIds) {
      final cid = CanlidovizProtocol.assetToItemId(id);
      if (cid == null) continue;
      if (_freshTick(cid, now) != null) return liveRefreshInterval;
    }
    return fallbackRefreshInterval;
  }

  /// Fiyat akisi varligi mi? (cid eslemesi VAR + akisa bagli: kodu veya
  /// [CanlidovizProtocol.streamTopics] topic uyesi).
  ///
  /// 14/18 Ayar'da cid mum icin bulunur ama akis uyesi degiller -
  /// quote icin `false`, mum icin [supportsCandles] `true`.
  @override
  bool supports(String assetId) =>
      CanlidovizProtocol.assetToItemId(assetId) != null &&
      CanlidovizProtocol.streamAssetIds.contains(assetId);

  /// Mum (gecmis) destegi: history API'de cid olan **her** varlik.
  @override
  bool supportsCandles(String assetId) =>
      CanlidovizProtocol.assetToItemId(assetId) != null;

  /// Güncel fiyat (P1): WebSocket'ten gelen **gerçek tik**.
  ///
  /// Akış bağlı değilse / taze tik yoksa [EmptyFailure] döndürür; repository
  /// `_fetchDirectTryAll` sıradaki adayı (Gold API) dener - **fallback
  /// olduğu gibi çalışır**. HTTP isteği yapılmaz.
  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final now = DateTime.now();
    final out = <String, Quote>{};

    for (final id in assetIds.toSet()) {
      if (!supports(id)) continue;
      final cid = CanlidovizProtocol.assetToItemId(id);
      if (cid == null) continue;

      final tick = _freshTick(cid, now);
      if (tick == null) continue; // akış yok/taze değil -> fallback zinciri

      // Kapanis referansi: WS karelerinde % degisim YOKTUR; son tamamlanmis
      // gunluk kapanis arka planda cekilir. Hazirsa quote'a eklenir -
      // boylece degisim yuzdesi gercek kapanistan hesaplanir (uydurulmaz).
      unawaited(_ensurePreviousClose(cid));
      final previousClose = _previousCloseEntry(cid)?.value;

      final asset = AssetCatalog.byId(id);
      out[id] = Quote(
        assetId: id,
        source: QuoteSourceLabel.market,
        updatedAt: tick.receivedAt,
        price: tick.price,
        bid: tick.bid,
        ask: tick.ask,
        currency: asset?.currency ?? 'USD',
        freshness: _freshness(tick.receivedAt, now),
        previousClose: previousClose,
      );
    }

    if (out.isEmpty) {
      return const Err(EmptyFailure(
        'CanlıDöviz fiyat akışından taze fiyat gelmedi.',
      ));
    }
    return Success(out);
  }

  /// previousClose onbellek suresi (kapanis gunde bir kez degisir).
  static const Duration previousCloseTtl = Duration(minutes: 30);

  /// Kapanis arama penceresi (borsa/kotu gecmis gunleri kapsar).
  static const Duration previousCloseWindow = Duration(days: 40);

  /// cid -> (deger|null, alinma zamani). `value == null` son deneme
  /// **basarisizdir** (istek seli olmasin diye TTL boyunca tekrar denemez;
  /// quote previousClose'suz gider ve UI "—" gosterir - deger uydurulmaz).
  final Map<int, ({double? value, DateTime at})> _previousCloseCache = {};

  /// Su an bekleyen kapanis istekleri (cid -> future).
  final Map<int, Future<void>> _previousClosePending = {};

  ({double? value, DateTime at})? _previousCloseEntry(int cid) {
    final e = _previousCloseCache[cid];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > previousCloseTtl) return null;
    return e;
  }

  /// Kapanis referansini arka planda ceker (cid basina tek istek).
  ///
  /// Hata quote'u **engellemez**: basarisizliga karsilik bellekte
  /// `value=null` girisi birakilir ve [previousCloseTtl] boyunca tekrar
  /// denenmez. Ag cagrisi ucretsizdir (yalnizca ilk tikte bir kez).
  Future<void> _ensurePreviousClose(int cid) {
    if (_previousCloseEntry(cid) != null) return Future<void>.value();
    final pending = _previousClosePending[cid];
    if (pending != null) return pending;
    late final Future<void> future;
    future = _loadPreviousClose(cid).whenComplete(() {
      if (identical(_previousClosePending[cid], future)) {
        _previousClosePending.remove(cid);
      }
    });
    _previousClosePending[cid] = future;
    return future;
  }

  /// Son **tamamlanmis** gunluk bar'in kapanisini ceker.
  ///
  /// Bitis kesmesi = dun 23:59:59 UTC: bugunun yarim kalmis bar'i asla
  /// previousClose olarak kullanilmaz (aksinde % degisim gun icine
  /// sikisir ve yanlis gosterilir).
  Future<void> _loadPreviousClose(int cid) async {
    double? close;
    try {
      final nowUtc = DateTime.now().toUtc();
      final start = nowUtc.subtract(previousCloseWindow);
      final end = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day)
          .subtract(const Duration(seconds: 1));
      final uri = CanlidovizProtocol.historyUri(
        period: CanlidovizProtocol.periodDaily,
        itemDataId: cid,
        startUtc: start,
        endUtc: end,
      );
      final response = await _httpClient
          .get(uri, headers: _headers)
          .timeout(CanlidovizProtocol.requestTimeout);
      if (response.statusCode < 400) {
        final parsed = CanlidovizProtocol.parseHistory(response.body);
        final candles = parsed.dataOrNull;
        if (candles != null && candles.isNotEmpty) {
          // ParseHistory zaten dogal siralar; yine de emin olmak icin en
          // yeni bar (en buyuk time) secilir.
          var latest = candles.first;
          for (final c in candles) {
            if (c.time > latest.time) latest = c;
          }
          if (latest.close.isFinite) close = latest.close;
        }
      }
    } catch (_) {
      // Zaman asimi/ag/parse hatasi: giris `null` olarak yazilir (yukaridaki
      // TTL kurali gecerli kalir). SAHTE KAPANIS DEGERI URETILMEZ.
      close = null;
    }
    _previousCloseCache[cid] = (value: close, at: DateTime.now());
  }

  /// Test yardimcisi: bekleyen kapanis isteklerinin bitmesini saglar.
  Future<void> waitForPreviousClose({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_previousClosePending.isNotEmpty) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      try {
        await Future.wait(_previousClosePending.values.toList())
            .timeout(remaining);
      } on TimeoutException {
        return;
      }
    }
  }

  /// Bağlı akışın, geçerli yaş aralığındaki son tikini döndürür.
  CanlidovizTick? _freshTick(int cid, DateTime now) {
    if (!_priceStream.isConnected) return null;
    final tick = _priceStream.latest(cid);
    if (tick == null) return null;
    // Saat geriye alınırsa fark negatif olur; o durumda tik tazedir.
    if (now.difference(tick.receivedAt) > maxTickAge) return null;
    return tick;
  }

  /// Tik tazeliği (esikler Gold API ile aynı).
  ///
  /// Tik seviyesindeki akış `live` üretir; [maxTickAge] nedeniyle bu aşımda
  /// bayat tik zaten servis edilmez.
  DataFreshness _freshness(DateTime receivedAt, DateTime now) {
    final age = now.difference(receivedAt);
    if (age < const Duration(minutes: 2)) return DataFreshness.live;
    if (age < const Duration(minutes: 5)) return DataFreshness.delayed;
    return DataFreshness.daily;
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    if (!supportsCandles(assetId)) {
      return const Err(EmptyFailure('Bu kaynak mum verisi desteklemiyor.'));
    }
    if (limit < 1) {
      return const Err(BadRequestFailure('Mum limiti pozitif olmalı.'));
    }
    final itemId = CanlidovizProtocol.assetToItemId(assetId);
    if (itemId == null) {
      return const Err(BadRequestFailure('CanlıDöviz eşlemesi bulunamadı.'));
    }

    final end = DateTime.now().toUtc();
    final start = end.subtract(CanlidovizProtocol.windowFor(interval, limit));
    final uri = CanlidovizProtocol.historyUri(
      period: CanlidovizProtocol.periodFor(interval),
      itemDataId: itemId,
      startUtc: start,
      endUtc: end,
    );

    final http.Response response;
    try {
      response = await _httpClient
          .get(uri, headers: _headers)
          .timeout(CanlidovizProtocol.requestTimeout);
    } on TimeoutException {
      return const Err(TimeoutFailure());
    } on http.ClientException catch (e) {
      return Err(NetworkFailure('İnternet bağlantısı kurulamadı.', e));
    } catch (e) {
      return Err(UnknownFailure('Beklenmeyen bir hata oluştu.', e));
    }

    if (response.statusCode >= 400) {
      return Err(_statusToFailure(response.statusCode, response.body));
    }

    final parsed = CanlidovizProtocol.parseHistory(response.body);
    final raw = parsed.dataOrNull;
    if (raw == null) {
      return Err(parsed.failureOrNull ?? const ParseFailure());
    }

    // 1) Dilim kovalarına birleştir (mevcut CandleAggregator), 2) limit'e kısalt.
    // Eksik geçmiş UYDURULMAZ: retansiyon sınırlı olduğunda (örn. h4) bar
    // sayısı `limit`'in altında kalabilir ve bu durum olduğu gibi döner.
    final candles = CanlidovizProtocol.prepare(raw, interval, limit);
    if (candles.isEmpty) {
      return const Err(EmptyFailure('CanlıDöviz için mum verisi bulunamadı.'));
    }

    return Success(CandleSeries(
      assetId: assetId,
      interval: interval,
      candles: candles,
      updatedAt: DateTime.now(),
    ));
  }

  /// HTTP durum kodu -> [Failure] eşlemesi (`ApiClient` ile aynı kurallar).
  Failure _statusToFailure(int status, String body) {
    if (status >= 500) {
      return ServerFailure('Sunucudan yanıt alınamadı. ($status)');
    }
    if (status >= 400) {
      // Sunucunun kendi mesajı: {"data":null,"message":"invalid date range"}
      final message = CanlidovizProtocol.serverMessage(body);
      if (message != null) {
        return BadRequestFailure('CanlıDöviz isteği reddetti: $message');
      }
      return BadRequestFailure('İstek reddedildi. ($status)');
    }
    return UnknownFailure('Beklenmeyen HTTP durumu: $status');
  }

  void dispose() {
    _priceStream.stop();
    _previousCloseCache.clear();
    _previousClosePending.clear();
    _httpClient.close();
  }
}
