import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/failures.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/quote.dart';
import '../../domain/providers/market_data_provider.dart';
import '../../domain/entities/data_freshness.dart';

/// Frankfurter (https://api.frankfurter.dev/) kaynakli [MarketDataProvider] uygulamasi.
///
/// Kapsam: USD bazli doviz kurlari (TRY, EUR, GBP, CHF, JPY) - ECB referans kurlar.
///
/// Protokol: HTTP GET -> JSON endpoint returning {amount, base, date, rates: {CURRENCY: rate}}
///
/// Ozellikler:
///   * Kimlik dogrulama YOK (public endpoint)
///   * ECB (Avrupa Merkez Bankasi) resmi referans kurlari
///   * Gunluk guncelleme (EOD - ~16:00 CET)
///   * Ticari kullanim IZINLI (Open data)
///   * Spot referans kur (bankalar arasi arka plan)
///   * JPY degeri "1 USD = X JPY" formatindadir (100 JPY bazli DEGIL)
///
/// NOT: Bu provider TCMB'ye fallback olarak tasarlanmistir.
/// TCMB gunde 1-2 kez resmi alis/satis kuru yayinlar; Frankfurter gunde 1 kez
/// ECB referans kuru yayinlar. TCMB basarisiz oldugunda Frankfurter devreye girer.
class FrankfurterProvider implements MarketDataProvider {
  FrankfurterProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const String _baseUrl = 'https://api.frankfurter.dev/v1/latest';

  /// Asset ID -> Frankfurter doviz kodu eslesmesi
  static const Map<String, String> _assetToCurrency = {
    AssetCatalog.usdTryId: 'TRY',
    AssetCatalog.eurTryId: 'EUR',
    AssetCatalog.gbpTryId: 'GBP',
    AssetCatalog.chfTryId: 'CHF',
    AssetCatalog.jpyTryId: 'JPY',
  };

  @override
  String get id => 'frankfurter';

  @override
  String get displayName => 'Frankfurter (ECB Reference)';

  @override
  Duration get refreshInterval => const Duration(hours: 12);

  @override
  bool supports(String assetId) {
    return _assetToCurrency.containsKey(assetId);
  }

  @override
  bool supportsCandles(String assetId) => false;

  @override
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds) async {
    final supportedIds = assetIds.where(supports).toList();
    if (supportedIds.isEmpty) {
      return const Err(EmptyFailure('Frankfurter için uygun sembol yok.'));
    }

    // Frankfurter tek istekle tum para birimlerini dondurur
    final symbols = supportedIds
        .map((id) => _assetToCurrency[id]!)
        .toSet()
        .join(',');

    final url = '$_baseUrl?base=USD&symbols=$symbols';

    try {
      final resp = await _httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return Err(NetworkFailure('Frankfurter HTTP ${resp.statusCode}'));
      }

      final body = resp.body.trim();
      if (body.isEmpty) {
        return const Err(EmptyFailure('Frankfurter bos dondu.'));
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      final ratesJson = json['rates'] as Map<String, dynamic>?;
      if (ratesJson == null || ratesJson.isEmpty) {
        return const Err(EmptyFailure('Frankfurter kur verisi yok.'));
      }

      final base = json['base'] as String?;
      if (base != 'USD') {
        return Err(BadRequestFailure('Frankfurter base USD degil: $base'));
      }

      // date alani "YYYY-MM-DD" formatinda
      final dateStr = json['date'] as String?;
      DateTime updatedAt;
      try {
        updatedAt = dateStr != null
            ? DateTime.parse(dateStr).toLocal()
            : DateTime.now();
      } catch (_) {
        updatedAt = DateTime.now();
      }

      final out = <String, Quote>{};

      for (final assetId in supportedIds) {
        final currencyCode = _assetToCurrency[assetId]!;
        final rate = ratesJson[currencyCode];

        if (rate is! num) continue;
        final rateValue = rate.toDouble();
        if (!rateValue.isFinite || rateValue <= 0) continue;

        // Frankfurter USD->CURRENCY dondurur (orn. 1 USD = 49.157 TRY)
        // Bu zaten spot kur formatindadir.
        // JPY icin de "1 USD = 158.23 JPY" dondurur (100 JPY bazli DEGIL)

        // NOT: TCMB JPY'yi 100 JPY bazli verir (orn. 31.01).
        // Frankfurter 1 USD = X JPY verir (orn. 158.23).
        // Bu provider TCMB fallback'i oldugu icin, JPY icin birim uyumsuzlugu
        // olabilir. Consumer (TcmbFxMarketDataProvider) bu provider'i sadece
        // %degisim icin kullandigi icin sorun yoktur.
        // Eger bu provider dogrudan fiyat icin kullanilacaksa, JPY icin
        // rate / 100 donusumu gerekir. Simdilik ham deger dondurulur.

        final asset = AssetCatalog.byId(assetId);
        final quoteCurrency = asset?.currency ?? 'TRY';

        final quote = Quote(
          assetId: assetId,
          source: QuoteSourceLabel.market,
          updatedAt: updatedAt,
          price: rateValue,
          currency: quoteCurrency,
          freshness: DataFreshness.daily,
        );

        out[assetId] = quote;
      }

      if (out.isEmpty) {
        return const Err(EmptyFailure('Frankfurter gecerli kur verisi yok.'));
      }
      return Success(out);
    } on FormatException {
      return const Err(ParseFailure('Frankfurter veri okunamadi.'));
    } on TimeoutException {
      return const Err(NetworkFailure('Frankfurter zaman asimi.'));
    } on http.ClientException {
      return const Err(NetworkFailure('Frankfurter baglanti hatasi.'));
    } catch (_) {
      return const Err(UnknownFailure('Frankfurter beklenmeyen hata.'));
    }
  }

  @override
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    return const Err(EmptyFailure(
      'Frankfurter mum (OHLC) verisi sağlamaz.',
    ));
  }

  void dispose() {
    _httpClient.close();
  }
}