/// Tek bir mum (candlestick) verisi.
///
/// Zaman damgasi Unix milisaniye. Tum alanlar zorunlu; kaynakta eksik
/// deger varsa [Candle] uretilmez (sahte 0 kullanilmaz).
class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });

  /// Unix milisaniye.
  final int time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);

  bool get isBullish => close >= open;
  bool get isBearish => close < open;

  double get range {
    final r = high - low;
    return r.isFinite && r > 0 ? r : 0;
  }

  /// Yuzde degisim (acilistan kapanisa).
  double? get changePercent {
    if (open == 0) return null;
    final v = (close - open) / open * 100;
    return v.isFinite ? v : null;
  }

  static Candle? fromJson(Map<String, dynamic> json) {
    final time = json['time'] ?? json['t'];
    final open = json['open'] ?? json['o'];
    final high = json['high'] ?? json['h'];
    final low = json['low'] ?? json['l'];
    final close = json['close'] ?? json['c'];
    final volume = json['volume'] ?? json['v'];

    if (time is! num || open is! num || high is! num || low is! num || close is! num) {
      return null;
    }
    final o = open.toDouble();
    final h = high.toDouble();
    final l = low.toDouble();
    final c = close.toDouble();
    if (!o.isFinite || !h.isFinite || !l.isFinite || !c.isFinite) return null;
    if (h < l) return null;

    return Candle(
      time: time.toInt(),
      open: o,
      high: h,
      low: l,
      close: c,
      volume: volume is num && volume.toDouble().isFinite ? volume.toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        if (volume != null) 'volume': volume,
      };

  @override
  bool operator ==(Object other) =>
      other is Candle && other.time == time && other.close == close;

  @override
  int get hashCode => Object.hash(time, close);

  @override
  String toString() => 'Candle(t: $time, o: $open, h: $high, l: $low, c: $close)';
}

/// Grafik zaman dilimleri.
///
/// Veri saglayici hangi dilimleri destekliyorsa kullanilir; desteklenmeyen
/// dilimler UI'da pasif gosterilir (uydurma veri uretilmez).
enum ChartInterval {
  m1('1d', '1 dk', Duration(minutes: 1)),
  m5('5d', '5 dk', Duration(minutes: 5)),
  m15('15d', '15 dk', Duration(minutes: 15)),
  m30('30d', '30 dk', Duration(minutes: 30)),
  h1('60m', '1 sa', Duration(hours: 1)),
  h4('240m', '4 sa', Duration(hours: 4)),
  d1('1d', '1 gün', Duration(days: 1)),
  w1('1wk', '1 hafta', Duration(days: 7)),
  mo1('1mo', '1 ay', Duration(days: 30));

  const ChartInterval(this.yahooRange, this.label, this.duration);

  /// Yahoo Finance `interval` parametresi.
  final String yahooRange;
  final String label;
  final Duration duration;
}

/// Bir varlik icin grafik verisi.
class CandleSeries {
  const CandleSeries({
    required this.assetId,
    required this.interval,
    required this.candles,
    this.isStale = false,
    this.updatedAt,
  });

  final String assetId;
  final ChartInterval interval;
  final List<Candle> candles;
  final bool isStale;
  final DateTime? updatedAt;

  bool get isEmpty => candles.isEmpty;
  int get length => candles.length;

  Candle? get first => candles.isEmpty ? null : candles.first;
  Candle? get last => candles.isEmpty ? null : candles.last;

  double? get sessionHigh {
    double? m;
    for (final c in candles) {
      if (m == null || c.high > m) m = c.high;
    }
    return m;
  }

  double? get sessionLow {
    double? m;
    for (final c in candles) {
      if (m == null || c.low < m) m = c.low;
    }
    return m;
  }
}
