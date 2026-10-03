import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Fiyat degistiginde kisa bir **renk hareketi** gosteren metin.
///
/// Kurallar:
///  * Yalnizca **iki gercek fiyat** karsilastirilir; hicbir deger
///    uydurulmaz / rastgele uretilmez.
///  * Fiyat ayni kaldiysa renk **hic degismez**.
///  * Renk hareketi tamamen gorseldir: sayi her zaman dogru formatta
///    (provider'dan gelen deger) yazilir.
///  * Sayinin kendisi asla animasyonla kaydirilmaz/olceklenmez; yalnizca
///    renk yumusakca yeşil/kırmızıya gidip geri doner.
class PriceFlash extends StatefulWidget {
  const PriceFlash({
    super.key,
    required this.text,
    required this.price,
    required this.style,
  });

  /// Ekranda yazilacak metin (provider'in formatladigi hali).
  final String text;

  /// Yonu belirleyen gercek fiyat. `null` ise hareket yapilmaz.
  final double? price;

  final TextStyle? style;

  @override
  State<PriceFlash> createState() => _PriceFlashState();
}

class _PriceFlashState extends State<PriceFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  double? _lastPrice;
  bool _up = true;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    _lastPrice = widget.price;
    // Animasyon kapanissa renk sifirlanir (yanlis renkte kalmasin).
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PriceFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.price;
    final prev = _lastPrice;

    final changed = next != null &&
        prev != null &&
        next.isFinite &&
        prev.isFinite &&
        next != prev;

    if (changed) {
      _up = next > prev;
      _controller.forward(from: 0);
      _fallback?.cancel();
      _fallback = Timer(const Duration(milliseconds: 950), () {
        if (mounted) setState(() {});
      });
    }

    _lastPrice = next;
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.style?.color ?? Theme.of(context).textTheme.bodyMedium?.color;
    final flashColor = _up ? AppPalette.gain : AppPalette.loss;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Hizli giris (ilk %25) + yavas donus: klasik "flash" efekti.
        final k = t <= 0
            ? 0.0
            : t < 0.25
                ? t / 0.25
                : 1 - (t - 0.25) / 0.75;
        final color = baseColor == null
            ? flashColor
            : Color.lerp(baseColor, flashColor, k.clamp(0.0, 1.0));

        return Text(
          widget.text,
          style: widget.style?.copyWith(color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
