import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Piyasa durumu enum'u.
enum MarketStatus {
  open('Açık'),
  closed('Kapalı'),
  preMarket('Ön Seans'),
  postMarket('Kapanış Sonrası');

  const MarketStatus(this.label);

  final String label;
}

/// Borsa İstanbul işlem saatleri.
///
/// Hafta içi: 09:30 - 18:00 (Türkiye saati UTC+3)
/// Not: Yaz saati uygulaması değişebilir; sistem zamanına güvenilir.
class BistMarketHours {
  static const int openHour = 9;
  static const int openMinute = 30;
  static const int closeHour = 18;
  static const int closeMinute = 0;

  /// Verilen zaman diliminde BIST açık mı?
  static bool isOpen([DateTime? time]) {
    final now = time ?? DateTime.now();
    // Hafta sonu kontrolü
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }

    final open = DateTime(now.year, now.month, now.day, openHour, openMinute);
    final close = DateTime(now.year, now.month, now.day, closeHour, closeMinute);

    return now.isAfter(open) && now.isBefore(close);
  }

  /// Verilen zaman diliminde ön seans mı? (09:00-09:30)
  static bool isPreMarket([DateTime? time]) {
    final now = time ?? DateTime.now();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final preOpen = DateTime(now.year, now.month, now.day, 9, 0);
    final open = DateTime(now.year, now.month, now.day, openHour, openMinute);
    return now.isAfter(preOpen) && now.isBefore(open);
  }
}

/// Global piyasa durumu (BIST, Forex, Metaller).
class MarketStatusData {
  const MarketStatusData({
    required this.bistStatus,
    required this.forexStatus,
    required this.metalsStatus,
    this.lastUpdated,
  });

  final MarketStatus bistStatus;
  final MarketStatus forexStatus;
  final MarketStatus metalsStatus;
  final DateTime? lastUpdated;

  String get overallLabel {
    final statuses = [bistStatus, forexStatus, metalsStatus];
    if (statuses.every((s) => s == MarketStatus.open)) return 'Tüm piyasalar açık';
    if (statuses.every((s) => s == MarketStatus.closed)) return 'Tüm piyasalar kapalı';
    final openCount = statuses.where((s) => s == MarketStatus.open).length;
    return '$openCount piyasa açık';
  }

  bool get anyOpen => bistStatus == MarketStatus.open ||
      forexStatus == MarketStatus.open ||
      metalsStatus == MarketStatus.open;
}

/// Piyasa durumu provider'ı.
/// Sistem saati kullanır; fake timer yok.
final marketStatusProvider = StreamProvider<MarketStatusData>((ref) {
  final controller = StreamController<MarketStatusData>();

  // İlk değer hemen gönder
  controller.add(computeMarketStatus());

  // Periyodik güncelleme timer'ı
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    if (!controller.isClosed) {
      controller.add(computeMarketStatus());
    }
  });

  // Cleanup: stream iptal edildiğinde timer'ı durdur
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

MarketStatusData computeMarketStatus() {
  final now = DateTime.now();

  // BIST
  MarketStatus bistStatus;
  if (BistMarketHours.isOpen(now)) {
    bistStatus = MarketStatus.open;
  } else if (BistMarketHours.isPreMarket(now)) {
    bistStatus = MarketStatus.preMarket;
  } else {
    bistStatus = MarketStatus.closed;
  }

  // Forex (5/24 - Cuma 18:00 - Pazar 18:00 Türkiye saati kapalı)
  // Basit yaklaşım: Hafta içi her zaman açık kabul et
  MarketStatus forexStatus;
  if (now.weekday == DateTime.saturday ||
      (now.weekday == DateTime.friday && now.hour >= 18) ||
      (now.weekday == DateTime.sunday && now.hour < 18)) {
    forexStatus = MarketStatus.closed;
  } else {
    forexStatus = MarketStatus.open;
  }

  // Metaller (Forex ile benzer - COMEX/Globe)
  final metalsStatus = forexStatus;

  return MarketStatusData(
    bistStatus: bistStatus,
    forexStatus: forexStatus,
    metalsStatus: metalsStatus,
    lastUpdated: now,
  );
}