import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import '../../domain/entities/data_freshness.dart';

/// gold-api.com (https://gold-api.com/) kaynakli [MarketDataProvider] uygulamasi.
///
/// Kapsam: Ons Altın (XAU/USD), Ons Gümüş (XAG/USD) - SPOT fiyatlar.
///
/// Protokol: HTTP GET -> JSON endpoint returning {symbol, name, price, currency, updatedAt, ...}
///
/// Ozellikler:
///   * Kimlik dogrulama YOK (public endpoint)
///   * Rate limiting YOK (realtime price icin sinirsiz)
///   * CORS aktif - web/direct cagri mumkun
///   * Ticari kullanim IZINLI (ToS Section 9)
///   * ~ms seviyesinde guncelleme
///   * SPOT fiyat (USD/troy ounce) - futures degil
class GoldApiProvider implements MarketDataProvider {
  GoldApiProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const String _baseUrl = 'https://api.gold-api.com/price';

  /// gold-api.com, User-Agent'inda "Dart" (buyuk/kucuk harf farketmez)
  /// bulunan isteklere **HTTP 429** dondurur; tarayici / curl /
  /// python-requests UA'lari ile HTTP 200 doner (2026-10-06'da canli
  /// dogrulandi: "Dart/3.13 (dart:io)" -> 429, "KYRON (Flutter)" -> 200).
  ///
  /// `package:http` varsayilan UA'i `Dart/x.y (dart:io)` oldugu icin bu
  /// saglayicinin istekleri sessizce reddediliyordu ve Ons Altin/Ons Gumus
  /// icin **hic fiyat uretilmiyordu** (bkz. `_fetchSingle` -> statusCode != 200
  /// -> null). Tarayici taklidi yapmadan, kendini tanitan bir UA gonderiyoruz.
  static const String _userAgent = 'KYRON (Flutter)';

  /// Asset ID -> gold-api.com sembol eslesmesi
  static const Map<String, String> _assetToSymbol = {
    AssetCatalog.onsAltinId: 'XAU',
    AssetCatalog.onsGumusId: 'XAG',
  };

  @override
  String get id => 'gold-api';

  @override
  String get displayName => 'Gold API (Spot)';

  @override
  Duration get refreshInterval => const Duration(seconds: 60);

  @override
  bool supports(String assetId) {
    return _assetToSymbol.containsKey(assetId);
  }

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final supportedIds = assetIds.where(supports).toList();
    if (supportedIds.isEmpty) {
      return const Err(EmptyFailure('Gold API için uygun sembol yok.'));
    }

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
      return const Err(EmptyFailure('Gold API fiyat verisi boş döndü.'));
    }
    return Success(out);
  }

  Future<({String assetId, Quote quote})?> _fetchSingle(String assetId) async {
    final symbol = _assetToSymbol[assetId];
    if (symbol == null) return null;

    final url = '$_baseUrl/$symbol';

    try {
      final resp = await _httpClient
          .get(Uri.parse(url), headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        return null;
      }

      final body = resp.body.trim();
      if (body.isEmpty) return null;

      final json = jsonDecode(body) as Map<String, dynamic>;

      final price = json['price'];
      if (price is! num) return null;
      final priceValue = price.toDouble();
      if (!priceValue.isFinite || priceValue <= 0) return null;

      // updatedAt alani ISO8601 string olarak geliyor
      DateTime updatedAt;
      try {
        updatedAt = DateTime.parse(json['updatedAt'] as String).toLocal();
      } catch (_) {
        updatedAt = DateTime.now();
      }

      final asset = AssetCatalog.byId(assetId);
      final currency = asset?.currency ?? 'USD';

      final quote = Quote(
        assetId: assetId,
        source: QuoteSourceLabel.market,
        updatedAt: updatedAt,
        price: priceValue,
        currency: currency,
        freshness: _freshnessFromTimestamp(updatedAt),
      );

      return (assetId: assetId, quote: quote);
    } on FormatException {
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
  /// Gold API ms seviyesinde guncelliyor. 2 dakika altinda live sayilir.
  DataFreshness _freshnessFromTimestamp(DateTime updatedAt) {
    final now = DateTime.now();
    final age = now.difference(updatedAt);

    if (age < const Duration(minutes: 2)) {
      return DataFreshness.live;
    }
    if (age < const Duration(minutes: 5)) {
      return DataFreshness.delayed;
    }
    return DataFreshness.daily;
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    return const Err(EmptyFailure(
      'Gold API mum (OHLC) verisi sağlamaz.',
    ));
  }

  void dispose() {
    _httpClient.close();
  }
}