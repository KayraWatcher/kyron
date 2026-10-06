import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'canlidoviz_protocol.dart';

/// CanlıDöviz anlık fiyat akışının **bağlantı katmanı**.
///
/// Protokol detayı, kare isimleri ve fiyat kaydı biçimi
/// [CanlidovizProtocol] içinde kanıtlanmıştır; bu sınıf yalnızca
/// bağlantı yaşam döngüsünü yönetir:
///
///  * `start()` -> handshake (`0{...}`) -> `40` -> abonelik (`us`) -> tick
///  * Engine.IO ping'e `3` (pong) ile cevap
///  * Kopmada / 25 sn ping gelmediğinde üstel beklemeyle yeniden bağlanma
///
/// Arayüz **test edilebilirlik** içindir: provider bu soyutlamayı alır,
/// testler sahtesini geçirir ve hiçbir test gerçek ağa çıkmaz.
abstract interface class CanlidovizPriceStream {
  /// Bağlantıyı başlat (idempotent). Çağrılmazsa akış **hiç başlamaz**
  /// ve provider fiyat vermez (fallback zinciri çalışır).
  void start();

  /// Bağlantıyı ve yeniden deneme zamanlayıcılarını kapat.
  void stop();

  /// İlk bağlantı denemesi (veya handshake/abonelik) sürüyor mu?
  ///
  /// Provider bu durumda kısa güncelleme aralığı kullanır ki uygulama
  /// açılışında akış bağlanana kadar kısa olsun, bağlantı tamamlanınca
  /// doğrudan tikler okunmaya başlansın.
  bool get isConnecting;

  /// Abonelik tamamlandı ve bağlantı açık mı?
  bool get isConnected;

  /// cid için en son gelen tik (yoksa `null`). Tazelik kontrolü provider'da.
  CanlidovizTick? latest(int cid);
}

class WsCanlidovizPriceStream implements CanlidovizPriceStream {
  WsCanlidovizPriceStream({
    required List<String> codes,
    List<String> topics = const <String>[],
  })  : _codes = List<String>.unmodifiable(codes),
        _topics = List<String>.unmodifiable(topics);

  /// Bağlantı (TCP+TLS+handshake) üst sınırı; aşarsa yeniden denenir.
  static const Duration connectTimeout = Duration(seconds: 10);

  /// Sunucu ping aralığı 25 sn; bu sürenin +15 sn fazlası sessizlik sayılır
  /// ve bağlantı yenilenir (ölü soket asla sonsuza dek tutulmaz).
  static const Duration pingGrace = Duration(seconds: 15);

  static const Duration minBackoff = Duration(seconds: 1);
  static const Duration maxBackoff = Duration(seconds: 30);

  final List<String> _codes;

  /// `t` topic alani (site istemcisi ile ayni mekanizma; orn. `GOLD`).
  final List<String> _topics;
  final Map<int, CanlidovizTick> _latest = <int, CanlidovizTick>{};

  _StreamState _state = _StreamState.idle;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  Duration _pingInterval = const Duration(seconds: 25);
  var _attempt = 0;
  var _subscribed = false;
  var _stopped = false;

  /// Aktif bağlantı denemesinin sırası (zaman aşımına uğrayan/eski
  /// denemelerin geç gelen socket'leri kapatılması için).
  var _connectSeq = 0;

  /// Bağlantı zaman aşımı **kendi** zamanlayıcımız.
  ///
  /// `Future.timeout` yerine bilinçli kullanılıyor: iptal edilebilir, böylece
  /// `stop()` çağrıldığında (widget testi sonu / uygulama kapanışı) bekleyen
  /// zamanlayıcı kalmaz.
  Timer? _connectGuard;

  @override
  bool get isConnecting =>
      _state == _StreamState.connecting ||
      (_state == _StreamState.connected && !_subscribed);

  @override
  bool get isConnected =>
      _state == _StreamState.connected && _subscribed && _socket != null;

  @override
  CanlidovizTick? latest(int cid) => _latest[cid];

  @override
  void start() {
    if (_stopped || _state != _StreamState.idle) return;
    unawaited(_connect());
  }

  @override
  void stop() {
    _stopped = true;
    _connectSeq++; // bekleyen deneme gecersizlesir
    _connectGuard?.cancel();
    _connectGuard = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    _subscription?.cancel();
    _subscription = null;
    final ws = _socket;
    _socket = null;
    _subscribed = false;
    _state = _StreamState.idle;
    try {
      unawaited(ws?.close());
    } catch (_) {
      // Kapatma hatası yok sayılır; zaten kapanıyor.
    }
  }

  Future<void> _connect() async {
    _state = _StreamState.connecting;
    final seq = ++_connectSeq;

    // Zaman aşımı kendi zamanlayıcımız: `stop()` ile iptal edilebilir
    // (widget testi sonu / uygulama kapanışında bekleyen Timer bırakmaz).
    _connectGuard?.cancel();
    _connectGuard = Timer(connectTimeout, () => _onConnectTimeout(seq));

    WebSocket ws;
    try {
      ws = await WebSocket.connect(CanlidovizProtocol.wsUrl);
    } catch (_) {
      _cancelConnectGuard();
      if (_stopped) {
        _state = _StreamState.idle;
        return;
      }
      // Ag/TLS/handshake hatasi -> ustel beklemeyle yeniden dene.
      _scheduleReconnect();
      return;
    }

    _cancelConnectGuard();

    if (_stopped || seq != _connectSeq) {
      // Iptal edilmis / zaman asimina ugratilmis deneme: gec socket
      // acilmaz, kapatilir.
      try {
        unawaited(ws.close());
      } catch (_) {}
      if (_stopped) _state = _StreamState.idle;
      return;
    }

    _socket = ws;
    _subscribed = false;
    _state = _StreamState.connected;
    _armWatchdog();

    _subscription = ws.listen(
      (dynamic data) {
        if (!identical(_socket, ws)) return; // eski baglantidan gec kare
        _onFrame(data);
      },
      onError: (Object _) {
        if (!identical(_socket, ws)) return;
        _teardown(ws);
      },
      onDone: () {
        if (!identical(_socket, ws)) return;
        _teardown(ws);
      },
      cancelOnError: false,
    );
  }

  void _onFrame(dynamic data) {
    final frame = data is String
        ? data
        : data is List<int>
            ? utf8.decode(data, allowMalformed: true)
            : null;
    if (frame == null) return;

    _armWatchdog();

    // 1) El sıkışma -> ping aralığını oku, namespace'e bağlan.
    if (CanlidovizProtocol.isHandshake(frame)) {
      _pingInterval =
          CanlidovizProtocol.handshakePingInterval(frame) ?? _pingInterval;
      _send(CanlidovizProtocol.namespaceConnect);
      return;
    }

    // 2) Engine.IO ping -> pong.
    if (CanlidovizProtocol.isPing(frame)) {
      _send(CanlidovizProtocol.enginePong);
      return;
    }

    // 3) Namespace onayı -> abonelik gonder.
    if (CanlidovizProtocol.isNamespaceAck(frame)) {
      _subscribed = true;
      _attempt = 0;
      _send(CanlidovizProtocol.subscriptionFrame(_codes, topics: _topics));
      return;
    }

    // 4) Fiyat yayini -> tikleri sakla (son gelen kazanir).
    if (CanlidovizProtocol.isPriceFrame(frame)) {
      final receivedAt = DateTime.now();
      for (final tick
          in CanlidovizProtocol.parsePriceFrame(frame, receivedAt: receivedAt)) {
        _latest[tick.cid] = tick;
      }
      return;
    }

    // Diger kareler (ack/uyari) P0/P1 kapsaminda kullanilmaz.
  }

  void _send(String frame) {
    final ws = _socket;
    if (ws == null || ws.readyState != WebSocket.open) return;
    try {
      ws.add(frame);
    } catch (_) {
      // Gonderim hatasi: soket zaten kopmustur; onDone/yeniden baglanma devreye girer.
    }
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_pingInterval + pingGrace, _onSilent);
  }

  /// Ping gelmedi (ölü bağlantı): kapat ve yeniden bağlan.
  void _onSilent() {
    final ws = _socket;
    if (ws == null) return;
    try {
      unawaited(ws.close());
    } catch (_) {}
    _teardown(ws);
  }

  void _teardown(WebSocket ws) {
    if (!identical(_socket, ws)) return;
    _socket = null;
    _subscription?.cancel();
    _subscription = null;
    _subscribed = false;
    _watchdog?.cancel();
    _watchdog = null;
    if (_stopped) {
      _state = _StreamState.idle;
      return;
    }
    _scheduleReconnect();
  }

  /// Bağlantı zaman aşımı: bu deneme geçersiz sayılır ve yeniden denenir.
  void _onConnectTimeout(int seq) {
    if (_stopped || seq != _connectSeq) return;
    _connectSeq++; // bekleyen `WebSocket.connect` geç gelirse kapatılır
    _scheduleReconnect();
  }

  void _cancelConnectGuard() {
    _connectGuard?.cancel();
    _connectGuard = null;
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _state = _StreamState.backoff;
    _reconnectTimer?.cancel();
    var delay = minBackoff * (1 << (_attempt > 5 ? 5 : _attempt));
    if (delay > maxBackoff) delay = maxBackoff;
    if (_attempt < 6) _attempt++;
    _reconnectTimer = Timer(delay, () {
      if (_stopped) return;
      unawaited(_connect());
    });
  }
}

enum _StreamState { idle, connecting, connected, backoff }
