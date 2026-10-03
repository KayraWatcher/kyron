import '../../domain/entities/candle.dart';
import '../../domain/entities/quote.dart';
import '../../domain/technical/indicators.dart';

/// İfadenin yonu. **Yorum/tavsiye icermez** - yalnizca gozlem.
enum StatementTone { neutral, above, below, rising, falling }

/// Nesnel bir teknik gozlem ifadesi.
///
/// **Kural:** Metin asla "al/sat", "yükselir", "güçlü", "zayıf",
/// "kesin", "tavsiye" gibi yargi/oneri icermez. Yalnizca olculmus
/// durumun tarifi yapilir.
class TechnicalStatement {
  const TechnicalStatement({
    required this.text,
    required this.tone,
    this.value,
    this.formattedValue,
  });

  final String text;
  final StatementTone tone;

  /// Ham deger (test icin).
  final double? value;

  /// Gorunen deger.
  final String? formattedValue;

  @override
  String toString() => text;

  @override
  bool operator ==(Object other) =>
      other is TechnicalStatement && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// Teknik gorunum ureteci.
///
/// Girdi olarak **saf veri** alir; ag servisi, context veya durum yoktur.
/// Boylece birebir unit test yazilabilir.
abstract final class TechnicalViewEngine {
  static const List<int> keyPeriods = [20, 50, 200];

  /// Tum gozlemleri uretir.
  static List<TechnicalStatement> build({
    required List<Candle> candles,
    required ChartInterval interval,
    Quote? quote,
    int rsiPeriod = 14,
    int macdFast = 12,
    int macdSlow = 26,
    int macdSignal = 9,
    int stochPeriod = 14,
    int stochSmooth = 3,
    int cciPeriod = 20,
    int williamsPeriod = 14,
    int atrPeriod = 14,
    int bollPeriod = 20,
    double bollDev = 2,
  }) {
    final out = <TechnicalStatement>[];
    if (candles.length < 2) return out;

    final closes = [for (final c in candles) c.close];
    final last = candles.last;
    final price = last.close;
    if (!price.isFinite || price <= 0) return out;

    out.add(TechnicalStatement(
      text: '${interval.label} zaman diliminde son kapanış '
          '${_n(price)} seviyesinde.',
      tone: StatementTone.neutral,
      value: price,
      formattedValue: _n(price),
    ));

    // ---- Hareketli ortalamalar ----
    for (final p in keyPeriods) {
      final sma = Indicators.sma(closes, p);
      final v = _last(sma);
      if (v == null) continue;
      out.add(_compare(
        subject: 'Fiyat',
        relation: 'SMA $p',
        price: price,
        other: v,
      ));
    }

    for (final p in [9, 21, 50]) {
      final ema = Indicators.ema(closes, p);
      final v = _last(ema);
      if (v == null) continue;
      out.add(_compare(
        subject: 'Fiyat',
        relation: 'EMA $p',
        price: price,
        other: v,
      ));
    }

    // ---- RSI ----
    final rsi = _last(Indicators.rsi(closes, rsiPeriod));
    if (rsi != null) {
      out.add(TechnicalStatement(
        text: 'RSI $rsiPeriod değeri ${rsi.toStringAsFixed(1)}.',
        tone: StatementTone.neutral,
        value: rsi,
        formattedValue: rsi.toStringAsFixed(1),
      ));
      out.add(_band(
        label: 'RSI $rsiPeriod',
        value: rsi,
        lo: 30,
        hi: 70,
        loText: '30 alt sınırının altında',
        hiText: '70 üst sınırının üzerinde',
        midText: '30 ile 70 arasında',
      ));
    }

    // ---- MACD ----
    final macd = Indicators.macd(
      closes,
      fast: macdFast,
      slow: macdSlow,
      signal: macdSignal,
    );
    final m = _last(macd.line('MACD'));
    final s = _last(macd.line('Sinyal'));
    final h = _last(macd.line('Histogram'));
    if (m != null && s != null) {
      out.add(TechnicalStatement(
        text: 'MACD değeri ${m.toStringAsFixed(4)}, sinyal çizgisi '
            '${s.toStringAsFixed(4)}.',
        tone: StatementTone.neutral,
        value: m,
        formattedValue: m.toStringAsFixed(4),
      ));
      out.add(TechnicalStatement(
        text: h == null
            ? 'MACD histogram değeri hesaplanamadı.'
            : 'MACD histogram değeri ${h.toStringAsFixed(4)}; '
                'MACD çizgisi sinyal çizgisinin '
                '${m >= s ? 'üzerinde' : 'altında'}.',
        tone: h == null
            ? StatementTone.neutral
            : (m >= s ? StatementTone.above : StatementTone.below),
        value: h,
        formattedValue: h?.toStringAsFixed(4),
      ));
    }

    // ---- Stokastik ----
    final st = Indicators.stoch(
      candles,
      kPeriod: stochPeriod,
      dPeriod: stochSmooth,
    );
    final k = _last(st.line('%K'));
    final d = _last(st.line('%D'));
    if (k != null) {
      out.add(TechnicalStatement(
        text: 'Stokastik %K değeri ${k.toStringAsFixed(1)}'
            '${d != null ? ', %D değeri ${d.toStringAsFixed(1)}' : ''}.',
        tone: StatementTone.neutral,
        value: k,
        formattedValue: k.toStringAsFixed(1),
      ));
    }

    // ---- CCI ----
    final cci = _last(Indicators.cci(candles, cciPeriod));
    if (cci != null) {
      out.add(TechnicalStatement(
        text: 'CCI $cciPeriod değeri ${cci.toStringAsFixed(1)}.',
        tone: StatementTone.neutral,
        value: cci,
        formattedValue: cci.toStringAsFixed(1),
      ));
      out.add(TechnicalStatement(
        text: 'CCI $cciPeriod değeri ${cci >= 0 ? 'sıfırın üzerinde' : 'sıfırın altında'}.',
        tone: cci >= 0 ? StatementTone.above : StatementTone.below,
        value: cci,
        formattedValue: cci.toStringAsFixed(1),
      ));
    }

    // ---- Williams %R ----
    final wr = _last(Indicators.williamsR(candles, williamsPeriod));
    if (wr != null) {
      out.add(TechnicalStatement(
        text: 'Williams %R değeri ${wr.toStringAsFixed(1)}.',
        tone: StatementTone.neutral,
        value: wr,
        formattedValue: wr.toStringAsFixed(1),
      ));
    }

    // ---- Bollinger ----
    final bb = Indicators.bollinger(
      closes,
      period: bollPeriod,
      multiplier: bollDev,
    );
    final up = _last(bb.line('Üst'));
    final mid = _last(bb.line('Orta'));
    final low = _last(bb.line('Alt'));
    if (up != null && low != null && mid != null) {
      out.add(TechnicalStatement(
        text: 'Bollinger $bollPeriod üst bandı ${_n(up)}, orta bandı '
            '${_n(mid)}, alt bandı ${_n(low)} seviyesinde.',
        tone: StatementTone.neutral,
        value: price,
        formattedValue: _n(price),
      ));
      final pos = up > low ? (price - low) / (up - low) : null;
      if (pos != null && pos.isFinite) {
        final pct = (pos * 100).clamp(0, 100).toDouble();
        out.add(TechnicalStatement(
          text: 'Fiyat, Bollinger bantları arasında ${pct.toStringAsFixed(0)} '
              '% konumunda (0 = alt bant, 100 = üst bant).',
          tone: StatementTone.neutral,
          value: pct,
          formattedValue: pct.toStringAsFixed(0),
        ));
      }
    }

    // ---- ATR ----
    final atr = _last(Indicators.atr(candles, atrPeriod));
    if (atr != null) {
      final pct = price > 0 ? atr / price * 100 : null;
      out.add(TechnicalStatement(
        text: 'ATR $atrPeriod değeri ${_n(atr)}'
            '${pct != null ? ', fiyatın %${pct.toStringAsFixed(2)} kadarı' : ''}.',
        tone: StatementTone.neutral,
        value: atr,
        formattedValue: _n(atr),
      ));
    }

    // ---- Hacim / OBV ----
    final obv = _last(Indicators.obv(candles));
    if (obv != null) {
      out.add(TechnicalStatement(
        text: 'OBV değeri ${_compact(obv)}.',
        tone: StatementTone.neutral,
        value: obv,
        formattedValue: _compact(obv),
      ));
    }

    // ---- Cizgi cizgi gore degisim (mum sirasi) ----
    final change = _seriesChange(candles);
    if (change != null) {
      out.add(change);
    }

    // ---- Donem ici tepe/dip ----
    out.add(TechnicalStatement(
      text: 'Görünen aralıkta en yüksek ${_n(_highOf(candles))}, '
          'en düşük ${_n(_lowOf(candles))} seviyesi görüldü.',
      tone: StatementTone.neutral,
    ));

    // ---- Anlik quote bilgisi ----
    if (quote != null) {
      final q = quote;
      final pc = q.previousClose;
      if (q.hasPrice && pc != null && pc > 0) {
        final diff = q.price! - pc;
        final pct = diff / pc * 100;
        if (pct.isFinite) {
          out.add(TechnicalStatement(
            text: 'Son fiyat, önceki kapanışa göre '
                '${pct >= 0 ? '%' : '%-'}${pct.abs().toStringAsFixed(2)} '
                '${pct >= 0 ? 'yüksek' : 'düşük'}.',
            tone: pct >= 0 ? StatementTone.rising : StatementTone.falling,
            value: pct,
            formattedValue: pct.toStringAsFixed(2),
          ));
        }
      }
      if (q.dayHigh != null) {
        out.add(TechnicalStatement(
          text: 'Günlük en yüksek ${_n(q.dayHigh!)}.',
          tone: StatementTone.neutral,
          value: q.dayHigh,
        ));
      }
      if (q.dayLow != null) {
        out.add(TechnicalStatement(
          text: 'Günlük en düşük ${_n(q.dayLow!)}.',
          tone: StatementTone.neutral,
          value: q.dayLow,
        ));
      }
      if (q.bid != null && q.ask != null) {
        out.add(TechnicalStatement(
          text: 'Alış ${_n(q.bid!)}, satış ${_n(q.ask!)}; '
              'makas ${_n(q.spread ?? 0)}.',
          tone: StatementTone.neutral,
          value: q.spread,
        ));
      }
    }

    return out;
  }

  // --------------------------------------------------------------------------

  static TechnicalStatement _compare({
    required String subject,
    required String relation,
    required double price,
    required double other,
  }) {
    final above = price >= other;
    final diff = other != 0 ? (price - other) / other * 100 : null;
    final pctText = diff != null && diff.isFinite
        ? ' (%${diff.abs().toStringAsFixed(2)} fark)'
        : '';
    return TechnicalStatement(
      text: '$subject $relation ${above ? 'üzerinde' : 'altında'} '
          '(${_n(other)})$pctText.',
      tone: above ? StatementTone.above : StatementTone.below,
      value: other,
      formattedValue: _n(other),
    );
  }

  static TechnicalStatement _band({
    required String label,
    required double value,
    required double lo,
    required double hi,
    required String loText,
    required String hiText,
    required String midText,
  }) {
    final tone = value < lo
        ? StatementTone.below
        : value > hi
            ? StatementTone.above
            : StatementTone.neutral;
    return TechnicalStatement(
      text: '$label ${value < lo ? loText : value > hi ? hiText : midText}.',
      tone: tone,
      value: value,
      formattedValue: value.toStringAsFixed(1),
    );
  }

  static TechnicalStatement? _seriesChange(List<Candle> candles) {
    if (candles.length < 2) return null;
    final first = candles.first.close;
    final last = candles.last.close;
    if (!first.isFinite || !last.isFinite || first <= 0) return null;
    final pct = (last - first) / first * 100;
    if (!pct.isFinite) return null;
    return TechnicalStatement(
      text: 'Görünen aralıkta kapanış, ilk mumdan bugüne '
          '${pct >= 0 ? '%' : '%-'}${pct.abs().toStringAsFixed(2)} '
          '${pct >= 0 ? 'arttı' : 'azaldı'}.',
      tone: pct > 0
          ? StatementTone.rising
          : pct < 0
              ? StatementTone.falling
              : StatementTone.neutral,
      value: pct,
      formattedValue: pct.toStringAsFixed(2),
    );
  }

  static double? _highOf(List<Candle> c) {
    double? m;
    for (final x in c) {
      if (x.high.isFinite && (m == null || x.high > m)) m = x.high;
    }
    return m;
  }

  static double? _lowOf(List<Candle> c) {
    double? m;
    for (final x in c) {
      if (x.low.isFinite && (m == null || x.low < m)) m = x.low;
    }
    return m;
  }

  static double? _last(List<double?>? s) {
    if (s == null) return null;
    for (var i = s.length - 1; i >= 0; i--) {
      final v = s[i];
      if (v != null && v.isFinite) return v;
    }
    return null;
  }

  static String _n(double? v) {
    if (v == null || !v.isFinite) return '—';
    if (v.abs() >= 100000) return _compact(v);
    final s = v.toStringAsFixed(v.abs() < 1 ? 4 : 2);
    return s;
  }

  static String _compact(double v) {
    if (!v.isFinite) return '—';
    final a = v.abs();
    if (a >= 1e9) return '${(v / 1e9).toStringAsFixed(2)} Mr';
    if (a >= 1e6) return '${(v / 1e6).toStringAsFixed(2)} Mn';
    if (a >= 1e3) return '${(v / 1e3).toStringAsFixed(2)} B';
    return v.toStringAsFixed(2);
  }
}
