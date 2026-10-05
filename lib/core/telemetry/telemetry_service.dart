import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'telemetry_config.dart';

/// Anonim kurulum telemetrisi servisi (FAZ 6).
///
/// Sorumluluklari:
///  * [initialize]  : anonim installation id uret/sakla + uygulama versiyonunu oku.
///  * [trackAppOpen]     : uygulama acilisinda `app_open` / `app_update` ping'i.
///  * [trackAppUpdate]   : versiyon degisikliginde `app_update` ping'i.
///  * [updateLastSeen]   : olaysiz `last_seen_at` guncellemesi.
///  * [trackUpdateCheck] : update kontrol sonucu.
///  * [trackUpdateAvailable] : guncelleme mevcut.
///  * [trackForcedUpdateShown] : zorunlu guncelleme ekrani gosterildi.
///  * [trackUpdateDownloadClicked] : guncelleme butonuna tiklandi.
///
/// Kurallar:
///  * **UI asla beklemez** : butun ag cagrilari kisa timeout'lu ve
///    `try/catch` icindedir; hata firlatmaz, uygulamayi yonetmez.
///  * **Supabase yalnizca RPC** : `POST /rest/v1/rpc/telemetry_ping`.
///    Tablolara dogrudan INSERT/SELECT yapilmaz (bkz.
///    `supabase/migrations/*_telemetry.sql`); anon anahtar ile okuma
///    RLS tarafindan tamamen kapali.
///  * **Spam onleme (FAZ 7)** : `app_open` en az [appOpenCooldown] arayla,
///    olaysiz ping'ler en az [quietPingInterval] arayla gonderilir.
///  * **Gizlilik (FAZ 13)** : yalnizca anonim uuid + platform + versiyon +
///    zaman damgasi. Ip/reklam id/kisisel veri yok.
///
/// Yapilandirma yoksa ([TelemetryConfig.enabled] == false) her yontem
/// aninda doner; hicbir sey yazmaz/ag cagirmaz.
class TelemetryService {
  TelemetryService({
    required this.prefs,
    http.Client? client,
    String? url,
    String? anonKey,
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        url = url ?? TelemetryConfig.supabaseUrl,
        anonKey = anonKey ?? TelemetryConfig.supabaseAnonKey,
        _now = now ?? DateTime.now;

  // --- prefs anahtarlari (mevcut dot-namespaced konvansiyon) ---
  static const String installationIdKey = 'telemetry.installation_id';
  static const String lastOpenEventMsKey = 'telemetry.last_open_event_ms';
  static const String lastPingMsKey = 'telemetry.last_ping_ms';
  static const String lastVersionKey = 'telemetry.last_version';

  /// `app_open` olayi bu araliktan kisa surede tekrarlanmaz.
  static const Duration appOpenCooldown = Duration(minutes: 30);

  /// Olaysiz (yalnizca last_seen) ping'ler bu araliktan kisa tekrarlanmaz.
  static const Duration quietPingInterval = Duration(minutes: 5);

  /// Ag cok kisa surede doner; telemetry uygulamayi asla bekletemez.
  static const Duration requestTimeout = Duration(seconds: 8);

  final SharedPreferences prefs;
  final http.Client _client;
  final DateTime Function() _now;

  /// Supabase proje URL'si (anonim istemci icin; service-role DEGIL).
  final String url;

  /// Supabase anon (publishable) anahtari.
  final String anonKey;

  String? _installationId;
  String? _appVersion;
  bool _initialized = false;

  /// Telemetri acik mi? (iki `--dart-define` de verilmis olmali.)
  bool get enabled => url.isNotEmpty && anonKey.isNotEmpty;

  /// Anonim kurulum kimligi ([initialize] sonrasi). Bu bir insan kimligi
  /// DEGILDIR; uygulama silinip kurulursa yenisi uretilir.
  String? get installationId => _installationId;

  /// `1.0.0+1` biciminde pubspec versiyonu (okunamazsa `unknown`).
  String get appVersion => _appVersion ?? 'unknown';

  /// Platform etiketi: `android` / `ios` / `web` / `other` (FAZ 11).
  String get platform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'other';
    }
  }

  /// Kimlik + versiyon hazirligi. Agrag cagirmaz; hicbir hata firlatmaz.
  Future<void> initialize() async {
    if (!enabled || _initialized) return;
    try {
      var id = prefs.getString(installationIdKey);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(installationIdKey, id);
      }
      _installationId = id;

      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.buildNumber.isEmpty
            ? info.version
            : '${info.version}+${info.buildNumber}';
      } catch (_) {
        _appVersion = 'unknown';
      }
      _initialized = true;
    } catch (_) {
      // Kimlik okulanamadi: telemetri bu oturumda pasif; uygulama etkilenmez.
    }
  }

  /// Uygulama acildiginda cagrilir (AppLifecycleBinder).
  ///
  /// * Versiyon degistiyse -> `app_update`
  /// * Soguk acilis (cooldown gectiyse) -> `app_open`
  /// * Iksi de degilse -> olaysiz last_seen ping'i (throttle'li)
  Future<void> trackAppOpen() async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;

      final nowMs = _now().millisecondsSinceEpoch;
      String? event;

      final storedVersion = prefs.getString(lastVersionKey);
      if (storedVersion != null && storedVersion != _appVersion) {
        event = 'app_update';
      } else {
        final lastOpen = prefs.getInt(lastOpenEventMsKey) ?? 0;
        if (nowMs - lastOpen >= appOpenCooldown.inMilliseconds) {
          event = 'app_open';
        }
      }

      if (event == null) {
        // Olaysiz ping throttle'i: sik acilis/kapanislarda spam yok.
        final lastPing = prefs.getInt(lastPingMsKey) ?? 0;
        if (nowMs - lastPing < quietPingInterval.inMilliseconds) return;
      }

      final sent = await _sendPing(event: event);
      if (sent) {
        // Basarili gonderimden sonra yerel sayaclari guncelle; hata olursa
        // sonraki aciliste tekrar denenir (olay kaybolmaz).
        await prefs.setString(lastVersionKey, _appVersion ?? 'unknown');
        await prefs.setInt(lastPingMsKey, nowMs);
        if (event != null) {
          await prefs.setInt(lastOpenEventMsKey, nowMs);
        }
      }
    } catch (_) {
      // Telemetri hatasi uygulamayi asla etkilemez.
    }
  }

  /// Versiyon degisikliginde dogrudan `app_update` gonderir.
  Future<void> trackAppUpdate() async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;
      if (await _sendPing(event: 'app_update')) {
        await prefs.setString(lastVersionKey, _appVersion ?? 'unknown');
        await prefs.setInt(
          lastPingMsKey,
          _now().millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      // yut
    }
  }

  /// Olaysiz `last_seen_at` guncellemesi (throttle'li).
  Future<void> updateLastSeen() async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;
      final nowMs = _now().millisecondsSinceEpoch;
      final lastPing = prefs.getInt(lastPingMsKey) ?? 0;
      if (nowMs - lastPing < quietPingInterval.inMilliseconds) return;
      if (await _sendPing(event: null)) {
        await prefs.setInt(lastPingMsKey, nowMs);
      }
    } catch (_) {
      // yut
    }
  }

  // --- Update check telemetry (FAZ 17) ---

  /// Update kontrolu gerceklesti.
  Future<void> trackUpdateCheck({required String status}) async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;
      await _sendPing(event: 'update_check', extra: {'status': status});
    } catch (_) {
      // yut
    }
  }

  /// Guncelleme mevcut (opsiyonel veya zorunlu).
  Future<void> trackUpdateAvailable({required bool forced}) async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;
      await _sendPing(event: 'update_available', extra: {'forced': forced});
    } catch (_) {
      // yut
    }
  }

  /// Zorunlu guncelleme ekrani gosterildi.
  Future<void> trackForcedUpdateShown() async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;
      await _sendPing(event: 'forced_update_shown');
    } catch (_) {
      // yut
    }
  }

  /// Guncelleme indirme butonuna tiklandi.
  Future<void> trackUpdateDownloadClicked({required bool forced}) async {
    if (!enabled) return;
    try {
      await initialize();
      if (_installationId == null) return;
      await _sendPing(event: 'update_download_clicked', extra: {'forced': forced});
    } catch (_) {
      // yut
    }
  }

  /// Tek istek: Supabase RPC `telemetry_ping`. Asla hata firlatmaz.
  Future<bool> _sendPing({String? event, Map<String, dynamic>? extra}) async {
    final id = _installationId;
    if (id == null) return false;
    try {
      final body = <String, dynamic>{
        'p_installation_id': id,
        'p_platform': platform,
        'p_app_version': appVersion,
      };
      if (event != null) body['p_event'] = event;
      if (extra != null) body['p_extra'] = extra;
      final uri = Uri.parse('$url/rest/v1/rpc/telemetry_ping');
      final response = await _client
          .post(
            uri,
            headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $anonKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // Offline / timeout / 5xx: sessizce basarisiz; telemetri sonraki
      // aciliste tekrar dener. Kuyruk kurulmaz (FAZ 6: basit tut).
      return false;
    }
  }

  /// HTTP istemcisini kapat (provider dispose).
  void dispose() {
    try {
      _client.close();
    } catch (_) {
      // yut
    }
  }
}