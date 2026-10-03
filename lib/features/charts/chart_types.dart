import 'package:flutter/material.dart';

/// Grafik cizim tipi.
enum ChartType {
  candlestick('Mum'),
  line('Çizgi'),
  area('Alan'),
  heikinAshi('Heikin Ashi'),
  ohlc('OHLC'),
  volume('Hacim');

  const ChartType(this.label);
  final String label;
}

/// Grafik uzerine cizilecek arac.
enum DrawingTool {
  none('Seç'),
  hLine('Yatay Çizgi'),
  vLine('Dikey Çizgi'),
  trendLine('Trend Çizgi'),
  channel('Paralel Kanal'),
  supportResistance('Destek/Direnç'),
  fibRetracement('Fibonacci Retracement'),
  fibExtension('Fibonacci Extension'),
  measure('Ölçü');

  const DrawingTool(this.label);
  final String label;
}

/// Aktif gosterge tanimi (ad + parametreler).
class IndicatorConfig {
  const IndicatorConfig({
    required this.id,
    required this.label,
    this.params = const <String, double>{},
    this.visible = true,
    this.pane = IndicatorPane.overlay,
    this.color,
  });

  /// Sabit kimlik: 'sma_20', 'rsi_14' gibi.
  final String id;
  final String label;

  /// Parametre adi -> deger. Or. {'period': 20}
  final Map<String, double> params;
  final bool visible;

  /// Ana fiyat grafigi uzerinde mi, ayririlmis panelde mi.
  final IndicatorPane pane;

  /// UI rengi; null ise varsayilan kullanilir.
  final Color? color;

  IndicatorConfig copyWith({
    Map<String, double>? params,
    bool? visible,
    Color? color,
    String? label,
  }) {
    return IndicatorConfig(
      id: id,
      label: label ?? this.label,
      params: params ?? this.params,
      visible: visible ?? this.visible,
      pane: pane,
      color: color ?? this.color,
    );
  }

  double get period => params['period'] ?? 14;

  @override
  bool operator ==(Object other) =>
      other is IndicatorConfig && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// Gosterge hangi bolgede cizilir.
enum IndicatorPane {
  /// Fiyatla ayni olcek (SMA, EMA, Bollinger, VWAP).
  overlay,

  /// 0-100 arasi ayri panel (RSI, Stoch, CCI, Williams).
  oscillator,

  /// Sifir merkezli ayri panel (MACD, OBV, hacim).
  zeroBased,
}

/// Gosterge kimlik uretimi ve varsayilan tanimlar.
abstract final class IndicatorPresets {
  static const String sma = 'sma';
  static const String ema = 'ema';
  static const String wma = 'wma';
  static const String vwap = 'vwap';
  static const String rsi = 'rsi';
  static const String macd = 'macd';
  static const String stoch = 'stoch';
  static const String cci = 'cci';
  static const String williams = 'willr';
  static const String bollinger = 'boll';
  static const String atr = 'atr';
  static const String volume = 'volume';
  static const String obv = 'obv';

  /// Desteklenen tum gostergeler (menu listesi).
  static const List<IndicatorDescriptor> all = [
    IndicatorDescriptor(sma, 'SMA', IndicatorPane.overlay, {'period': 20}),
    IndicatorDescriptor(ema, 'EMA', IndicatorPane.overlay, {'period': 20}),
    IndicatorDescriptor(wma, 'WMA', IndicatorPane.overlay, {'period': 20}),
    IndicatorDescriptor(vwap, 'VWAP', IndicatorPane.overlay, {}),
    IndicatorDescriptor(
        bollinger, 'Bollinger', IndicatorPane.overlay, {'period': 20, 'dev': 2}),
    IndicatorDescriptor(rsi, 'RSI', IndicatorPane.oscillator, {'period': 14}),
    IndicatorDescriptor(
        stoch, 'Stochastic', IndicatorPane.oscillator, {'period': 14}),
    IndicatorDescriptor(cci, 'CCI', IndicatorPane.oscillator, {'period': 20}),
    IndicatorDescriptor(
        williams, 'Williams %R', IndicatorPane.oscillator, {'period': 14}),
    IndicatorDescriptor(macd, 'MACD', IndicatorPane.zeroBased,
        {'fast': 12, 'slow': 26, 'signal': 9}),
    IndicatorDescriptor(atr, 'ATR', IndicatorPane.oscillator, {'period': 14}),
    IndicatorDescriptor(volume, 'Hacim', IndicatorPane.zeroBased, {}),
    IndicatorDescriptor(obv, 'OBV', IndicatorPane.zeroBased, {}),
  ];

  static IndicatorDescriptor? byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Ornek gosterge uretir.
  static IndicatorConfig make(String id) {
    final d = byId(id);
    if (d == null) return IndicatorConfig(id: id, label: id);
    return IndicatorConfig(
      id: d.id,
      label: d.label,
      params: Map.of(d.defaults),
      pane: d.pane,
    );
  }

  /// Panellere gore grupla.
  static Map<IndicatorPane, List<IndicatorConfig>> groupByPane(
      List<IndicatorConfig> list) {
    final map = <IndicatorPane, List<IndicatorConfig>>{};
    for (final i in list) {
      if (!i.visible) continue;
      map.putIfAbsent(i.pane, () => []).add(i);
    }
    return map;
  }
}

class IndicatorDescriptor {
  const IndicatorDescriptor(this.id, this.label, this.pane, this.defaults);

  final String id;
  final String label;
  final IndicatorPane pane;
  final Map<String, double> defaults;

  /// Duzenlenebilir parametreler.
  List<String> get paramKeys => defaults.keys.toList();
}
