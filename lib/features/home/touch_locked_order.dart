import 'package:flutter/widgets.dart';

/// Kullanici bir varliga **dokunurken / kaydirirken** listeyi yeniden
/// siralamaz.
///
/// Neden gerekli?
///  * Fiyatlar 30 saniyede bir tazelendigi icin "Fiyat" / "Degisim %" sirasi
///    periyodik olarak degisir.
///  * Kullanici bir karti basili tutarken kartlar yer degistirirse bastigi
///    kart baska bir varliga doner: yanlis detay acilir, kaydirma ziplar.
///
/// Davranis:
///  * Siralama istegi geldiginde parmak **kesilmisse** hemen uygulanir.
///  * Parmak **ekranda** ise yeni sira [pending] olarak saklanir ve parmak
///    kaldirildigi anda uygulanir. Boylece kullanici hicbir zaman bastigi
///    kartin yer degistirmesini gormez.
///  * Sadece parmak kaldirildiginda tek bir yeniden kurulum olur; diger
///    durumlarda (parent zaten yeniden kuruluyorsa) ek kurulum yapilmaz.
class TouchLockedOrder extends StatefulWidget {
  const TouchLockedOrder({
    super.key,
    required this.desired,
    required this.builder,
  });

  /// Istenen (yeni) sira.
  final List<String> desired;

  /// Aktif sira ile icerik ureten builder.
  final Widget Function(List<String> ids) builder;

  @override
  State<TouchLockedOrder> createState() => _TouchLockedOrderState();
}

class _TouchLockedOrderState extends State<TouchLockedOrder> {
  List<String> _shown = const <String>[];
  List<String>? _pending;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _shown = List<String>.of(widget.desired);
  }

  @override
  void didUpdateWidget(covariant TouchLockedOrder oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_same(oldWidget.desired, widget.desired)) return;

    if (_pointers > 0) {
      // Parmak ekranda: sira degisikligini ertele. setState CAGIRMA - bu
      // asamada zaten yeniden kurulum asamasindayiz.
      _pending = List<String>.of(widget.desired);
      return;
    }

    // Parmak yok: dogrudan uygula (build hemen sonra calisir).
    _shown = List<String>.of(widget.desired);
    _pending = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointers++;
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_pointers == 0) return;
    _pointers--;

    // Parmak kalkti: ertelenmis sira simdi uygulanabilir.
    if (_pointers == 0 && _pending != null && mounted) {
      final next = _pending!;
      setState(() {
        _shown = next;
        _pending = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: Builder(builder: (_) => widget.builder(_shown)),
    );
  }
}

/// Iki sira ayni mi? (Eleman sirasi dahil)
bool _same(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
