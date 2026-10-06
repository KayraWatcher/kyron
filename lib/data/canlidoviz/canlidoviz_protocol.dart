import 'dart:convert';

import '../../core/error/failures.dart';
import '../../domain/candle/candle_aggregator.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';

/// CanlıDöviz geçmiş (mum) ucunun **protokol katmani**.
///
/// Burada ne HTTP istegi ne WebSocket vardir; yalnizca kanitlanmis bicimde
/// istek kurgusu ve yanit cozumleme bulunur. Kaynak: gercek ag analizi
/// (`C:\temp\canlidoviz-test` - `depth2.js`, `range_probe.js`,
/// `period_test.js`) ve site JS'i (`c.bundle.js` -> `parsePipe`).
///
/// ## Kanitlanmis endpoint
///
/// ```
/// GET https://a.canlidoviz.com/items/history
///   ?period=OHLC|DAILY
///   &itemDataId=<cid>
///   &startDate=yyyy-MM-ddTHH:mm:ss
///   &endDate=yyyy-MM-ddTHH:mm:ss
/// ```
///
/// Yanit: `{ "unixTimestamp": "open|high|low|close" }` (Unix **saniye**, UTC).
/// Alan sirasi JS kaynaginda dogrulandi: `open=0, high=1, low=2, close=3`.
///
/// ## Dogrulanmis kisitlar (2026-10-06 olcumu)
///
///  * `period=OHLC` -> ~1 dakikalik mum, retansiyon **~8 gun**
///    (en eski veri istek penceresinden bagimsiz olarak baslangica kisitlanir;
///    29+ gunluk istek `400 invalid date range`).
///  * `period=DAILY` -> gunluk mum, **2018-08-26**'dan itibaren.
///  * Gecerli `period` yalnizca `OHLC` ve `DAILY`;
///    `HOURLY`/`MINUTE`/`WEEKLY`/`MONTHLY` -> `400 invalid period`.
///  * Kimlik dogrulama, cookie veya token **yok**.
///
/// ## Sahte veri yasagi
///
///  * Dondurulen mum yalnizca yanittaki sayilardan uretilir; hicbir OHLC
///    alani tahmin edilmez.
///  * 4 alanin tamami sayisal ve sonlu degilse mum **atlanir**.
///  * `high < low` olan mum reddedilir.
///  * Gecersiz timestamp'li mum reddedilir.
abstract final class CanlidovizProtocol {
  /// Endpoint taban adresi.
  static const String baseUrl = 'https://a.canlidoviz.com';

  /// Gecmis mum ucu.
  static const String historyPath = '/items/history';

  /// Ons Altin (`XAU/USD`) icin `itemDataId` (cid).
  ///
  /// Dogrulama: Gold API `XAU = 4135.20` ile cid=12 son kapanis `4133.72`
  /// arasindaki fark **%0.03** (2026-10-06) - varlik `XAU/USD` spot'tur.
  static const int onsAltinItemId = 12;

  /// Gecerli `period` degerleri.
  static const String periodOhlc = 'OHLC';
  static const String periodDaily = 'DAILY';

  /// `period=OHLC` istek penceresi tavanı.
  ///
  /// Olcum: 25 gun -> `200` (sunucu ~8 gunluk retansiyona kisir),
  /// 29 gun -> `400 invalid date range`. Retansiyon ~8 gun oldugundan bu
  /// tavandan uzun istek **ayni veriyi** dondurur; tavan yalnizca 400
  /// riskine karsi konur.
  static const Duration ohlcMaxWindow = Duration(days: 25);

  /// `period=DAILY` istek penceresi tavanı.
  ///
  /// Kanit: 2004 baslangicli istek bile `200` donuyor (veri 2018-08-26'dan
  /// itibaren); tavan gereksiz buyuk yanitlari sinirlandirir.
  static const Duration dailyMaxWindow = Duration(days: 3650);

  /// Tek bir gecmis istegi icin zaman asimi.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// 2100-01-01 (Unix saniye) - sonrasi gecersiz kabul edilir.
  static const int _maxUnixSeconds = 4102444800;

  // ---------------------------------------------------------------------------
  // VARLIK -> CID
  // ---------------------------------------------------------------------------

  /// Varlik -> `itemDataId` (cid) eslemesi. **29 varlik, hepsi gercek API
  /// uzerinden dogrulandi** (2026-10-06):
  ///
  ///  * **Sayfa/DOM kaniti** (`cid_map.json` + liste sayfalari DOM'u,
  ///    HTTP 200): her urun linkinin `[cid]` atributu sitenin kendi
  ///    atamasi (orn. `/altin-fiyatlari/yarim-altin` -> 47,
  ///    `/emtia-fiyatlari/gumus-ons` -> 267, `/endeks/bist-50` -> 249).
  ///  * **WS tik deger kimligi**: abonelik sonrasi gelen `cid|bid|ask|last`
  ///    kayitlarinda deger o varligin bilinen fiyatina esitti (orn. cid=32
  ///    -> 6538.46 gram altin; cid=1 -> 49.12 USD/TRY; cid=266 -> 100.48
  ///    Brent; cid=47 -> 21077 yarim altin; cid=57 -> 31.01 "100 JAPON
  ///    YENI"). Kapali piyasalarda (BIST, SPX) tik gelmez; 250/248/249/1015
  ///    **history API** son kapanis + sitenin kendi kod listesiyle
  ///    dogrulandi (12443.92 / 15457.49 / 11628.07 / 7773.95).
  ///  * **history API kaniti**: 29 cid'in tamami `items/history` DAILY
  ///    isteklerinde 200 + mantikli donus verdi; altin ailesi kapanislari
  ///    gram altin kapanisiyla agirlik iliskisinde (orn. yarim 21554 ~
  ///    gram 6543 x 3,305; tam 42912 ~ gram x 6,61).
  ///  * **Gercek deger karsilastirmasi**: WTI cid=1215 -> 89,76 ile Yahoo
  ///    `CL=F` 89,77 ayni (COIL=WTI dogrulandi); SPX 7773.95 = Yahoo
  ///    `^GSPC` 7773.95; XU050 11628.07 = Yahoo `XU050.IS` 11628.07;
  ///    DXY 102,18 = Yahoo `DX-Y.NYB` 102,189; XAG/USD 60,6 ~ Yahoo
  ///    `SI=F` 60,86; XPT/USD 1713 ~ Yahoo `PL=F` 1718.
  ///
  /// Esmeyen varlik `null` dondurur - **uydurma cid kullanilmaz**.
  /// `14/18 Ayar` yalnizca **mum** (candles) icin buradadir: bunlarin
  /// CanliDoviz akisinda tik uyesi olmadigi dogrulandi (GOLD topic uyesi
  /// degiller, `14` kodu tik getirmedi) - boylece quote icin [supports]
  /// false kalir, mum icin [supportsCandles] true olur.
  static const Map<String, int> itemIdsByAsset = <String, int>{
    // Mevcut 11 (P0+P1):
    AssetCatalog.onsAltinId: onsAltinItemId, // 12  - XAU/USD
    AssetCatalog.gramAltinId: 32,
    AssetCatalog.gramGumusId: 20,
    AssetCatalog.ceyrekAltinId: 11,
    AssetCatalog.usdTryId: 1,
    AssetCatalog.eurTryId: 50,
    AssetCatalog.gbpTryId: 100,
    AssetCatalog.chfTryId: 51,
    AssetCatalog.bist100Id: 250,
    AssetCatalog.bist30Id: 248,
    AssetCatalog.brentCrudeId: 266,
    // Altin ailesi (GOLD topic tikleri + DOM + DAILY tutarliligi):
    AssetCatalog.yarimAltinId: 47,
    AssetCatalog.tamAltinId: 14,
    AssetCatalog.cumhuriyetAltinId: 27, // DOM: /altin-fiyatlari/cumhuriyet-altini
    AssetCatalog.ataAltinId: 58,
    AssetCatalog.bilezik22Id: 18, // DOM: /altin-fiyatlari/22-ayar-bilezik
    AssetCatalog.resatAltinId: 43, // DOM: /altin-fiyatlari/resat-lira-altin
    // Mum kaynagi (quote akisi yok - bkz. doc):
    AssetCatalog.ayar14AltinId: 16,
    AssetCatalog.ayar18AltinId: 55,
    // Gumus / WTI / yeni doviz-endeks-emtia:
    AssetCatalog.onsGumusId: 267, // DOM: /emtia-fiyatlari/gumus-ons (XAG/USD)
    AssetCatalog.jpyTryId: 57, // DOM: /doviz-kurlari/100-japon-yeni (100 JPY)
    AssetCatalog.wtiCrudeId: 1215, // DOM: /emtia-fiyatlari/ham-petrol (COIL)
    AssetCatalog.cadTryId: 56,
    AssetCatalog.audTryId: 102,
    AssetCatalog.cnyTryId: 107,
    AssetCatalog.dxyId: 846,
    AssetCatalog.sp500Id: 1015,
    AssetCatalog.bist50Id: 249,
    AssetCatalog.platinId: 268, // DOM: /emtia-fiyatlari/platin-spot-dolar
    // 1.2.0 genislemesi - emtia + kripto (canli API dogrulamasi 2026-10-06):
    AssetCatalog.paladyumId: 269, // DOM: /emtia-fiyatlari/paladyum-spot-dolar
    AssetCatalog.bakirId: 1056, // DOM: /emtia-fiyatlari/bakir
    AssetCatalog.dogalgazId: 1064, // DOM: /emtia-fiyatlari/dogalgaz
    AssetCatalog.platinGramId: 1012, // DOM: /emtia-fiyatlari/platin-gram
    AssetCatalog.bitcoinId: 62, // DOM: /kripto-paralar/bitcoin
    AssetCatalog.ethereumId: 52, // DOM: /kripto-paralar/ethereum
  };

  /// Varlik -> `itemDataId` (cid). Esleme yoksa `null` (uydurulmaz).
  static int? assetToItemId(String assetId) => itemIdsByAsset[assetId];

  // ---------------------------------------------------------------------------
  // INTERVAL -> PERIOD / PENCERE
  // ---------------------------------------------------------------------------

  /// Grafik dilimi -> endpoint `period` degeri.
  ///
  ///  * `m1..h4` -> `OHLC` (~1 dk kaynak mum, kova olarak birlestirilir)
  ///  * `d1`     -> `DAILY` (dogrudan gunluk mum)
  ///  * `w1/mo1` -> `DAILY` (gunluk mumlar kovaya birlestirilir)
  static String periodFor(ChartInterval interval) => switch (interval) {
        ChartInterval.m1 ||
        ChartInterval.m5 ||
        ChartInterval.m15 ||
        ChartInterval.m30 ||
        ChartInterval.h1 ||
        ChartInterval.h4 =>
          periodOhlc,
        ChartInterval.d1 || ChartInterval.w1 || ChartInterval.mo1 =>
          periodDaily,
      };

  /// Dilim ve `limit` icin istek penceresi (kaynak bar sayisini karsilayacak
  /// kadar geriye gider, emniyet tavanina kisitlanir).
  ///
  /// `h1`/`h4` gibi uzun dilimlerde retansiyon (~8 gun) istenen pencereyi
  /// karsilamaz; sunucu mevcut veriyi oldugu kadar dondurur. Eksik bosa
  /// **uydurulmaz** - donen bar sayisi istenen `limit`'in altinda kalabilir.
  static Duration windowFor(ChartInterval interval, int limit) {
    final needed = interval.duration * limit;
    final cap =
        periodFor(interval) == periodOhlc ? ohlcMaxWindow : dailyMaxWindow;
    return needed > cap ? cap : needed;
  }

  // ---------------------------------------------------------------------------
  // ISTEGI KURMA
  // ---------------------------------------------------------------------------

  /// Endpoint, **kanitlanmis** bicimde (query string'i elden kurulur ki
  /// `:` karakteri `%3A` olarak kodlanmasin - ag analizinde bu bicimle
  /// `200` alinmistir).
  static Uri historyUri({
    required String period,
    required int itemDataId,
    required DateTime startUtc,
    required DateTime endUtc,
  }) {
    final start = formatTimestamp(startUtc);
    final end = formatTimestamp(endUtc);
    return Uri.parse(
      '$baseUrl$historyPath?period=$period&itemDataId=$itemDataId'
      '&startDate=$start&endDate=$end',
    );
  }

  /// `yyyy-MM-ddTHH:mm:ss` (UTC) - endpoint'in zorunlu tarih bicimi.
  static String formatTimestamp(DateTime time) {
    final u = time.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final year = u.year.toString().padLeft(4, '0');
    return '$year-${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
  }

  // ---------------------------------------------------------------------------
  // YANIT COZUMLEME
  // ---------------------------------------------------------------------------

  /// Tek bir `{unixTimestamp: "o|h|l|c"}` kaydini [Candle]'a cevirir.
  ///
  /// Gecersiz herhangi bir durumda `null` dondurulur; aciklama
  /// **uretilmez**, veri **uydurulmaz**.
  static Candle? parseCandle(String timestampKey, Object? rawValue) {
    // 1) Timestamp: Unix saniye -> milisaniye (UTC).
    final seconds = int.tryParse(timestampKey.trim());
    if (seconds == null || seconds <= 0 || seconds > _maxUnixSeconds) {
      return null;
    }

    // 2) `open|high|low|close` - 4 alanin tamami zorunlu.
    if (rawValue is! String) return null;
    final parts = rawValue.split('|');
    if (parts.length < 4) return null;

    final values = <double>[];
    for (var i = 0; i < 4; i++) {
      final v = double.tryParse(parts[i].trim());
      // Sayisal degilse / NaN / sonsuz olabilir.
      if (v == null || !v.isFinite) return null;
      // 0 veya negatif fiyat gecerli degildir (sahte bar uretilmez).
      if (v <= 0) return null;
      values.add(v);
    }

    final open = values[0];
    final high = values[1];
    final low = values[2];
    final close = values[3];

    // 3) Mantiksal tutarlilik.
    if (high < low) return null;

    return Candle(
      time: seconds * 1000,
      open: open,
      high: high,
      low: low,
      close: close,
      // Kaynakta hacim alani yok; `null` kalir (uydurulmaz).
      volume: null,
    );
  }

  /// Govdesi `[Candle]` listesine donusturulur.
  ///
  /// Beklenmeyen bicim -> [ParseFailure], sunucu hata govdesi ->
  /// [BadRequestFailure], hic gecerli mum yok -> [EmptyFailure].
  static Result<List<Candle>> parseHistory(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      return Err(ParseFailure('CanlıDöviz yanıtı çözümlenemedi.', e));
    }

    if (decoded is! Map) {
      return const Err(ParseFailure('CanlıDöviz yanıt biçimi beklenen gibi değil.'));
    }

    // Hata govdesi: {"data":null,"message":"invalid date range"}
    final message = decoded['message'];
    if (message is String && message.isNotEmpty) {
      return Err(BadRequestFailure('CanlıDöviz isteği reddetti: $message'));
    }

    final candles = <Candle>[];
    for (final entry in decoded.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final candle = parseCandle(key, entry.value);
      if (candle != null) candles.add(candle);
    }

    if (candles.isEmpty) {
      return const Err(EmptyFailure('CanlıDöviz için mum verisi bulunamadı.'));
    }

    candles.sort((a, b) => a.time.compareTo(b.time));
    return Success(candles);
  }

  /// Sunucunun kendi hata mesaji: `{"data":null,"message":"..."}`.
  ///
  /// HTTP 4xx govdesinden mesaji ayiklamak icin kullanilir; mesaj yoksa
  /// `null` doner.
  static String? serverMessage(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Gecersiz govde: sunucu mesaji yoktur.
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // DONUSUM
  // ---------------------------------------------------------------------------

  /// Kaynak barlari dilim kovalarina birlestirir.
  ///
  ///  * `m1` ve `d1` kaynakla **ayni** frekanstadir (1 dk mum / gunluk mum);
  ///    dokunulmaz.
  ///  * Diger dilimler mevcut [aggregateCandles] ile birlestirilir;
  ///    kova disinda mum **eklenmez**, eksik bar **uydurulmaz**.
  static List<Candle> aggregateFor(
    List<Candle> src,
    ChartInterval interval,
  ) =>
      switch (interval) {
        ChartInterval.m1 || ChartInterval.d1 => src,
        _ => aggregateCandles(src, bucket: interval.duration),
      };

  /// En fazla [limit] mum dondurur (en yenisi kalir).
  static List<Candle> takeLast(List<Candle> src, int limit) =>
      src.length <= limit ? src : src.sublist(src.length - limit);

  /// Kaynak mumlari dilime gore hazirlar: birlestir -> `limit`'e kisitla.
  static List<Candle> prepare(
    List<Candle> src,
    ChartInterval interval,
    int limit,
  ) =>
      takeLast(aggregateFor(src, interval), limit);

  // ---------------------------------------------------------------------------
  // ANLIK FIYAT AKISI (WebSocket: Engine.IO v4 + Socket.IO)
  // ---------------------------------------------------------------------------
  //
  // Kaynak: sitesinin kendi istemcisinin ag kaydi (`wsframes.json`,
  // `websocket.log` - Playwright) ve dart:io ile yapilan dogrudan probe
  // (`ws_dart_test.dart`, 2026-10-06: abonelik sonrasi 15 sn'de 5 tick).
  //
  //  1. `wss://s.canlidoviz.com/socket.io/?EIO=4&transport=websocket`
  //  2. Sunucu -> `0{"sid":...,"pingInterval":25000,"pingTimeout":10000,...}`
  //  3. istemci -> `40`                     (Socket.IO default namespace)
  //  4. Sunucu -> `40{"sid":...}`
  //  5. istemci -> `42["us",{"t":[],"c":[kodlar],"m":false}]`  (abonelik)
  //  6. Sunucu -> `42["c",["12|4147.21|4147.83||", ...]]`      (fiyat)
  //  7. Sunucu -> `2` (ping); istemci `3` (pong) ile cevaplar (25 sn'de bir)
  //
  // ## Fiyat kaydi bicimi
  //
  // `cid|bid|ask|last|change` - bosalan alanlar bos kalir; tek tarafli
  // kayitlar (`12|4150.13|||`) da gozlenmistir. **Fiyat = bid**, cunku
  // sitenin kendi gosterdigi ana fiyat bid'dir (olcum: sayfada
  // `domPrice` = bid); bid yoksa `ask` kullanilir. Iki taraf da yoksa
  // kayit **atlanir** - uydurma fiyat uretilmez.
  ///
  /// ## Sahte veri yasagi
  ///
  ///  * Yalnizca mesajdaki sayilar kullanilir; fiyat/alistirma uydurulmaz.
  ///  * Gecersiz cid, gecersiz/negatif sayi, hic gecerli fiyat olmayan
  ///    kayit atlanir.
  ///  * Mesaj kaynak zaman damgasi tasimaz; `receivedAt` olarak **alim ani**
  ///    kaydedilir (uygulama saati degil, aga dusen an).

  /// Anlik fiyat akisi uc adresi (kanitli: 2026-10-06 probe).
  static const String wsUrl =
      'wss://s.canlidoviz.com/socket.io/?EIO=4&transport=websocket';

  /// Engine.IO "open" cercevesi bu prefiksle baslar (`0{...}`).
  static const String engineOpenPrefix = '0';

  /// Engine.IO ping (sunucu -> istemci): tek karakter `2`.
  static const String enginePing = '2';

  /// Engine.IO pong (istemci -> sunucu): tek karakter `3`.
  static const String enginePong = '3';

  /// Socket.IO default namespace baglantisi: `40`.
  static const String namespaceConnect = '40';

  /// Socket.IO olay cercevesi prefiksi: `42[...]`.
  static const String socketEventPrefix = '42';

  /// Abonelik olay adi (`42["us", ...]`).
  static const String subscribeEvent = 'us';

  /// Fiyat yayin olay adi (`42["c", [...]]`).
  static const String priceEvent = 'c';

  /// Varlik -> abonelik kodu eslemesi (**mevcut CanlıDöviz mapping'i**).
  ///
  /// Kanit zinciri (2026-10-06):
  ///  * Kodlar sitenin kendi istemcisinin abonelik listesinden cikti
  ///    (`s.bundle.js` `pathMap` + `wsframes.json` gonderilen cerceveler).
  ///  * Canli probe: kodlar tek cercevede abone edildi; gelen tiklerin
  ///    **deger kimligi** eslemeyi dogruladi (USD->1 49.12, EUR->50 55.22,
  ///    GBP->100 64.77, CHF->51 59.12, GA->32 6538.46, GAG->20 96.11,
  ///    C->11 10582.58, XAU/USD->12 4147.21, XBRUSD->266 100.48).
  ///  * Genisletme probe'u (2026-10-06): `T`->14 (42078 tam altin),
  ///    `Y`->47 (21104 yarim), `JPY`->57 (31.01), `CAD`->56 (34.34),
  ///    `AUD`->102 (34.25), `CNY`->107 (7.33), `XAG/USD`->267 (60.65),
  ///    `COIL`->1215 (89.76), `XPT/USD`->268 (1713), `DXY`->846
  ///    (102.18) - hepsi ayni baglantida tik degeri kimligiyle.
  ///  * Kapali piyasalarda tik gelmez; `XU100`/`XU030` (P1), `XU050` ve
  ///    `SPX` kodlari sitenin kendi `pathMap` + liste tablosu kanitidir
  ///    ve cid'leri history API kapanisiyla dogrulandi. Piyasa acilinca
  ///    tik dogrulamasi cihaz testinde tamamlanacak.
  ///
  /// Eslesmeyen varlik `null` dondurur ve akisa abone edilmez; yeni varlik
  /// eklemek icin once cid'i, sonra kodu **gercek uzerinde** dogrulamak
  /// gerekir. Kodu olmayan (fakat GOLD topic uyesi olan) varliklar
  /// [streamTopicOnlyAssetIds] ile tanimlidir.
  static const Map<String, String> streamCodesByAsset = <String, String>{
    AssetCatalog.onsAltinId: 'XAU/USD',
    AssetCatalog.gramAltinId: 'GA',
    AssetCatalog.gramGumusId: 'GAG',
    AssetCatalog.ceyrekAltinId: 'C',
    AssetCatalog.usdTryId: 'USD',
    AssetCatalog.eurTryId: 'EUR',
    AssetCatalog.gbpTryId: 'GBP',
    AssetCatalog.chfTryId: 'CHF',
    AssetCatalog.bist100Id: 'XU100',
    AssetCatalog.bist30Id: 'XU030',
    AssetCatalog.brentCrudeId: 'XBRUSD',
    // Genisletme (tik deger kimligi ile dogrulandi):
    AssetCatalog.yarimAltinId: 'Y',
    AssetCatalog.tamAltinId: 'T',
    AssetCatalog.jpyTryId: 'JPY',
    AssetCatalog.cadTryId: 'CAD',
    AssetCatalog.audTryId: 'AUD',
    AssetCatalog.cnyTryId: 'CNY',
    AssetCatalog.onsGumusId: 'XAG/USD',
    AssetCatalog.wtiCrudeId: 'COIL',
    AssetCatalog.platinId: 'XPT/USD',
    AssetCatalog.dxyId: 'DXY',
    // Kapali piyasa - sitenin kendi kod listesi kaniti:
    AssetCatalog.sp500Id: 'SPX',
    AssetCatalog.bist50Id: 'XU050',
    // 1.2.0 genislemesi:
    AssetCatalog.bitcoinId: 'BTC', // tik: cid=62 -> 85.478 (BTC/USD)
    AssetCatalog.ethereumId: 'ETH', // tik: cid=52 -> 2.698 (ETH/USD)
    AssetCatalog.paladyumId: 'XPD/USD', // tik: cid=269 -> 1166,79/1171,11
    AssetCatalog.platinGramId: 'GRPLTN', // tik: cid=1012 -> 2708 (TRY/gram)
    // Bu ucu borsa saatinde canli (probda kapaliydi, tik gelmedi):
    AssetCatalog.bakirId: 'COPPER', // site kodu + DAILY kapanis 6,64
    AssetCatalog.dogalgazId: 'NGAS', // site kodu + DAILY kapanis 3,074
  };

  /// `us` abonelik `t` (topic) alani - **site istemcisiyle birebir ayni
  /// mekanizma** (kanit: sayfa probe'u `42["us",{"t":["GOLD"],...}]`).
  ///
  /// GOLD topic'i altin uyesi **tum** urunleri canli tik olarak dagitir;
  /// kendi kodu olmayan varliklar (cumhuriyet/ata/bilezik/resat) boylece
  /// akisa dahil olur. Probe: tek `t:["GOLD"]` aboneligi 53 cid getirdi
  /// (47, 14, 27, 58, 18, 43 dahil - hepsi x4-x8 tik sayaci ile).
  static const List<String> streamTopics = <String>['GOLD'];

  /// Kendi abonelik kodu OLMAYAN, yalnizca [streamTopics] uyesi olarak
  /// fiyat alan varliklar (quote icin akis uyesi sayilirlar).
  static const List<String> streamTopicOnlyAssetIds = <String>[
    AssetCatalog.cumhuriyetAltinId, // 27 - GOLD probe: 43046/43784
    AssetCatalog.ataAltinId, // 58 - GOLD probe: 43046/43784
    AssetCatalog.bilezik22Id, // 18 - GOLD probe: 5926/6124
    AssetCatalog.resatAltinId, // 43 - GOLD probe: 43307/43979
  ];

  /// Akisa abone olunan varliklar (kod anahtarlari + topic uyeleri).
  static List<String> get streamAssetIds => <String>[
        ...streamCodesByAsset.keys,
        ...streamTopicOnlyAssetIds,
      ];

  /// Abonelik kodlari (mapping degerleri).
  static List<String> get streamCodes =>
      streamCodesByAsset.values.toList(growable: false);

  /// Varlik -> abonelik kodu. Esleme yoksa `null`.
  static String? assetToStreamCode(String assetId) =>
      streamCodesByAsset[assetId];

  /// Abonelik cercevesi: `42["us",{"t":[topiclar],"c":[kodlar],"m":false}]`.
  ///
  /// Alan sirasi ve `t`/`m` anahtarlari sitenin istemcisiyle birebir aynı
  /// (kanit: `wsframes.json` sent frame'leri + sayfa probe'u). Birlesik
  /// `t`+`c` cercevesi yasam testinde dogrulandi: GOLD uyeleri ve `DXY`
  /// kod tikleri ayni baglantida geldi.
  static String subscriptionFrame(List<String> codes,
          {List<String> topics = const <String>[]}) =>
      '$socketEventPrefix'
      '${jsonEncode([
        subscribeEvent,
        {
          't': topics,
          'c': codes,
          'm': false,
        },
      ])}';

  /// Sunucu el sikismasi mu? (`0{...}`)
  static bool isHandshake(String frame) => frame.startsWith('$engineOpenPrefix{');

  /// El sikismasindaki `pingInterval` (ms). Cerceve gecerli degilse `null`.
  static Duration? handshakePingInterval(String frame) {
    if (!isHandshake(frame)) return null;
    try {
      final decoded = jsonDecode(frame.substring(1));
      if (decoded is Map && decoded['pingInterval'] is num) {
        final ms = (decoded['pingInterval'] as num).toInt();
        if (ms > 0) return Duration(milliseconds: ms);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Namespace baglanti onayi mu? (`40{...}`)
  static bool isNamespaceAck(String frame) =>
      frame.startsWith('$namespaceConnect{');

  /// Engine.IO ping mu? (tek karakter `2`)
  static bool isPing(String frame) => frame == enginePing;

  /// Fiyat yayin cercevesi mi? (`42["c",...]`)
  static bool isPriceFrame(String frame) =>
      frame.startsWith('$socketEventPrefix["$priceEvent"');

  /// Tek bir `cid|bid|ask|last|change` kaydini cozumler.
  ///
  /// Gecersiz herhangi bir durumda `null`; aciklama **uretilmez**.
  static CanlidovizTick? parseTick(String entry, {required DateTime receivedAt}) {
    final parts = entry.split('|');
    // En az `cid|bid|ask` - sonraki alanlar (last/change) opsiyoneldir.
    if (parts.length < 3) return null;

    final cid = int.tryParse(parts[0].trim());
    if (cid == null || cid <= 0) return null;

    final bid = _positivePrice(parts[1]);
    final ask = _positivePrice(parts[2]);
    // Iki taraf da yoksa bu kayittan fiyat uretilemez -> atlanir.
    if (bid == null && ask == null) return null;

    return CanlidovizTick(cid: cid, bid: bid, ask: ask, receivedAt: receivedAt);
  }

  /// `42["c",[...]]` cercevesini tick listesine cevirir.
  ///
  /// Fiyat cercevesi degilse / bozuksa **bos liste** doner (hata firlatmaz).
  static List<CanlidovizTick> parsePriceFrame(
    String frame, {
    required DateTime receivedAt,
  }) {
    if (!isPriceFrame(frame)) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(frame.substring(socketEventPrefix.length));
    } catch (_) {
      return const [];
    }
    if (decoded is! List || decoded.length < 2) return const [];
    if (decoded[0] != priceEvent) return const [];
    final entries = decoded[1];
    if (entries is! List) return const [];

    final out = <CanlidovizTick>[];
    for (final entry in entries) {
      if (entry is! String) continue;
      final tick = parseTick(entry, receivedAt: receivedAt);
      if (tick != null) out.add(tick);
    }
    return out;
  }

  /// Pozitif ve sonlu fiyat; degilse `null` (NaN/sonsuz/0/negatif elenir).
  static double? _positivePrice(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || !v.isFinite || v <= 0) return null;
    return v;
  }
}

/// Anlik fiyat kaydi (`cid|bid|ask|...`).
///
/// [receivedAt] mesajin aga dusen ani (kaynak mesaj zaman damgasi tasimaz).
class CanlidovizTick {
  const CanlidovizTick({
    required this.cid,
    required this.bid,
    required this.ask,
    required this.receivedAt,
  });

  /// CanlıDöviz `itemDataId` (cid).
  final int cid;

  /// Alış (bid) - yoksa `null`.
  final double? bid;

  /// Satış (ask) - yoksa `null`.
  final double? ask;

  /// Mesajin alindigi an.
  final DateTime receivedAt;

  /// Kaynagin gosterdigi ana fiyat: once `bid`, yoksa `ask`.
  /// Ikisi de yoksa `null` (bu durumda kayit zaten parse edilmez).
  double? get price => bid ?? ask;
}
