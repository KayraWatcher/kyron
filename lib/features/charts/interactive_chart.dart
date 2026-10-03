import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/candle.dart';
import 'chart_geometry.dart';
import 'chart_painter.dart';
import 'chart_types.dart';
import 'drawing.dart';
import 'indicator_engine.dart';

/// Grafik etkilesim durumu.
///
/// Zamanlayici/tanim disindaki tum degerler **mum indeksi ve fiyat**
/// uzerindedir; boylece zoom/pan'de cizimler mumlere kilitli kalir.
class ChartInteraction {
  const ChartInteraction({
    this.drawing,
    this.crosshair,
    this.crosshairIndex,
    this.crosshairPrice,
    this.activeTool = DrawingTool.none,
    this.showCrosshair = true,
  });

  final Drawing? drawing;
  final Offset? crosshair;
  final int? crosshairIndex;
  final double? crosshairPrice;
  final DrawingTool activeTool;
  final bool showCrosshair;

  static const ChartInteraction empty = ChartInteraction();

  /// Uzun basma bitti/iptal: capraz imlec kapanir **ve** secili mum/konum
  /// bilgisi temizlenir. Ust baslik aninda canli (guncel) fiyata doner.
  ///
  /// `copyWith(crosshairIndex: null)` bunu yapamaz (null "degistirme" olarak
  /// yorumlanir); bu yuzden acik bir fabrika metodu vardir.
  ChartInteraction released({DrawingTool? activeTool}) => ChartInteraction(
        drawing: drawing,
        crosshair: null,
        crosshairIndex: null,
        crosshairPrice: null,
        activeTool: activeTool ?? this.activeTool,
        showCrosshair: false,
      );

  /// Capraz imlec **acilir** (uzun basma / fare imleci grafik uzerinde).
  ///
  /// `released()` ve `copyWith(hideCrosshair: true)` imleci kapatabilir ama
  /// `copyWith` `showCrosshair` alanina **geri** `true` yazamaz (null =
  /// "degistirme" olarak yorumlanir). Bu yuzden acik bir fabrika metodu
  /// vardir: yoksa imlec bir kez kapandiktan sonra (`released()` ya da
  /// pan/tap ile) ekran yeniden kurulana kadar **bir daha acilmaz** -
  /// kullanici "grafik dokunmaya cevap vermiyor" olarak algilar.
  ChartInteraction engaged({
    required Offset crosshair,
    required int crosshairIndex,
    double? crosshairPrice,
    DrawingTool? activeTool,
  }) =>
      ChartInteraction(
        drawing: drawing,
        crosshair: crosshair,
        crosshairIndex: crosshairIndex,
        crosshairPrice: crosshairPrice,
        activeTool: activeTool ?? this.activeTool,
        showCrosshair: true,
      );

  ChartInteraction copyWith({
    Drawing? drawing,
    Offset? crosshair,
    int? crosshairIndex,
    double? crosshairPrice,
    DrawingTool? activeTool,
    bool? showCrosshair,
    bool hideCrosshair = false,
  }) {
    return ChartInteraction(
      drawing: drawing ?? this.drawing,
      crosshair: crosshair ?? this.crosshair,
      crosshairIndex: crosshairIndex ?? this.crosshairIndex,
      crosshairPrice: crosshairPrice ?? this.crosshairPrice,
      activeTool: activeTool ?? this.activeTool,
      showCrosshair: hideCrosshair ? false : (showCrosshair ?? this.showCrosshair),
    );
  }
}

/// Kullanicinin cizecegi nesnenin durumu.
class DraftDrawing {
  const DraftDrawing(this.type, this.points);

  final DrawingTool type;
  final List<DrawingPoint> points;

  Drawing? get asDrawing => points.isEmpty
      ? null
      : Drawing(
          id: 'draft_${DateTime.now().microsecondsSinceEpoch}',
          type: type,
          points: points,
        );
}

/// Ana grafik widget'i: zoom, pan, capraz imlec ve cizim araclarini yonetir.
class InteractiveChart extends StatefulWidget {
  const InteractiveChart({
    super.key,
    required this.candles,
    required this.chartType,
    this.overlays = const [],
    this.panels = const [],
    this.drawings = const [],
    this.interaction = ChartInteraction.empty,
    this.onInteractionChanged,
    this.onCrosshairRelease,
    this.onDrawingsChanged,
    this.priceFormatter,
    this.decimals,
    this.showToolbar = true,
    this.fitToData = false,
  });

  final List<Candle> candles;
  final ChartType chartType;
  final List<ComputedIndicator> overlays;
  final List<ChartPanel> panels;
  final List<Drawing> drawings;

  final ChartInteraction interaction;
  final ValueChanged<ChartInteraction>? onInteractionChanged;
  final ValueChanged<List<Drawing>>? onDrawingsChanged;
  final VoidCallback? onCrosshairRelease;

  final String Function(double)? priceFormatter;
  final int? decimals;
  final bool showToolbar;

  /// Disaridan gelen "tumu goster" komutu.
  final bool fitToData;

  @override
  State<InteractiveChart> createState() => _InteractiveChartState();
}

class _InteractiveChartState extends State<InteractiveChart> {
  late int _first;
  late int _visible;

  DraftDrawing? _draft;
  bool _autoFit = true;

  // Son gesiler
  double _baseVisible = 0;
  int _panFirst = 0;

  /// Son uretilen etkilesim (frame ici tazelik).
  ///
  /// Pointer event'leri frame'den hizli gelir (60-240 Hz);
  /// `widget.interaction` yalnizca **bir sonraki rebuild'de** guncellenir.
  /// Ayni frame icindeki ardisik event'ler `widget.interaction` uzerinden
  /// build ederse son yazan kazanir (lost-update): ornegin `_onScaleStart`
  /// imleci kapattiktan hemen sonraki `_onScaleUpdate` eski (acik) durumu
  /// geri yazabilir - bu da "imlec acik/kapali rastgele zipliyor" ve
  /// "hizli harekette imlec bir daha acilmiyor" semptomlarini uretir.
  /// Bu yuzden her uretim local olarak saklanir.
  ChartInteraction? _emitted;

  /// Bir sonraki event'in dayanacagi guncel etkilesim.
  ChartInteraction get _current => _emitted ?? widget.interaction;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(InteractiveChart old) {
    super.didUpdateWidget(old);
    // Ust agac etkilesimi disaridan degistirdiyse (aktivite araci secimi,
    // dilim degisimi, elle sifirlama) kaynak odur; kendi urettigimiz son
    // degerden farkliysa onu benimse.
    if (!identical(old.interaction, widget.interaction) &&
        !identical(_emitted, widget.interaction)) {
      _emitted = widget.interaction;
    }

    // Arac degisti/iptal edildi: yarim kalmis taslak artik o aracin
    // noktalarini tasiyordu. Taslak silinmezse bir sonraki tik **baska**
    // bir aracin noktalariyla birlestirilir (yanlis cizim uretilir).
    if (_draft != null && _draft!.type != _current.activeTool) {
      _draft = null;
    }

    if (old.candles != widget.candles ||
        old.chartType != widget.chartType ||
        (widget.fitToData && !old.fitToData)) {
      if (_autoFit || old.candles.isEmpty) _reset();
    }
  }

  void _reset() {
    final n = widget.candles.length;
    // Serideki mumlar (sinir kadar); pencere verinin disina cikmaz ->
    // sagda **uydurma bosluk** olusmaz, son mum sag kenara dayanir.
    _visible = ChartWindow.clampVisible(n, n);
    _first = ChartWindow.clampFirst(n - _visible, _visible, n);
    _autoFit = true;
  }

  int get _n => widget.candles.length;

  ChartViewport _buildViewport() {
    final visible = ChartWindow.clampVisible(_visible, _n);
    final first = ChartWindow.clampFirst(_first, visible, _n);
    final last = (first + visible).clamp(first + 1, _n).toInt();
    return ChartViewport.forRange(
      candles: widget.candles,
      first: first,
      lastExclusive: last,
    );
  }

  /// Etkilesimi ust agaca bildirir **ve** local kopyasini gunceller.
  void _emit(ChartInteraction i) {
    _emitted = i;
    widget.onInteractionChanged?.call(i);
  }

  // -------------------------------------------------------------------------
  // Zoom / pan
  // -------------------------------------------------------------------------

  void _zoom(double factor, {Offset? focal}) {
    if (_n == 0) return;
    setState(() {
      final current = ChartWindow.clampVisible(_visible, _n);
      final target = ChartWindow.zoomVisible(
        current: current,
        factor: factor,
        n: _n,
      );
      final center = focal?.dx;

      if (center != null && current > 0) {
        final ratio = center /
            math.max(1, context.size!.width - ChartPainter.priceAxisWidth);
        final anchor = _first + (ratio * current);
        _first = (anchor - ratio * target).round();
      } else {
        _first = _first + ((current - target) / 2).round();
      }

      _visible = target;
      // Pencere her zaman veri icinde: sagda bosluk kalmaz.
      _first = ChartWindow.clampFirst(_first, _visible, _n);
      _autoFit = false;
    });
  }

  void _panBy(double dx) {
    if (_n == 0) return;
    final width = context.size!.width - ChartPainter.priceAxisWidth;
    if (width <= 0) return;

    final next = ChartWindow.panFirst(
      first: _first,
      dx: dx,
      visible: _visible,
      n: _n,
      plotWidth: width,
    );
    if (next == _first) return;

    setState(() {
      _first = next;
      _autoFit = false;
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _baseVisible = _visible.toDouble();
    _panFirst = _first;
    // Kaydirma/yaklastirma baslarken imlec ve secili mum temizlenir.
    _releaseCrosshair();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2 && _baseVisible > 0) {
      // scale > 1 -> yakinlastir
      final target = ChartWindow.scaledVisible(
        base: _baseVisible.round(),
        scale: d.scale,
        n: _n,
      );
      setState(() {
        _visible = target;
        _first = ChartWindow.clampFirst(_panFirst, _visible, _n);
        _autoFit = false;
      });
      return;
    }

    // Tek parmak / tek tekerlek: yatay kaydirma (fare ve dokunmatik ayni).
    if (d.pointerCount == 1 && d.focalPointDelta.dx != 0) {
      _panBy(d.focalPointDelta.dx);
    }

    _updateCrosshair(d.localFocalPoint);
  }

  void _onScaleEnd(ScaleEndDetails d) {}

  void _onLongPressStart(LongPressStartDetails d) {
    _updateCrosshair(d.localPosition, engage: true);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    _updateCrosshair(d.localPosition, silent: true);
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    _releaseCrosshair();
  }

  void _onLongPressCancel() {
    _releaseCrosshair();
  }

  /// Uzun basma bitti/iptal: capraz imlec kapanir ve **secili mum
  /// temizlenir** ki ust baslik aninda canli (guncel) fiyata donsun.
  void _releaseCrosshair() {
    _emit(_current.released());
    widget.onCrosshairRelease?.call();
  }

  void _onHover(PointerHoverEvent e) {
    if (_current.activeTool != DrawingTool.none) return;
    // Fare imleci de imleci acmak zorunda: `released()`/tap sonrasinda
    // imlecin sonsuza dek kapali kalmasin.
    _updateCrosshair(e.localPosition, silent: true, engage: true);
  }

  /// Fare grafik alanindan **cikti**: imlec ekranda kalmaz, ust baslik
  /// canli (guncel) fiyata doner. Dokunmatik cihazlarda tetiklenmez.
  void _onHoverExit(PointerExitEvent e) {
    if (_current.activeTool != DrawingTool.none) return;
    if (!_current.showCrosshair) return;
    _releaseCrosshair();
  }

  /// Imlec konumunu hesaplar ve ust agaca bildirir.
  ///
  /// [engage] `true` iken imlec **acik** olur (uzun basma baslangici);
  /// `false` iken mevcut `showCrosshair` korunur (pan sirasinda imlec
  /// kapali kalmaya devam eder).
  void _updateCrosshair(
    Offset pos, {
    bool silent = false,
    bool engage = false,
  }) {
    final vp = _buildViewport();
    final width = context.size!.width - ChartPainter.priceAxisWidth;
    if (width <= 0) return;

    final idx = vp.first +
        ((pos.dx / width) * vp.length).floor().clamp(0, math.max(0, vp.length - 1)).toInt();

    final plotHeight = _plotHeight;
    if (plotHeight <= 0) return;
    final price = pos.dy <= plotHeight ? vp.priceMin +
        (1 - pos.dy / plotHeight) * (vp.priceMax - vp.priceMin) : null;

    final next = engage
        ? _current.engaged(
            crosshair: pos,
            crosshairIndex: idx,
            crosshairPrice: price,
          )
        : _current.copyWith(
            crosshair: pos,
            crosshairIndex: idx,
            crosshairPrice: price,
          );

    if (silent) {
      _emit(next);
      return;
    }

    setState(() => _emit(next));
  }

  double get _plotHeight {
    final totalPanelH = widget.panels.isEmpty
        ? 0.0
        : widget.panels.length * (ChartPainter.panelHeight + ChartPainter.panelGap);
    final size = context.size;
    if (size == null) return 0;
    return size.height - ChartPainter.timeAxisHeight - totalPanelH;
  }

  // -------------------------------------------------------------------------
  // Cizim araclari
  // -------------------------------------------------------------------------

  DrawingPoint _toPoint(Offset pos) {
    final vp = _buildViewport();
    final width = context.size!.width - ChartPainter.priceAxisWidth;
    final plotH = _plotHeight;
    final idx = vp.first +
        ((pos.dx / width) * vp.length).floor().clamp(0, math.max(0, vp.length - 1)).toInt();
    final price = plotH <= 0
        ? vp.priceMin
        : vp.priceMin + (1 - pos.dy / plotH) * (vp.priceMax - vp.priceMin);
    return DrawingPoint(idx, price);
  }

  void _onTapUp(TapUpDetails d) {
    final tool = _current.activeTool;
    if (tool == DrawingTool.none) {
      if (_current.showCrosshair) {
        // Dokunma ile kapatma da secili mumu temizler (canli moda doner).
        _emit(_current.released());
        widget.onCrosshairRelease?.call();
      }
      return;
    }

    final point = _toPoint(d.localPosition);
    final draft = _draft;

    if (draft == null) {
      setState(() => _draft = DraftDrawing(tool, [point]));
      return;
    }

    final next = [...draft.points, point];
    final needed = requiredPointsFor(tool);
    if (next.length >= needed) {
      final drawing = DraftDrawing(tool, next).asDrawing;
      setState(() => _draft = null);
      if (drawing != null) {
        widget.onDrawingsChanged?.call([...widget.drawings, drawing]);
      }
      _emit(_current.copyWith(
        activeTool: DrawingTool.none,
        hideCrosshair: true,
      ));
      HapticFeedback.lightImpact();
    } else {
      setState(() => _draft = DraftDrawing(tool, next));
    }
  }

  void clearAllDrawings() {
    setState(() => _draft = null);
    widget.onDrawingsChanged?.call(const []);
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.fromTheme(theme);

    if (widget.candles.isEmpty) {
      return Center(
        child: Text(
          'Grafik verisi yok',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final vp = _buildViewport();
    final draftDrawing = _draft?.asDrawing;

    final data = ChartRenderData(
      candles: widget.candles,
      viewport: vp,
      chartType: widget.chartType,
      overlays: widget.overlays,
      panels: widget.panels,
      drawings: widget.drawings,
      incompleteDrawing: draftDrawing,
      crosshair: _current.showCrosshair
          ? _current.crosshair
          : null,
      crosshairIndex: _current.showCrosshair
          ? _current.crosshairIndex
          : null,
      crosshairPrice: _current.showCrosshair
          ? _current.crosshairPrice
          : null,
      decimals: widget.decimals,
      priceFormatter: widget.priceFormatter,
      colors: colors,
    );

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _zoom(event.scrollDelta.dy > 0 ? 1.15 : 1 / 1.15,
              focal: event.position);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMove,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: _onLongPressCancel,
        onDoubleTap: () => setState(_reset),
        child: MouseRegion(
          onHover: _onHover,
          onExit: _onHoverExit,
          cursor: _current.activeTool == DrawingTool.none
              ? SystemMouseCursors.basic
              : SystemMouseCursors.precise,
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: ChartPainter(data),
                ),
              ),
              if (widget.showToolbar)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _ZoomControls(
                    onZoomIn: () => _zoom(1 / 1.25),
                    onZoomOut: () => _zoom(1.25),
                    onFit: () => setState(_reset),
                    onClear: widget.drawings.isEmpty
                        ? null
                        : clearAllDrawings,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onClear,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(context, Icons.add_rounded, onZoomIn),
          _divider(theme),
          _btn(context, Icons.remove_rounded, onZoomOut),
          _divider(theme),
          _btn(context, Icons.fit_screen_rounded, onFit),
          if (onClear != null) ...[
            _divider(theme),
            _btn(context, Icons.delete_sweep_rounded, onClear!),
          ],
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) => Divider(
        height: 1,
        thickness: 1,
        color: theme.dividerTheme.color ?? Colors.grey,
      );

  Widget _btn(BuildContext context, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
