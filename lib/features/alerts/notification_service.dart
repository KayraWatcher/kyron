import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Yerel bildirim servisi (Aşama 14).
///
/// **Neden yerel?** Uygulama hesap veya Firebase gerektirmez; tum bildirimler
/// cihaz uzerinde uretilir. Sunucu, anahtar veya ucretli servis yoktur.
abstract final class NotificationService {
  static const String _channelId = 'gold_fiyat_alarlari';
  static const String _channelName = 'Fiyat Alarmları';
  static const String _channelDescription =
      'Varlık fiyat, değişim oranı ve önemli haber alarmları';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Ilk kurulumu yapar. Hata firlatmaz - bildirimler opsiyoneldir.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      // Android odakli; baska platform ayari gecirilmez.
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (e) {
      debugPrint('Bildirim baslatilamadi: $e');
    }
  }

  /// Android 13+ icin bildirim izni ister.
  ///
  /// Basarisiz olursa uygulama calismaya devam eder; yalnizca bildirim
  /// gozukmez.
  static Future<bool> requestPermission() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Bildirim izni istenemedi: $e');
      return false;
    }
  }

  /// Bildirim izni su an verilmis mi?
  static Future<bool> permissionsGranted() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      final granted = await android.areNotificationsEnabled();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Bir bildirim gosterir.
  ///
  /// [id] aynıysa onceki bildirim uzerine yazilir; her alarm icin farkli
  /// kimlik kullanilir.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      await init();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Bildirim gosterilemedi: $e');
    }
  }

  /// Tum bildirimleri temizler.
  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Alarm kimliginden bildirim kimligi uretir (0..2^31 araliginda).
  static int idFor(String alertId) {
    // FNV-1a benzeri sabit; negatif/boyutlu sinirlari asmamasi icin modlenir.
    var h = 0x811c9dc5;
    for (final cu in alertId.codeUnits) {
      h ^= cu;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}
