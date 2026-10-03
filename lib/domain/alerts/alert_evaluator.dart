import '../entities/news_item.dart';
import '../entities/price_alert.dart';
import '../entities/quote.dart';

/// Bir alarmin degerlendirme sonucu.
class AlertEvaluation {
  const AlertEvaluation({required this.fire, required this.message});

  /// Bildirim gonderilmeli mi?
  final bool fire;

  /// Bildirim govdesi. `fire == false` iken bos kalir.
  final String message;

  static const AlertEvaluation skip = AlertEvaluation(fire: false, message: '');
}

/// Alarm kosullarinin **saf** degerlendiricisi.
///
/// Network, bildirim veya durum yoktur; yalnizca verilen [Quote] / haber
/// uzerinde hesap yapar. Boylece birebir unit test yazilabilir.
///
/// **Kural:** `null` / `NaN` fiyatlarla asla karar verilmez - deger yoksa
/// alarm **degerlendirilmez** (`fire == false`).
abstract final class AlertEvaluator {
  /// Kosul su anda sagliyor mu? (tetiklenmis/alarm durumundan bagimsiz)
  static bool conditionMet(PriceAlert alert, Quote? quote) {
    if (!alert.isArmed || quote == null) return false;
    if (alert.type == AlertType.importantNews) return false;

    final price = quote.hasPrice ? quote.price : null;
    final pct = quote.effectiveChangePercent;

    switch (alert.type) {
      case AlertType.priceAbove:
        final t = alert.threshold;
        if (t == null || price == null) return false;
        return price > t;

      case AlertType.priceBelow:
        final t = alert.threshold;
        if (t == null || price == null) return false;
        return price < t;

      case AlertType.percentChange:
        final t = alert.percent;
        if (t == null || pct == null) return false;
        return alert.direction == AlertDirection.above
            ? pct >= t
            : pct <= -t.abs();

      case AlertType.dayHigh:
        final high = quote.dayHigh;
        if (high == null || price == null) return false;
        return price >= high;

      case AlertType.dayLow:
        final low = quote.dayLow;
        if (low == null || price == null) return false;
        return price <= low;

      case AlertType.importantNews:
        return false;
    }
  }

  /// Varlik alarmi degerlendirir.
  ///
  /// Zaten tetiklenmis (`triggeredAt != null`) bir alarm **tekrar** bildirilmez;
  /// `repeat` alarminda tetik bayragini sifirlamak bekleyicinin isidir.
  static AlertEvaluation evaluate(PriceAlert alert, Quote? quote) {
    if (!alert.isArmed) return AlertEvaluation.skip;
    if (alert.type == AlertType.importantNews) return AlertEvaluation.skip;
    if (alert.triggeredAt != null) return AlertEvaluation.skip;
    if (!conditionMet(alert, quote)) return AlertEvaluation.skip;

    final price = quote!.hasPrice ? quote.price : null;
    final pct = quote.effectiveChangePercent;

    switch (alert.type) {
      case AlertType.priceAbove:
        return AlertEvaluation(
          fire: true,
          message: '${_n(price!)} seviyesi ${_n(alert.threshold!)} hedefinin '
              'üzerine çıktı.',
        );

      case AlertType.priceBelow:
        return AlertEvaluation(
          fire: true,
          message: '${_n(price!)} seviyesi ${_n(alert.threshold!)} hedefinin '
              'altına indi.',
        );

      case AlertType.percentChange:
        final sign = (pct ?? 0) >= 0 ? '+' : '-';
        return AlertEvaluation(
          fire: true,
          message: 'Değişim %$sign${_n((pct ?? 0).abs())} - '
              '${alert.direction.label} %${_n(alert.percent!.abs())} eşiğine '
              'ulaştı.',
        );

      case AlertType.dayHigh:
        return AlertEvaluation(
          fire: true,
          message: 'Günlük en yüksek ${_n(quote.dayHigh!)} seviyesinde.',
        );

      case AlertType.dayLow:
        return AlertEvaluation(
          fire: true,
          message: 'Günlük en düşük ${_n(quote.dayLow!)} seviyesinde.',
        );

      case AlertType.importantNews:
        return AlertEvaluation.skip;
    }
  }

  /// "Onemli haber" alarmi - verilen haber listesinde **gorulmemis** ve
  /// kategoriye uygun ilk haber icin bildirim uretir.
  ///
  /// [seenNewsIds] uygulama calisirken gorulen haber kimlikleridir; ayni
  /// haber iki kez bildirilmez.
  static AlertEvaluation evaluateNews({
    required PriceAlert alert,
    required List<NewsItem> items,
    required Set<String> seenNewsIds,
  }) {
    if (!alert.isArmed || alert.type != AlertType.importantNews) {
      return AlertEvaluation.skip;
    }
    final category = alert.newsCategory;

    for (final item in items) {
      if (seenNewsIds.contains(item.id)) continue;
      final matches = category == null ||
          category.isEmpty ||
          item.category.name == category ||
          item.category.label == category;
      if (!matches) continue;
      return AlertEvaluation(
        fire: true,
        message: '${item.source} · ${item.title}',
      );
    }
    return AlertEvaluation.skip;
  }

  static String _n(double? v) {
    if (v == null || !v.isFinite) return '—';
    final a = v.abs();
    if (a >= 100000) return v.toStringAsFixed(2);
    return v.toStringAsFixed(a < 1 ? 4 : 2);
  }
}
