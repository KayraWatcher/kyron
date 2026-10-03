import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/failures.dart';
import '../error/state_failure.dart';
import '../format/tr_format.dart';
import '../theme/app_theme.dart';

/// Veri durumu - her ekran bu dort durumu yonetir.
sealed class ViewState<T> {
  const ViewState();
  bool get isLoading => this is Loading<T>;
  bool get isError => this is Failed<T>;
  bool get isEmpty => this is Empty<T>;
  bool get isReady => this is Ready<T>;

  T? get dataOrNull => switch (this) {
        Ready<T>(:final data) => data,
        _ => null,
      };
}

final class Loading<T> extends ViewState<T> {
  const Loading({this.partial = false});

  /// Onceki veri gosterilirken arka planda yenileniyor.
  final bool partial;
}

final class Ready<T> extends ViewState<T> {
  const Ready(this.data, {this.isStale = false});

  final T data;

  /// Onbellekten/cevrimdisi geldi.
  final bool isStale;
}

final class Empty<T> extends ViewState<T> {
  const Empty([this.message = 'Gösterilecek veri bulunamadı.']);

  final String message;
}

final class Failed<T> extends ViewState<T> {
  const Failed(this.failure);

  final Failure failure;
}

/// Tekrar deneme tetikleyen ortak buton.
class RetryButton extends StatelessWidget {
  const RetryButton({
    super.key,
    required this.onPressed,
    this.label = 'Tekrar Dene',
    this.compact = false,
  });

  final VoidCallback onPressed;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size(160, 44)),
    );
  }
}

/// Hata durumu gosterimi. Kullaniciya Turkce aciklama + tekrar deneme.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.failure,
    required this.onRetry,
    this.compact = false,
  });

  final Failure failure;
  final VoidCallback onRetry;
  final bool compact;

  IconData get _icon => switch (failure) {
        NetworkFailure() || OfflineFailure() => Icons.wifi_off_rounded,
        TimeoutFailure() => Icons.timer_off_rounded,
        ServerFailure() => Icons.cloud_off_rounded,
        BadRequestFailure() => Icons.error_outline_rounded,
        ParseFailure() => Icons.broken_image_rounded,
        EmptyFailure() => Icons.inbox_rounded,
        UnknownFailure() => Icons.priority_high_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 32, color: AppPalette.neutral),
            const SizedBox(height: 8),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            RetryButton(onPressed: onRetry, compact: true),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.neutral.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, size: 36, color: AppPalette.neutral),
            ),
            const SizedBox(height: 16),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            RetryButton(onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Bos durum gosterimi.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    this.message = 'Gösterilecek veri bulunamadı.',
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppPalette.neutral),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Yukleniyor gosterimi.
class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// İskelet (skeleton) yukleme - veri bicimini tahmin edebildigimiz yerlerde.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.darkSurfaceAlt
        : AppPalette.lightSurfaceAlt;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(base, base.withValues(alpha: 0.45),
              _controller.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Cevrimdisi/son guncelleme etiketi.
class StaleBadge extends StatelessWidget {
  const StaleBadge({
    super.key,
    required this.updatedAt,
    this.isOffline,
    this.message,
  });

  final DateTime? updatedAt;
  final bool? isOffline;

  /// Elle yazilan metin (varsayilan aciklamalarin disinda).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = isOffline ?? false;
    final text = message ??
        (offline
            ? 'Çevrimdışı'
            : 'Son güncelleme: ${TrFormat.dateTimeSeconds(updatedAt)}');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          offline ? Icons.cloud_off_rounded : Icons.schedule_rounded,
          size: 12,
          color: AppPalette.neutral,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.neutral,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Genel hata/veri sarmalayici - `ViewState`a gore uygun gosterimi secer.
class StateView<T> extends StatelessWidget {
  const StateView({
    super.key,
    required this.state,
    required this.onRetry,
    required this.builder,
    this.emptyMessage,
    this.emptyIcon,
    this.compactError = false,
    this.child,
  });

  final ViewState<T> state;
  final VoidCallback onRetry;
  final Widget Function(T data) builder;
  final String? emptyMessage;
  final IconData? emptyIcon;
  final bool compactError;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return switch (s) {
      Loading<T>() => child ?? const LoadingStateView(),
      Failed<T>(:final failure) =>
        ErrorStateView(failure: failure, onRetry: onRetry, compact: compactError),
      Empty<T>(:final message) => EmptyStateView(
          message: emptyMessage ?? message,
          icon: emptyIcon ?? Icons.inbox_rounded,
        ),
      Ready<T>(:final data, :final isStale) => _ready(data, isStale),
    };
  }

  /// Hazir durum icerigi.
  ///
  /// Onceki surumde icerik her zaman `Column` icine sariliyordu. `Column`
  /// cocuklarina ana eksen yonunde sinirsiz (0..sonsuz) kisit verir; bu
  /// yuzden `ListView`/`CustomPaint` tabanli icerik yukseligi sinirlanamaz ve
  /// release modda sessizce hicbir sey cizilmez. Icerik dogrudan disari
  /// birakilir; boylece ustteki `Expanded` (veya baska sinirli bir kap)
  /// icerige tam sinirli kisit verir.
  Widget _ready(T data, bool isStale) {
    final content = builder(data);
    if (!isStale) return content;

    const badge = Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: StaleBadge(
        updatedAt: null,
        isOffline: true,
        message: 'Güncelleme başarısız — son bilinen veri',
      ),
    );

    // Sinirli olmayan baglamda `Expanded` kullanilamaz; icerik kendi
    // yukseligini belirler (or. dar bir diyalog icinde shrinkWrap liste).
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [badge, Expanded(child: content)],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [badge, content],
        );
      },
    );
  }
}

/// AsyncValue'yu ortak [ViewState] modeline cevirir.
///
/// Boylece tum ekranlar loading/error/empty/offline gosterimini ayni
/// bilesenlerle paylasir. Veri yoksa [Loading]/[Failed] doner; **veri
/// varken yenileme veya gecici hata icerigi asla silmez**:
///
///  * ilk yukleme     -> [Loading]  (henuz veri yok)
///  * ilk hata        -> [Failed]   (Tekrar Dene)
///  * yenileme        -> onceki veri **ekranda kalir** (spinner'a donulmez;
///                       grafik/jest durumu yok olmaz)
///  * yenileme hatasi -> onceki veri `isStale` ile "son bilinen veri" olarak
///                       gosterilir
///  * bos icerik      -> [Empty] (hata ile karistirilmaz)
///
/// Boylece "arka planda sessiz yenileme" ekranin gorunumunu bozmaz;
/// hicbir yerde NaN/uydurma deger uretilmez.
ViewState<T> toViewState<T>(
  AsyncValue<T> value, {
  bool Function(T data)? isEmpty,
  bool isStale = false,
}) {
  final data = value.value;
  final failure = value.hasError ? StateFailure.from(value.error!) : null;

  // ---- Veri yok: durum bircok net ----
  if (data == null) {
    if (failure == null) return Loading<T>();
    // "Gosterilecek veri yok" bir hata degil, ayri bir durumdur
    // (orn. bos haber kategorisi) - kullaniciya "Tekrar Dene" gosterilmez.
    if (failure is EmptyFailure) return Empty<T>();
    return Failed<T>(failure);
  }

  final empty = isEmpty?.call(data) ?? false;

  // ---- Veri var: onceki deger korunur ----
  if (value.isLoading) {
    // Sessiz yenileme: icerik degismez, ekran spinner'a donmez.
    return empty ? Loading<T>() : Ready<T>(data, isStale: isStale);
  }
  if (failure != null) {
    if (empty && failure is EmptyFailure) return Empty<T>();
    // Gecici hata: son GERCEK veri "guncel degil" olarak gosterilir.
    return Ready<T>(data, isStale: true);
  }
  if (empty) return Empty<T>();
  return Ready<T>(data, isStale: isStale);
}
