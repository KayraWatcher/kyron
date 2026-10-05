import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import '../../domain/entities/data_freshness.dart';

/// AnlıkAltınFiyatlari.com (https://anlikaltinfiyatlari.com/) kaynakli
/// [MarketDataProvider] uygulama.
///
/// Kapsam: Gram/Ceyrek/Yarim/Tam/Cumhuriyet/Ata/22Ayar/14Ayar/18Ayar/Reşat altin,
/// Ons altin, Gümüş (ons/gram), Döviz (USD/TRY).
///
/// Protokol: HTTP GET -> JSONP endpoint (jsonp2.php) returning
/// `[[timestamp_ms, price], ...]` arrays.
///
/// Ozellikler:
///   * Kimlik dogrulama YOK (public endpoint)
///   * ~60 saniyelik guncelleme araligi (site setInterval 60sn)
///   * Sadece `live` suffix'li endpointler canli veri saglar
///     (orn. `gramlive.json` vs `gram.json`)
///   * Gümüş fiyat degisimleri seyrek (2 degisim / 40 dk digerlerine 10/40 dk)
///   * Timestamp milliseconds -> DateTime donusumu
///   * Authentication YOK
class AnlikAltinFiyatlariProvider implements MarketDataProvider {
  AnlikAltinFiyatlariProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const String _baseUrl =
      'https://anlikaltinfiyatlari.com/anlik/charts/jsonp2.php';

  /// Refresh interval = 60 seconds (site uses setInterval(..., 60000))
  @override
  final Duration refreshInterval = const Duration(seconds: 60);

  @override
  String get id => 'anlikaltinfiyatlari';

  @override
  String get displayName => 'Anlık Altın Fiyatları';

  /// Mapping: GOLD asset ID -> AnlıkAltınFiyatlari filename (with 'live' suffix)
  static const Map<String, String> _assetToFilename = {
    AssetCatalog.gramAltinId: 'gramlive',
    AssetCatalog.ceyrekAltinId: 'ceyreklive',
    AssetCatalog.yarimAltinId: 'yarimlive',
    AssetCatalog.tamAltinId: 'tamlive', // Not tested; may need verification
    AssetCatalog.cumhuriyetAltinId: 'cumhuriyetlive',
    AssetCatalog.ataAltinId: 'atalive', // Not tested; may need verification
    AssetCatalog.bilezik22Id: '22ayarlive',
    AssetCatalog.ayar14AltinId: '14ayarlive',
    AssetCatalog.ayar18AltinId: '18ayarlive',
    AssetCatalog.resatAltinId: 'resatlive',
    AssetCatalog.onsAltinId: 'onaltinlive', // Not tested; may need verification
    AssetCatalog.gramGumusId: 'gumuslive', // Maps to gumuslive (Gram Gümüş)
    AssetCatalog.onsGumusId: 'gumusonslive', // Ons Gümüş
    AssetCatalog.usdTryId: 'usdtrylive', // Not tested
    AssetCatalog.eurTryId: 'eurtrylive', // Not tested
    AssetCatalog.gbpTryId: 'gbptrylive', // Not tested
    AssetCatalog.chfTryId: 'chftrylive', // Not tested
    AssetCatalog.jpyTryId: 'jpytrylive', // Not tested
    // Legacy/alternative IDs (for backward compatibility)
    '22-ayar-altin': '22ayarlive',
  };

  /// Assets supported for direct price fetching (not calculated)
  /// Only assets with working live endpoints are included.
  static const Set<String> _supportedDirect = {
    AssetCatalog.gramAltinId,
    AssetCatalog.ceyrekAltinId,
    AssetCatalog.yarimAltinId,
    AssetCatalog.cumhuriyetAltinId,
    AssetCatalog.bilezik22Id,
    AssetCatalog.ayar14AltinId,
    AssetCatalog.ayar18AltinId,
    AssetCatalog.resatAltinId,
    AssetCatalog.gramGumusId, // Gram Gümüş
    AssetCatalog.onsGumusId, // Ons Gümüş
  };

  @override
  bool supports(String assetId) {
    // Sadece canli endpointi olan varliklari destekle
    final filename = _assetToFilename[assetId];
    if (filename == null) return false;
    return _supportedDirect.contains(assetId);
  }

  @override
  bool supportsCandles(String assetId) {
    // Mum verisi icin gerekli endpointler test edilmemis; oncelikle fiyat odakli
    return false;
  }

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final supportedIds = assetIds.where(supports).toList();
    if (supportedIds.isEmpty) {
      return const Err(EmptyFailure(
          'AnlıkAltınFiyatlari için uygun sembol yok.'));
    }

    // Gruplandir: ayni endpoint'e dusenleri tek istekte topla
    // Her asset icin ayri endpoint oldugu icin paralel getir
    final futures = <Future<({String assetId, Quote quote})?>>[];

    for (final assetId in supportedIds) {
      futures.add(_fetchSingle(assetId));
    }

    final results = await Future.wait(futures);
    final out = <String, Quote>{};

    for (final res in results) {
      if (res != null) {
        out[res.assetId] = res.quote;
      }
    }

    if (out.isEmpty) {
      return const Err(EmptyFailure('AnlıkAltınFiyatlari fiyat verisi boş döndü.'));
    }
    return Success(out);
  }

  Future<({String assetId, Quote quote})?> _fetchSingle(String assetId) async {
    final filename = _assetToFilename[assetId];
    if (filename == null) return null;

    final url = '$_baseUrl?filename=$filename.json&islive=1&time=30';

    try {
      final resp = await _httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        return null;
      }

      final body = resp.body.trim();
      if (body.isEmpty) return null;

      // Response is JSON array: [[timestamp_ms, price], ...]
      final List<dynamic> data = jsonDecode(body);
      if (data.isEmpty) return null;

      // En son veri noktasini al (en guncel)
      final last = data.last;
      if (last is! List || last.length < 2) return null;

      final timestampMs = last[0] as num;
      final price = last[1] as num;

      // Validate
      if (!timestampMs.isFinite || !price.isFinite) return null;
      if (price <= 0) return null;

      final updatedAt = DateTime.fromMillisecondsSinceEpoch(timestampMs.toInt());

      // Asset bilgisini al
      final asset = AssetCatalog.byId(assetId);
      final currency = asset?.currency ?? 'TRY';

      // Sadece price doldur; bid/ask yok (site alis/satis vermez)
      final quote = Quote(
        assetId: assetId,
        source: QuoteSourceLabel.market,
        updatedAt: updatedAt,
        price: price.toDouble(),
        currency: currency,
        freshness: _freshnessFromTimestamp(updatedAt),
      );

      return (assetId: assetId, quote: quote);
    } on FormatException {
      // Malformed JSON
      return null;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Timestamp'ten tazelik hesapla.
  ///
  /// Site ~60 saniyede bir guncelliyor. Eger timestamp 120sn'den eskiyse
  /// stale sayilir. Market acik/kapali bilgisi yok -> unknown/delayed.
  DataFreshness _freshnessFromTimestamp(DateTime updatedAt) {
    final now = DateTime.now();
    final age = now.difference(updatedAt);

    if (age < const Duration(seconds: 120)) {
      return DataFreshness.live; // Site 60sn gunceller, 120sn guvenli
    }
    if (age < const Duration(minutes: 5)) {
      return DataFreshness.delayed;
    }
    return DataFreshness.daily; // Eski veri
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    // AnlıkAltınFiyatlari.com only provides current price snapshots,
    // not OHLC candlestick data.
    return const Err(EmptyFailure(
        'AnlıkAltınFiyatlari mum (OHLC) verisi sağlamaz.'));
  }

  /// Clean up http client if we created it
  void dispose() {
    _httpClient.close();
  }
}