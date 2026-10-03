import '../entities/portfolio.dart';
import '../entities/quote.dart';

/// Portfoy hesaplari - saf fonksiyonlar, tamamen test edilebilir.
///
/// Kural: **asla uydurma fiyat kullanilmaz.** Bir varligin guncel fiyati
/// yoksa o kalem `hasPrice = false` olarak isaretlenir ve toplamda
/// dikkate alinmaz; eksik kisim ayrica gosterilir.
abstract final class PortfolioCalculator {
  /// Islem listesinden pozisyon ozetini hesaplar.
  ///
  /// [names]  : assetId -> gorunur ad
  /// [quotes] : assetId -> guncel fiyat (yoksa null)
  static PortfolioSummary compute({
    required List<PortfolioTransaction> transactions,
    Map<String, String> names = const {},
    Map<String, Quote> quotes = const {},
  }) {
    // Varlik bazinda toplula.
    final grouped = <String, List<PortfolioTransaction>>{};
    for (final t in transactions) {
      if (!t.isValid) continue;
      grouped.putIfAbsent(t.assetId, () => []).add(t);
    }

    if (grouped.isEmpty) return PortfolioSummary.empty;

    final items = <PortfolioItem>[];
    double totalValue = 0;
    double totalCost = 0;
    double dayChange = 0;
    double dayChangeValue = 0;
    var missing = false;

    grouped.forEach((assetId, list) {
      final agg = _aggregate(list);
      if (agg.netQuantity == 0 && agg.realizedCost == 0) return;

      final quote = quotes[assetId];
      final currentPrice = quote?.price;

      final hasPrice = currentPrice != null && currentPrice.isFinite;

      if (!hasPrice) missing = true;

      // Guncel deger yalnizca fiyat biliniyorsa hesaplanir.
      final currentValue = hasPrice ? agg.netQuantity * currentPrice : 0.0;

      // Maliyet: kalan pozisyonun maliyeti (satistan dusulmus).
      final cost = agg.realizedCost;

      final profitLoss = hasPrice ? currentValue - cost : 0.0;
      final profitLossPercent = cost > 0 ? (profitLoss / cost) * 100 : 0.0;

      if (hasPrice) totalValue += currentValue;

      // Maliyet yalnizca **fiyati bilinen** kalemlerden toplanir. Fiyati
      // alinamayan bir kalemin maliyeti toplanirken degeri toplanmazsa
      // `profitLoss` yanlis (yaniltici) cikar. Eksik kisim ayrica
      // `hasMissingPrices` ile gosterilir.
      if (hasPrice) totalCost += cost;

      final dayPct = quote?.effectiveChangePercent;
      if (hasPrice && dayPct != null && dayPct.isFinite) {
        // Onceki deger = guncel / (1 + oran/100).
        //
        // **NaN/Infinity koruması:** oran -100 ise bolme sifirdir; orani
        // asiri buyuk/ucuk ya da guncel deger 0 ise sonuc NaN cikabilir ve
        // tek bir kalem tum portfoy gunluk degisimini zehirlerdi
        // (ekranda "NaN" veya "∞"). Boyle bir kalemin katkisi **atlanir**;
        // o kalemin kendisi `dayChangePercent: null` ile zaten "bilinmiyor"
        // olarak gosterilir, uydurma deger uretilmez.
        final divisor = 1 + dayPct / 100;
        if (divisor.isFinite && divisor != 0) {
          final delta = currentValue - (currentValue / divisor);
          if (delta.isFinite) dayChangeValue += delta;
        }
      }

      items.add(PortfolioItem(
        assetId: assetId,
        assetName: names[assetId] ?? assetId,
        totalQuantity: agg.netQuantity,
        avgCost: agg.averageCost,
        totalCost: cost,
        currentValue: currentValue,
        profitLoss: profitLoss,
        profitLossPercent: profitLossPercent.isFinite ? profitLossPercent : 0.0,
        currentPrice: hasPrice ? currentPrice : null,
        dayChangePercent: (dayPct != null && dayPct.isFinite) ? dayPct : null,
        currency: quote?.currency,
        hasPrice: hasPrice,
      ));
    });

    items.sort((a, b) => b.currentValue.compareTo(a.currentValue));

    final profitLoss = totalValue - totalCost;
    final profitLossPercent = totalCost > 0 ? (profitLoss / totalCost) * 100 : 0.0;
    final prevTotal = totalValue - dayChangeValue;
    final dayChangePercent =
        prevTotal > 0 ? (dayChangeValue / prevTotal) * 100 : 0.0;
    dayChange = dayChangeValue.isFinite ? dayChangeValue : 0.0;

    return PortfolioSummary(
      totalValue: totalValue,
      totalCost: totalCost,
      profitLoss: profitLoss,
      profitLossPercent: profitLossPercent.isFinite ? profitLossPercent : 0.0,
      dayChange: dayChange,
      dayChangePercent: dayChangePercent.isFinite ? dayChangePercent : 0.0,
      items: items,
      hasMissingPrices: missing,
    );
  }

  static _Aggregate _aggregate(List<PortfolioTransaction> list) {
    // Tarihe gore sirala; FIFO maliyet ortalama icin.
    final sorted = [...list]..sort((a, b) => a.date.compareTo(b.date));

    double netQty = 0;
    double cost = 0;

    for (final t in sorted) {
      if (!t.isSell) {
        netQty += t.quantity;
        cost += t.nominal + t.fee;
      } else {
        // Satista maliyet orantili dusulur; negatife dusmeyecek sekilde.
        if (netQty > 0) {
          final avg = cost / netQty;
          final sold = t.quantity <= netQty ? t.quantity : netQty;
          final soldCost = avg * sold;
          cost -= soldCost;
          if (cost < 0) cost = 0;
          netQty -= sold;
        }
        // Satis komisyonu maliyeti artirir (net zarar/kar etkisi).
        cost += t.fee;
        if (cost < 0) cost = 0;
      }
    }

    if (netQty < 0) netQty = 0;

    final avg = netQty > 0 ? cost / netQty : 0.0;

    return _Aggregate(netQty, cost, avg);
  }

  /// Varlik dagilimi (%) - toplam deger sifirsa bos liste doner.
  static List<({String assetId, String name, double share, double value})>
      allocation(PortfolioSummary summary) {
    if (summary.totalValue <= 0) return const [];
    return [
      for (final i in summary.items)
        (
          assetId: i.assetId,
          name: i.assetName,
          share: i.shareOf(summary.totalValue),
          value: i.currentValue,
        ),
    ];
  }
}

class _Aggregate {
  const _Aggregate(this.netQuantity, this.realizedCost, this.averageCost);

  final double netQuantity;
  final double realizedCost;
  final double averageCost;
}
