import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/price_alert.dart';

/// Alarm listesinin yerel depolamasi (JSON).
///
/// **Kural:** Bozuk/eksik kayitlar sessizce atlanir; hatali veriyle
/// karsilasilirsa alarm listesi **bosluk** yerine `null` doner ve arayuz
/// "veri yok" durumunu gosterir.
abstract final class AlertStore {
  static const String key = 'alerts.list';

  /// Alarm listesini okur. Depolama erisilemezse `null` (bilinmiyor).
  static List<PriceAlert>? read(SharedPreferences? prefs) {
    if (prefs == null) return null;
    try {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <PriceAlert>[];
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final a = PriceAlert.fromJson(e);
        if (a != null) out.add(a);
      }
      return out;
    } catch (_) {
      // Bozuk veri: uydurma listeye cevrilmez.
      return null;
    }
  }

  /// Alarm listesini yazar. Basarisizsa false.
  static Future<bool> write(
      SharedPreferences? prefs, List<PriceAlert> alerts) async {
    if (prefs == null) return false;
    try {
      await prefs.setString(key, jsonEncode([for (final a in alerts) a.toJson()]));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Gorulen haberler
  // ---------------------------------------------------------------------------

  /// Saklanan gorulen haber kimlikleri ust siniri.
  ///
  /// Akis surekli yenilenir; bellek/tercih siniri icin eski kimlikler
  /// dusulur. Dusme, o haberin yeniden bildirilmesine yol acmaz: haber
  /// akisindan da coktan cikmistir.
  static const int maxSeenNews = 200;

  static const String seenKey = 'alerts.seenNews';

  /// Gorulen haber kimliklerini okur (bozuk veri bos set doner).
  static Set<String> readSeenNews(SharedPreferences? prefs) {
    if (prefs == null) return <String>{};
    try {
      final raw = prefs.getString(seenKey);
      if (raw == null || raw.isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return <String>{for (final e in decoded) if (e is String) e};
    } catch (_) {
      return <String>{};
    }
  }

  /// Gorulen haber kimliklerini yazar (son [maxSeenNews] adet).
  static Future<bool> writeSeenNews(
      SharedPreferences? prefs, Set<String> ids) async {
    if (prefs == null) return false;
    try {
      final list = ids.toList();
      if (list.length > maxSeenNews) {
        // Set insertion-order korur: ilk girilenler en eskisidir.
        list.removeRange(0, list.length - maxSeenNews);
      }
      await prefs.setString(seenKey, jsonEncode(list));
      return true;
    } catch (_) {
      return false;
    }
  }
}
