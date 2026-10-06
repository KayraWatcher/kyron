import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_view.dart';
import '../../domain/entities/asset.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/candle.dart';
import '../../domain/entities/quote.dart';
import '../../shared/widgets/price_flash.dart';
import '../../shared/widgets/quote_card.dart';
import '../alerts/alert_providers.dart';
import '../alerts/alert_sheet.dart';
import '../charts/chart_painter.dart';
import '../charts/chart_types.dart';
import '../charts/drawing.dart';
import '../charts/heikin_ashi.dart';
import '../charts/indicator_engine.dart';
import '../charts/interactive_chart.dart';
import '../technical/technical_view.dart';
import 'asset_detail_providers.dart';
import 'asset_news_list.dart';
import 'widgets/candle_ohlc_bar.dart';
import 'widgets/drawing_toolbar.dart';
import 'widgets/indicator_sheet.dart';

/// Varlik detay sayfasi (Aşama 8/9/10).
class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.assetId});

  final String assetId;

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  final List<Drawing> _drawings = [];
  DrawingTool _activeTool = DrawingTool.none;
  bool _fullscreen = false;
  int _tab = 0; // 0 = Grafik, 1 = Teknik Görünüm

  @override
  void initState() {
    super.initState();
    // Varsayilan gostergeler: RSI + EMA20 (hafif, acilista hesaplanir).
    Future.microtask(() {
      // Widget bu esnada zaten kaldirilmis olabilir (hizli geri donus):
      // monte edilmemis bir `ConsumerState` uzerinden provider yazmak
      // hata uretir.
      if (!mounted) return;
      final n = ref.read(activeIndicatorsProvider.notifier);
      if (ref.read(activeIndicatorsProvider).isEmpty) {
        n.add(IndicatorPresets.make(IndicatorPresets.rsi));
        n.add(IndicatorPresets.make(IndicatorPresets.ema));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(widget.assetId);
    final interval = ref.watch(chartIntervalProvider);
    final chartType = ref.watch(chartTypeProvider);
    // Faz F (yeniden kurulum daraltma):
    //  * Grafik sekmesinde fiyat tikleri **ekranin tamamini** yeniden
    //    kurmasin; fiyat bilgisi basligin kendisi izler.
    //  * Teknik gorunum tum degeri ister, o zaman izlenir.
    //  * Ayrıca alarm sayisi yalnizca bu varliga ait olan degistiginde
    //    guncellenir (ref.select).
    final quote = _tab == 1
        ? ref.watch(assetQuoteProvider(widget.assetId)).value
        : null;

    final body = Column(
      children: [
        if (!_fullscreen) ...[
          // ---- Bilgi basligi ----
          _Header(
            assetId: widget.assetId,
          ),

          // ---- Sekmeler ----
          _tabBar(theme),
        ],

        if (_tab == 0) ...[
          if (!_fullscreen)
            _IntervalBar(
              selected: interval,
              onChanged: (i) {
                // Dilim gercekten degistiyse eski imlec mumu artik bu
                // seride anlamsizdir; **olay baglaminda** (kullanici
                // tiklamasi) temizlenir. Provider yazimi `didUpdateWidget`
                // icinde yapilirsa Riverpod "widget agaci kurulurken
                // provider degistirme" hatasi verirdi (cihaz testinde
                // goruldu) - yazi olaya tasinmistir.
                if (i != interval &&
                    ref.read(crosshairCandleProvider(widget.assetId)) !=
                        null) {
                  ref.read(crosshairCandleProvider(widget.assetId).notifier)
                      .pick(null);
                }
                ref.read(chartIntervalProvider.notifier).select(i);
              },
            ),
          const SizedBox(height: 4),
          Expanded(
            // Grafik durumu BURADA yasar (capraz imlec her harekette
            // ekranin tamami yeniden kurulmaz - Faz F performans kurali).
            child: _ChartSection(
              assetId: widget.assetId,
              interval: interval,
              chartType: chartType,
              activeTool: _activeTool,
              drawings: _drawings,
              onToolChanged: (t) => setState(() => _activeTool = t),
              onDrawingsChanged: (d) => setState(() {
                _drawings
                  ..clear()
                  ..addAll(d);
              }),
            ),
          ),
          DrawingToolbar(
            activeTool: _activeTool,
            onToolSelected: (t) => setState(() => _activeTool = t),
            onIndicators: () => showIndicatorSheet(context),
            onChartType: () => _showChartTypePicker(context),
            onToggleFullscreen: () =>
                setState(() => _fullscreen = !_fullscreen),
            hasDrawings: _drawings.isNotEmpty,
            onClearDrawings: () => setState(_drawings.clear),
            fullscreen: _fullscreen,
          ),
        ] else if (_tab == 1) ...[
          Expanded(
            child: _TechnicalViewTab(
              assetId: widget.assetId,
              interval: interval,
              quote: quote,
            ),
          ),
        ] else ...[
          // ---- Haberler sekmesi: varlikla **gercekten** iliskili haberler ----
          // Iliski [NewsImpact] kurallariyla belirlenir (kategori + spesifik
          // varlik adi + merkez bankasi olayi); anahtar kelime taramasi yok.
          // Kanit yoksa bos liste gosterilmez.
          Expanded(
            child: AssetNewsList(
              assetId: widget.assetId,
              parentIds: asset?.parentIds ?? const <String>[],
            ),
          ),
        ],
      ],
    );

    // Android geri tusu / kenardan kaydirma: ekrani kapatmadan once
    //  * tam ekran modundan cikis,
    //  * aktif cizim aracinin iptali
    // yapilir; geri tusu boylece grafikte yarim kalmis durumu "tutarli"
    // kapatir ve kullanici istemedigi halde detay sayfasindan dusmez.
    // `canPop` true iken sistem normal pop islemini yapar (davranis degismez).
    final popScope = PopScope(
      canPop: !_fullscreen && _activeTool == DrawingTool.none,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_fullscreen) {
          setState(() => _fullscreen = false);
        } else if (_activeTool != DrawingTool.none) {
          setState(() => _activeTool = DrawingTool.none);
        }
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(asset?.name ?? widget.assetId),
          actions: [
            Consumer(
              builder: (context, ref, _) {
                final count = ref.watch(
                  alertsProvider.select(
                    (list) =>
                        list.where((a) => a.assetId == widget.assetId).length,
                  ),
                );
                return IconButton(
                  tooltip: 'Bu varlık için alarm ekle',
                  onPressed: () => showAlertSheet(context,
                      assetId: widget.assetId),
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.add_alert_rounded),
                  ),
                );
              },
            ),
            if (asset != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Text(
                    asset.symbol,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(child: body),
      ), // Scaffold
    ); // PopScope
    return popScope;
  }

  Widget _tabBar(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Row(
        children: [
          _tabBtn(theme, 0, 'Grafik', Icons.candlestick_chart_rounded),
          _tabBtn(theme, 1, 'Teknik Görünüm', Icons.insights_rounded),
          _tabBtn(theme, 2, 'Haberler', Icons.article_outlined),
        ],
      ),
    );
  }

  Widget _tabBtn(ThemeData theme, int i, String label, IconData icon) {
    final selected = _tab == i;
    return Expanded(
      child: InkWell(
        onTap: () {
          // Grafik bolumunden uzaklasildi: imlec secimi birakilir.
          // Yoksa ust baslik "Gecmis mum" modunda kalir ve grafige geri
          // donuldugunda ekranda imlec yokken eski mum gosterilir.
          // (Ekranin kendisi kapandiginda autoDispose zaten sifirlar.)
          if (i != 0) _clearCrosshairPick();
          setState(() => _tab = i);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              // Dar ekranda (360px) veya genis yaz tipi olcumunde etiket
              // satiri tasmamali: Flexible + ellipsis ile kirpilir.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Grafik sekmesinden uzaklasildiginda imlecin sectigi mumu birakir.
  ///
  /// Aksi halde ust baslik "gecmis mum" modunda kalir; grafige geri
  /// donuldugunde ekranda imlec yokken eski mum gosterilir. Secili mum
  /// zaten yoksa dokunulmaz (gereksiz yazma / rebuild yok).
  void _clearCrosshairPick() {
    final provider = crosshairCandleProvider(widget.assetId);
    if (ref.read(provider) == null) return;
    ref.read(provider.notifier).pick(null);
  }

  Future<void> _showChartTypePicker(BuildContext context) async {
    final selected = await showModalBottomSheet<ChartType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Grafik Tipi',
                style: Theme.of(ctx).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final t in ChartType.values)
              ListTile(
                leading: Icon(_typeIcon(t)),
                title: Text(t.label),
                trailing: ref.read(chartTypeProvider) == t
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      ref.read(chartTypeProvider.notifier).select(selected);
    }
  }

  IconData _typeIcon(ChartType t) => switch (t) {
        ChartType.candlestick => Icons.candlestick_chart_rounded,
        ChartType.line => Icons.show_chart_rounded,
        ChartType.area => Icons.area_chart_rounded,
        ChartType.heikinAshi => Icons.candlestick_chart_outlined,
        ChartType.ohlc => Icons.bar_chart_rounded,
        ChartType.volume => Icons.bar_chart_rounded,
      };
}

// ---------------------------------------------------------------------------
// Grafik bolumu: OHLC ustbilgi + interaktif grafik (**ayri durum**)
// ---------------------------------------------------------------------------

/// Grafik ve OHLC ustbilgisini kendi durumuyla barindiran bolum.
///
/// Neden ayri? Capraz imlec her hareketinde ekranin tamami (baslik,
/// sekmeler, arac cubugu) yeniden kurulmasin; yalnizca bu alt agac
/// guncellensin. Ayrica ustbilgi artik imlecin mumunu takip edebilsin
/// (GOLD v2 / Faz E + F).
class _ChartSection extends ConsumerStatefulWidget {
  const _ChartSection({
    required this.assetId,
    required this.interval,
    required this.chartType,
    required this.activeTool,
    required this.drawings,
    required this.onToolChanged,
    required this.onDrawingsChanged,
  });

  final String assetId;
  final ChartInterval interval;
  final ChartType chartType;
  final DrawingTool activeTool;
  final List<Drawing> drawings;

  /// Arac cubugundan secim / cizim tamamlanmasi ust agaca bildirilir.
  final ValueChanged<DrawingTool> onToolChanged;
  final ValueChanged<List<Drawing>> onDrawingsChanged;

  @override
  ConsumerState<_ChartSection> createState() => _ChartSectionState();
}

class _ChartSectionState extends ConsumerState<_ChartSection> {
  ChartInteraction _interaction = ChartInteraction.empty;

  /// Imlec cozumlemesi icin en son gorulen serinin kendisi.
  ///
  /// Ustteki ana fiyat, kullanici gecmise kaydirinca bu seriden o mumu
  /// okur (`crosshairCandleProvider`).
  List<Candle> _lastCandles = const <Candle>[];

  @override
  void didUpdateWidget(covariant _ChartSection old) {
    super.didUpdateWidget(old);
    if (old.activeTool != widget.activeTool) {
      _interaction = _interaction.copyWith(activeTool: widget.activeTool);
    }
    if (old.interval != widget.interval) {
      // Dilim degisti: eski imlec indeksi yeni seride anlamsizdir.
      // Yalnizca **yerel** durum sifirlanir; `crosshairCandleProvider`
      // yazimi yasam dongusu yerine dilim degisikliginin oldugu olay
      // baglaminda yapilir (yukaridaki `_IntervalBar.onChanged`).
      // Neden: widget yasam dongusu build asamasidir ve Riverpod orada
      // provider degistirmeye izin vermez.
      _interaction = ChartInteraction(activeTool: widget.activeTool);
      _lastCandles = const <Candle>[];
    }
  }

  /// Heikin Ashi donusum onbellegi (ayni kaynak icin yeniden hesaplanmaz).
  List<Candle>? _haSource;
  List<Candle>? _haCache;

  /// Grafikte **goruntulenen** seri.
  ///
  /// Heikin Ashi seciliyken gercek seriden turetilir; kaynak seri
  /// (`series.candles`) degismez, boylece kullanici Mum moduna dondugunde
  /// veri kaybolmaz. Donusum bellekte saklanir - her build'de yeniden
  /// hesaplanmaz. Dizin hizasi birebir korundugu icin imlec indeksi ve
  /// gosterge serileri ayni mumlara isaret etmeye devam eder.
  List<Candle> _displaySeries(List<Candle> source) {
    if (widget.chartType != ChartType.heikinAshi) return source;
    if (!identical(_haSource, source)) {
      _haSource = source;
      _haCache = HeikinAshi.convert(source);
    }
    return _haCache ?? source;
  }

  @override
  Widget build(BuildContext context) {
    final assetId = widget.assetId;
    final interval = widget.interval;

    final candlesAsync = ref.watch(assetCandlesProvider((assetId, interval)));
    // Gosterge hesabi yalnizca grafik bolumunde calisir; teknik gorunum
    // veya ustbilgi asla yeniden hesaplatmaz (Faz F).
    final indicators =
        ref.watch(computedIndicatorsProvider((assetId, interval)));

    final view = toViewState<CandleSeries>(
      candlesAsync,
      isEmpty: (s) => s.candles.isEmpty,
    );

    return StateView<CandleSeries>(
      state: view,
      onRetry: () => ref.invalidate(assetCandlesProvider((assetId, interval))),
      emptyMessage: 'Bu zaman dilimi için grafik verisi bulunamadı.',
      emptyIcon: Icons.show_chart_rounded,
      builder: (series) {
        // Grafikte goruntulenen seri (Heikin Ashi seciliyse donusturulmus).
        // Ust bilgi satiri (OHLC) ve imlec mumu da ayni seriyi kullandigi
        // icin renk ile deger asla birbirini tutmaz.
        final candles = _displaySeries(series.candles);
        final decimals = _decimals(candles);
        _lastCandles = candles;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Faz E / gereksinim 5: OHLC + hacim + tarih = imlecin mumu.
            CandleOhlcBar(
              candles: candles,
              interaction: _interaction,
              decimals: decimals ?? 2,
            ),
            Expanded(
              child: InteractiveChart(
                // Anahtar yalnizca **varlik + dilim**: grafik tipi veya
                // gosterge sayisi degistiginde widget State'i yeniden
                // kurulursa zoom/pan konumu, yarim cizim ve imlec durumu
                // silinir (kullanici "grafik sifirlandi" der). Bunlar
                // artik `didUpdateWidget` ile canli guncellenir.
                key: ValueKey('$assetId${interval.name}'),
                candles: candles,
                chartType: widget.chartType,
                overlays: indicators
                    .where((i) => i.config.pane == IndicatorPane.overlay)
                    .toList(),
                panels: _panels(indicators),
                drawings: widget.drawings,
                interaction: _interaction,
                onInteractionChanged: _onInteraction,
                onDrawingsChanged: widget.onDrawingsChanged,
                onCrosshairRelease: () {
                  // Crosshair kapandiginda (parmak birakildiginda/cancel oldugunda)
                  // ust basligi canli moda dondurmek icin secili mumu temizle.
                  ref.read(crosshairCandleProvider(widget.assetId).notifier).pick(null);
                },
                decimals: decimals,
              ),
            ),
          ],
        );
      },
    );
  }

  void _onInteraction(ChartInteraction i) {
    // Cizim araci tamamlandiginda grafik kendi aracini kapatir; ust agaca
    // bildir ki arac cubugu da guncellensin.
    if (i.activeTool != _interaction.activeTool) {
      widget.onToolChanged(i.activeTool);
    }

    // Imlecin sectigi mumu ust basliga aktar. Imlec kapaliyken (release/
    // cancel) `_syncCrosshairCandle` secimi null yapar -> ust baslik aninda
    // canli (guncel) fiyata doner. `crosshairChanged` ayni mum icinde
    // tekrar yazmayi onler; ayrica debounce/timer YOK - release aninda temiz.
    _syncCrosshairCandle(i);

    // Local interaction state (chart repaint için).
    if (mounted) setState(() => _interaction = i);
  }


  /// Imlecin uzerindeki mumu ust basliga aktarir (gereksinim: gecmise
  /// kaydirildiginda ustteki ana fiyat o tarihin fiyatina gecer).
  ///
  /// **Dikkat:** yalnizca imlec **farkli bir muma** gectiginde yazilir.
  /// Imlec ayni mumun icinde gezerken ust baslik tekrar tekrar
  /// yeniden kurulmaz (Faz F performans kurali).
  void _syncCrosshairCandle(ChartInteraction i) {
    final provider = crosshairCandleProvider(widget.assetId);
    final next = resolveCrosshairCandle(
      _lastCandles,
      i.showCrosshair ? i.crosshairIndex : null,
    );

    final prev = ref.read(provider);
    if (!crosshairChanged(prev, next)) return;
    ref.read(provider.notifier).pick(next);
  }

  static List<ChartPanel> _panels(List<ComputedIndicator> indicators) {
    final osc = <ComputedIndicator>[];
    final zero = <ComputedIndicator>[];
    for (final ci in indicators) {
      switch (ci.config.pane) {
        case IndicatorPane.oscillator:
          osc.add(ci);
        case IndicatorPane.zeroBased:
          zero.add(ci);
        case IndicatorPane.overlay:
          break;
      }
    }

    final out = <ChartPanel>[];
    if (osc.isNotEmpty) {
      out.add(ChartPanel(
        title: osc.map((e) => e.config.label).join(', '),
        items: osc,
      ));
    }
    if (zero.isNotEmpty) {
      out.add(ChartPanel(
        title: zero.map((e) => e.config.label).join(', '),
        items: zero,
      ));
    }
    return out;
  }

  static int? _decimals(List<Candle> candles) {
    if (candles.isEmpty) return null;
    final p = candles.last.close;
    if (!p.isFinite) return null;
    if (p >= 1000) return 2;
    if (p >= 1) return p.abs() < 10 ? 4 : 3;
    return 6;
  }
}

// ---------------------------------------------------------------------------
// Baslik: fiyat, degisim, alis/satis, tepe/dip
// ---------------------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    // Faz F: baslik kendi fiyatini izler; fiyat tikleri alttaki grafik
    // agacini (gostergeler + cizim) yeniden kurmaz.
    final quote = ref.watch(assetQuoteProvider(assetId));
    // Kullanici grafikte gecmise kaydirinca ustteki ana fiyat da o
    // mumun tarihine ve fiyatina gecer (imlec kalkarsa canli moda donulur).
    final picked = ref.watch(crosshairCandleProvider(assetId));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: switch (quote) {
        AsyncLoading() => const SizedBox(
            height: 96,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        AsyncError(:final error) => _headerError(context, ref, error),
        // KOK NEDEN DZELTMESI (cihaz testi, 2026-10-03):
        //
        // Canli icerik (`_headerData`: fiyat + hucreler + zaman damgasi) ile
        // imlec icerigi (`_headerPicked`: fiyat + 2 kisa satir) **farkli
        // yukseklikteydi** (~230px fark olcusildi). Imlec acilirken baslik
        // kisalir, Column'daki grafik alani yukari kayar; imlecin saklanan
        // yerel Y degeri eski geometriye ait oldugu icin yatay cizgi ve
        // fiyat etiketi parmagin ~230px USTUNDE cizilir. Chartin ust
        // kismina basan kullanici icin cizgi tamamen ekrandan disari kayar
        // -> "grafiye dokunuyorum ve hicbir tepki yok".
        //
        // Duzeltme: imlec modunda canli icerik ayni kutuda **gorunmez yer
        // tutar**. Stack'in yuksekligi boylece her kosulda canli icerigin
        // yuksekligine esit olur; imlec acilip/kapanirken baslik yuksekligi
        // DEGMEZ, grafik alani hic kaymaz, cizgi parmak konumunda kalir.
        // (Canli icerik her zaman imlec iceriginden uzun oldugu icin Stack
        // yuksekligi mod gecislerinde sabit kalir.)
        // (REGRESYON PROVASI SONRASI: duzeltme geri konuldu.)
        AsyncData(:final value) => picked == null
            ? _headerData(context, asset, value)
            : Stack(
                alignment: Alignment.topLeft,
                children: [
                  // Yer tutucu: canli icerik tam boyutlanir ama boyanmaz
                  // ve dokunma almaz (uzerine imlec icerigi biner).
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: 0,
                        child: _headerData(context, asset, value),
                      ),
                    ),
                  ),
                  // Imlec icerigi canli icerigin ustune ayni ust hizasinda
                  // biner: buyuk fiyat satiri ayni Y'de kalir, asagi kalan
                  // alan kartin kendi zeminiyle dolar.
                  Positioned.fill(
                    child: _headerPicked(context, asset, value, picked),
                  ),
                ],
              ),
      },
    );
  }

  Widget _headerError(BuildContext context, WidgetRef ref, Object error) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppPalette.neutral),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Fiyat verisi alınamadı',
                    style: theme.textTheme.titleSmall),
                Text(
                  'Bağlantınızı kontrol edip tekrar deneyin.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.neutral),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                ref.invalidate(assetQuoteProvider(assetId)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _headerData(BuildContext context, AssetDescriptor? asset, Quote q) {
    final theme = Theme.of(context);
    final pct = q.effectiveChangePercent;
    final priceText = q.hasPrice
        ? '${TrFormat.price(q.price)} ${q.currency ?? asset?.currency ?? ''}'
        : TrFormat.noData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kopma durumu: son GERCEK veri korunur ama "guncel degil"dir ve
        // istemci kendiliginen yeniden baglanmayi dener.
        if (q.isStale) ...[
          _StaleBanner(updatedAt: q.updatedAt),
          const SizedBox(height: 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: PriceFlash(
                text: priceText,
                price: q.price,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ChangeBadge(value: pct, percent: true, compact: false),
                const SizedBox(height: 2),
                Tooltip(
                  message: q.isStale
                      ? 'Bağlantı kurulamıyor; en son alınan gerçek fiyat '
                          'gösteriliyor. Uygulama kendiliğinden yeniden '
                          'deneyecek.'
                      : q.freshness.description,
                  child: Text(
                    q.isStale
                        ? 'Bağlantı yok'
                        : q.freshness.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppPalette.neutral),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _cell(context, 'Alış', q.bid),
            _cell(context, 'Satış', q.ask),
            _cell(context, 'Makas', q.spread, decimals: 4),
            _cell(context, 'Açılış', q.open),
            _cell(context, 'Önceki Kapanış', q.previousClose),
            _cell(context, 'Gün En Yüksek', q.dayHigh),
            _cell(context, 'Gün En Düşük', q.dayLow),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
                Icons.schedule_rounded, size: 13, color: AppPalette.neutral),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Son güncelleme: ${TrFormat.dateTime(q.updatedAt)}'
                ' · ${q.source.label}'
                '${q.marketTime != null ? ' · Son işlem ${TrFormat.dateTime(q.marketTime!)}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.neutral),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Imlec **acikken** ust baslik: o mumun fiyati + tarihi.
  ///
  /// Kural: gecmis deger ile guncel deger asla karistirilmaz.
  ///  * Buyuk fiyat = imlecin durdugu **mumun kapanisi** (O ardindaki
  ///    tarih yazilir).
  ///  * Etiket "Gecmis mum" olur; "Canli"/"Gecikmeli" **yazilmaz**, cunku
  ///    bu mod anlik fiyati gostermez.
  ///  * Guncel fiyatin kendisi ayrica "Guncel: ..." satirinda durur.
  ///  * Mumun A/Y/D/K degerleri alttaki OHLC satirinda zaten ayni imlece
  ///    bagli gosterilir; burada tekrarlanmaz.
  Widget _headerPicked(
    BuildContext context,
    AssetDescriptor? asset,
    Quote q,
    Candle c,
  ) {
    final theme = Theme.of(context);
    final when = DateTime.fromMillisecondsSinceEpoch(c.time);
    final currency = q.currency ?? asset?.currency ?? '';
    final candlePct = c.open > 0 ? (c.close - c.open) / c.open * 100 : null;
    final livePrice = q.hasPrice ? TrFormat.price(q.price) : TrFormat.noData;

    // `Positioned.fill` ile canli icerigin boyutunu paylasir: buyuk fiyat
    // satiri canli moddaki ile AYNI Y'de kalir, satirlar dikeyde esit
    // yayilir (asagida bos luk kalmaz, kart dis gorunumu degismez).
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: PriceFlash(
                text: currency.isEmpty
                    ? TrFormat.price(c.close)
                    : '${TrFormat.price(c.close)} $currency',
                price: c.close,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (candlePct != null && candlePct.isFinite)
                  ChangeBadge(value: candlePct, percent: true, compact: false),
                const SizedBox(height: 2),
                Tooltip(
                  message: 'Grafikte imlecin durduğu mumun açılıştan '
                      'kapanışa değişimidir; güncel piyasa değişimi değildir.',
                  child: Text(
                    'Geçmiş mum',
                    maxLines: 1,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppPalette.neutral),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.history_rounded,
                size: 13, color: AppPalette.neutral),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${TrFormat.dateTime(when)} tarihli mum · ${q.source.label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.neutral),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            const Icon(Icons.refresh_rounded,
                size: 13, color: AppPalette.neutral),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                q.isStale
                    ? 'Son gerçek fiyat: $livePrice · Bağlantı yok'
                    : 'Güncel: $livePrice · ${q.freshness.label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.neutral),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, String label, double? value,
      {int decimals = 2}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: AppPalette.neutral, fontSize: 10.5),
        ),
        const SizedBox(height: 1),
        Text(
          value == null ? TrFormat.noData : TrFormat.money(value, decimals: decimals),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Zaman dilimi secici
// ---------------------------------------------------------------------------

class _IntervalBar extends StatelessWidget {
  const _IntervalBar({required this.selected, required this.onChanged});

  final ChartInterval selected;
  final ValueChanged<ChartInterval> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        itemCount: ChartInterval.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final iv = ChartInterval.values[i];
          final active = iv == selected;
          return ChoiceChip(
            label: Text(iv.label),
            selected: active,
            onSelected: (_) => onChanged(iv),
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teknik gorunum (Aşama 10)
// ---------------------------------------------------------------------------

class _TechnicalViewTab extends ConsumerWidget {
  const _TechnicalViewTab({
    required this.assetId,
    required this.interval,
    required this.quote,
  });

  final String assetId;
  final ChartInterval interval;
  final Quote? quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candlesAsync = ref.watch(assetCandlesProvider((assetId, interval)));

    return switch (candlesAsync) {
      AsyncLoading() =>
        const Center(child: CircularProgressIndicator()),
      AsyncError() => ErrorStateView(
          failure: const UnknownFailure('Grafik verisi alınamadı.'),
          onRetry: () =>
              ref.invalidate(assetCandlesProvider((assetId, interval))),
        ),
      AsyncData(:final value) => _Statements(
          statements: TechnicalViewEngine.build(
            candles: value.candles,
            interval: interval,
            quote: quote,
          ),
        ),
    };
  }
}

class _Statements extends StatelessWidget {
  const _Statements({required this.statements});

  final List<TechnicalStatement> statements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (statements.isEmpty) {
      return const EmptyStateView(
        message: 'Bu zaman dilimi için yeterli veri yok.',
        icon: Icons.insights_rounded,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.gold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.gold.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppPalette.goldDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bu ekran yalnızca hesaplanmış değerlerin nesnel '
                  'açıklamasını sunar. Yatırım tavsiyesi, al/sat önerisi '
                  'veya fiyat yönü tahmini içermez.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final s in statements) _statementTile(context, s),
      ],
    );
  }

  Widget _statementTile(BuildContext context, TechnicalStatement s) {
    final theme = Theme.of(context);
    final (icon, color) = switch (s.tone) {
      StatementTone.neutral => (Icons.remove_rounded, AppPalette.neutral),
      StatementTone.above => (Icons.arrow_upward_rounded, AppPalette.gain),
      StatementTone.below => (Icons.arrow_downward_rounded, AppPalette.loss),
      StatementTone.rising => (Icons.trending_up_rounded, AppPalette.gain),
      StatementTone.falling => (Icons.trending_down_rounded, AppPalette.loss),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baglanti kopmasi: son GERCEK veri gosterilir, ama "guncel degil"dir.
///
/// Fiyat **sifirlanmaz / uydurulmaz**; kullanici ne goruntulendigini ve ne
/// zamandir guncellenmedigini net gorur. Istemci kendiliginen yeniden
/// dener, ayrica elle "Tekrar Dene" sunulur.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.updatedAt});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.loss.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.loss.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 16, color: AppPalette.loss),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bağlantı yok — son bilinen gerçek fiyat gösteriliyor '
              '(son güncelleme ${TrFormat.dateTime(updatedAt)}). '
              'Yeniden bağlanılıyor.',
              style: theme.textTheme.labelSmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
