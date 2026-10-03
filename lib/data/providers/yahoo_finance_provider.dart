import 'dart:convert';

import '../../core/error/failures.dart';
import '../../core/network/api_client.dart';
import '../../domain/candle/candle_aggregator.dart';
import '../../domain/entities/candle.dart';

/// Yahoo Finance `chart` API'sinden donen meta bilgisi.
class YahooQuoteMeta {
  const YahooQuoteMeta({
    required this.symbol,
    this.currency,
    this.price,
    this.previousClose,
    this.chartPreviousClose,
    this.change,
    this.changePercent,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.marketTime,
    this.exchangeName,
    this.isRegularMarketTime = false,
    this.regularMarketStart,
    this.regularMarketEnd,
  });

  final String symbol;
  final String? currency;
  final double? price;
  final double? previousClose;
  final double? chartPreviousClose;
  final double? change;
  final double? changePercent;
  final double? dayHigh;
  final double? dayLow;
  final double? volume;
  final double? fiftyTwoWeekHigh;
  final double? fiftyTwoWeekLow;
  final DateTime? marketTime;
  final String? exchangeName;
  final bool isRegularMarketTime;

  /// Duzenli piyasa oturumunun baslangic/bitis anlari (Yahoo'dan gelir).
  ///
  /// Bu alanlar varken piyasa acik/kapali durumu **veriden okunur**;
  /// yoksa tazelik [DataFreshness.unknown] birakilir (uydurulmaz).
  final DateTime? regularMarketStart;
  final DateTime? regularMarketEnd;

  /// Simdi itibariyle duzenli oturum acik mi?
  bool isMarketOpenAt(DateTime utcNow) {
    final s = regularMarketStart;
    final e = regularMarketEnd;
    if (s == null || e == null) return false;
    return !utcNow.isBefore(s) && utcNow.isBefore(e);
  }

  /// Piyasa oturum bilgisi saglayici tarafindan verilmis mi?
  bool get hasTradingSession => regularMarketStart != null && regularMarketEnd != null;

  double? get effectivePreviousClose => previousClose ?? chartPreviousClose;

  double? get effectiveChange {
    final c = change;
    if (c != null) return c;
    final p = price;
    final pc = effectivePreviousClose;
    if (p == null || pc == null) return null;
    final v = p - pc;
    return v.isFinite ? v : null;
  }

  double? get effectiveChangePercent {
    final c = changePercent;
    if (c != null) return c;
    final p = price;
    final pc = effectivePreviousClose;
    if (p == null || pc == null || pc == 0) return null;
    final v = (p - pc) / pc * 100;
    return v.isFinite ? v : null;
  }

  bool get hasData => price != null;
}

/// Yahoo Finance `chart` ucu.
///
/// Ucretsiz ve anahtarsiz; resmi API olarak tanimlanmamistir, bu nedenle
/// mimaride [YahooFinanceProvider] arayuzunun arkasinda tutulur ki
/// ileride lisansli bir saglayiciyla degistirilebilsin.
///
/// Kaynak: query1.finance.yahoo.com/v8/finance/chart/{symbol}
/// Dogrulanmis ornek: THYAO.IS -> 1 dakikalik OHLCV + meta.
class YahooFinanceProvider {
  YahooFinanceProvider(
    this._client, {
    this._host = 'query1.finance.yahoo.com',
  });

  final ApiClient _client;
  final String _host;

  Uri _chartUri(String symbol, String interval, String range) => Uri.parse(
        'https://$_host/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range&includePrePost=false',
      );

  /// Tek sembol icin anlik meta (fiyat) bilgisi.
  Future<Result<YahooQuoteMeta>> fetchQuote(String symbol) async {
    final res = await _client.getText(
      _chartUri(symbol, '1d', '5d'),
      headers: _headers,
      overrideTimeout: const Duration(seconds: 12),
    );
    return res.when(onSuccess: (body) => _parseMeta(symbol, body),
        onFailure: (f) => Err(f));
  }

  /// Birden fazla sembolu paralel ceker.
  ///
  /// Tek bir sembol hatali olsa bile digerleri doner.
  Future<Result<Map<String, YahooQuoteMeta>>> fetchQuotes(
    Iterable<String> symbols, {
    int concurrency = 6,
  }) async {
    final unique = symbols.toSet();
    if (unique.isEmpty) {
      return const Err(EmptyFailure('Sembol listesi boş.'));
    }

    final result = <String, YahooQuoteMeta>{};
    Failure? lastFailure;

    final list = unique.toList();
    for (var i = 0; i < list.length; i += concurrency) {
      final batch = list.sublist(
        i,
        i + concurrency > list.length ? list.length : i + concurrency,
      );
      final responses = await Future.wait(batch.map(fetchQuote));
      for (var j = 0; j < batch.length; j++) {
        final r = responses[j];
        if (r case Success(data: final meta)) {
          if (meta.hasData) result[batch[j]] = meta;
        } else {
          lastFailure = r.failureOrNull ?? lastFailure;
        }
      }
    }

    if (result.isEmpty) {
      return Err(lastFailure ?? const NetworkFailure());
    }
    return Success(result);
  }

  /// Mum serisi cek.
  Future<Result<CandleSeries>> fetchCandles({
    required String symbol,
    required ChartInterval interval,
    int limit = 300,
  }) async {
    final (yahooInterval, range) = _mapInterval(interval, limit);

    final res = await _client.getText(
      _chartUri(symbol, yahooInterval, range),
      headers: _headers,
      overrideTimeout: const Duration(seconds: 20),
    );

    return res.when(
      onSuccess: (body) => _parseCandles(symbol, interval, body, limit),
      onFailure: (f) => Err(f),
    );
  }

  /// [ChartInterval] -> (Yahoo interval, range).
  ///
  /// Dogrulama: `test/interval_probe.dart` her dilim icin donen mumlarin
  /// araligini olcer. 4 saat disindaki tum dilimler birebir eslesir (%100).
  /// 4 saatlik dilim Yahoo'da olmadigi icin 60m alinip birlestirilir.
  (String, String) _mapInterval(ChartInterval interval, int limit) {
    switch (interval) {
      case ChartInterval.m1:
        return ('1m', '1d');
      case ChartInterval.m5:
        return ('5m', '5d');
      case ChartInterval.m15:
        return ('15m', '5d');
      case ChartInterval.m30:
        return ('30m', '5d');
      case ChartInterval.h1:
        return ('60m', '1mo');
      case ChartInterval.h4:
        // Yahoo 240m sunmaz (dogrulandi: 4 saat istegi 1 saatlik mum
        // donuyor). Bu yuzden **gerçek** 60m mumlari alinip istemci
        // tarafinda 4 saatlik kovalara birlestirilir; "4 sa" etiketi
        // artik donen veriyle birebir aynidir (bkz. aggregateCandles).
        return ('60m', '3mo');
      case ChartInterval.d1:
        return ('1d', '1y');
      case ChartInterval.w1:
        return ('1wk', '5y');
      case ChartInterval.mo1:
        return ('1mo', 'max');
    }
  }

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  };

  Result<YahooQuoteMeta> _parseMeta(String symbol, String body) {
    try {
      final meta = _extractMeta(body, symbol);
      if (meta == null || !meta.hasData) {
        return Err(EmptyFailure('$symbol için fiyat verisi bulunamadı.'));
      }
      return Success(meta);
    } catch (e) {
      return Err(ParseFailure('Veri okunamadı.', e));
    }
  }

  Result<CandleSeries> _parseCandles(
    String symbol,
    ChartInterval interval,
    String body,
    int limit,
  ) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final chart = decoded['chart'];
      if (chart is! Map<String, dynamic>) {
        return const Err(ParseFailure('Yanıt biçimi beklenen gibi değil.'));
      }
      if (chart['error'] != null) {
        final err = chart['error'];
        final description =
            err is Map && err['description'] is String ? err['description'] : null;
        return Err(BadRequestFailure(
          description ?? '$symbol için veri alınamadı.',
        ));
      }

      final result = chart['result'];
      if (result is! List || result.isEmpty) {
        return Err(EmptyFailure('$symbol için mum verisi bulunamadı.'));
      }

      final first = result.first;
      if (first is! Map<String, dynamic>) {
        return const Err(ParseFailure('Beklenmeyen yanıt yapısı.'));
      }

      final timestamps = first['timestamp'];
      if (timestamps is! List || timestamps.isEmpty) {
        return Err(EmptyFailure('$symbol için mum verisi bulunamadı.'));
      }

      final indicators = first['indicators'];
      if (indicators is! Map<String, dynamic>) {
        return const Err(ParseFailure('Mum verisi eksik.'));
      }
      final quotes = indicators['quote'];
      if (quotes is! List || quotes.isEmpty || quotes.first is! Map) {
        return const Err(ParseFailure('Mum verisi eksik.'));
      }
      final q = (quotes.first as Map).cast<String, dynamic>();

      final opens = _numList(q['open']);
      final highs = _numList(q['high']);
      final lows = _numList(q['low']);
      final closes = _numList(q['close']);
      final volumes = _numList(q['volume']);

      final candles = <Candle>[];
      for (var i = 0; i < timestamps.length; i++) {
        final t = timestamps[i];
        if (t is! num) continue;

        final o = _at(opens, i);
        final h = _at(highs, i);
        final l = _at(lows, i);
        final c = _at(closes, i);
        // Yahoo aralik disindaki mumlari null olarak dondurur; atla.
        if (o == null || h == null || l == null || c == null) continue;
        if (h < l) continue;

        candles.add(Candle(
          time: t.toInt() * 1000,
          open: o,
          high: h,
          low: l,
          close: c,
          volume: _at(volumes, i),
        ));
      }

      if (candles.isEmpty) {
        return Err(EmptyFailure('$symbol için geçerli mum bulunamadı.'));
      }

      // 4 saatlik dilim: Yahoo 240m sunmadigi icin GERCEK 60m mumlardan
      // hesaplanir. Uydurma mum yok - her kova gercek mumlarin birlesimidir.
      final merged = interval == ChartInterval.h4
          ? aggregateCandles(candles, bucket: const Duration(hours: 4))
          : candles;

      final trimmed = merged.length > limit
          ? merged.sublist(merged.length - limit)
          : merged;

      return Success(CandleSeries(
        assetId: symbol,
        interval: interval,
        candles: trimmed,
        updatedAt: DateTime.now(),
      ));
    } on FormatException catch (e) {
      return Err(ParseFailure('Veri okunamadı.', e));
    } catch (e) {
      return Err(UnknownFailure('Beklenmeyen bir hata oluştu.', e));
    }
  }

  YahooQuoteMeta? _extractMeta(String body, String symbol) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final chart = decoded['chart'];
    if (chart is! Map<String, dynamic>) return null;
    if (chart['error'] != null) return null;
    final result = chart['result'];
    if (result is! List || result.isEmpty) return null;
    final first = result.first;
    if (first is! Map<String, dynamic>) return null;
    final meta = first['meta'];
    if (meta is! Map<String, dynamic>) return null;

    final price = _d(meta['regularMarketPrice']);
    final prev = _d(meta['previousClose']) ?? _d(meta['chartPreviousClose']);

    // Piyasa oturumu (acik/kapali) bilgisi - tazelik icin gercek kaynak.
    DateTime? regStart;
    DateTime? regEnd;
    final periods = meta['currentTradingPeriod'];
    if (periods is Map) {
      final regular = periods['regular'];
      if (regular is Map) {
        regStart = _epochSeconds(regular['start']);
        regEnd = _epochSeconds(regular['end']);
      }
    }

    return YahooQuoteMeta(
      symbol: (meta['symbol'] as String?) ?? symbol,
      currency: meta['currency'] as String?,
      price: price,
      previousClose: prev,
      chartPreviousClose: _d(meta['chartPreviousClose']),
      change: _d(meta['regularMarketChange']),
      changePercent: _d(meta['regularMarketChangePercent']),
      dayHigh: _d(meta['regularMarketDayHigh']),
      dayLow: _d(meta['regularMarketDayLow']),
      volume: _d(meta['regularMarketVolume']),
      fiftyTwoWeekHigh: _d(meta['fiftyTwoWeekHigh']),
      fiftyTwoWeekLow: _d(meta['fiftyTwoWeekLow']),
      marketTime: meta['regularMarketTime'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (meta['regularMarketTime'] as num).toInt() * 1000,
              isUtc: true,
            )
          : null,
      exchangeName: meta['fullExchangeName'] as String?,
      isRegularMarketTime: meta['currentTradingPeriod'] != null,
      regularMarketStart: regStart,
      regularMarketEnd: regEnd,
    );
  }

  /// Unix saniye -> UTC DateTime. Gecersizse null (uydurulmaz).
  DateTime? _epochSeconds(dynamic raw) {
    if (raw is! num) return null;
    final sec = raw.toInt();
    if (sec <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true);
  }

  List<double?>? _numList(dynamic raw) {
    if (raw is! List) return null;
    return raw.map((e) => e is num ? e.toDouble() : null).toList();
  }

  double? _at(List<double?>? list, int i) {
    if (list == null || i >= list.length) return null;
    final v = list[i];
    if (v == null || !v.isFinite) return null;
    return v;
  }

  double? _d(dynamic raw) {
    if (raw is! num) return null;
    final v = raw.toDouble();
    return v.isFinite ? v : null;
  }
}
