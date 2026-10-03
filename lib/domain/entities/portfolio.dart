/// Portfoy islem kaydi.
class PortfolioTransaction {
  const PortfolioTransaction({
    required this.id,
    required this.assetId,
    required this.quantity,
    required this.price,
    required this.date,
    this.fee = 0,
    this.note,
    this.isSell = false,
  });

  final String id;
  final String assetId;

  /// Miktar (gram, adet, para birimi ...). Sifirdan buyuk olmali.
  final double quantity;

  /// Birim alis (veya satis) fiyati.
  final double price;

  final DateTime date;

  /// Komisyon (mutlak tutar).
  final double fee;

  final String? note;

  /// false -> alis, true -> satis.
  final bool isSell;

  /// Islem nominal degeri (komisyon haric).
  double get nominal => quantity * price;

  /// Toplam maliyet (komisyon dahil).
  double get totalCost => isSell ? -(nominal + fee) : nominal + fee;

  bool get isValid =>
      quantity.isFinite &&
      quantity > 0 &&
      price.isFinite &&
      price >= 0 &&
      fee.isFinite &&
      fee >= 0;
}

/// Portfoy ozeti.
class PortfolioSummary {
  const PortfolioSummary({
    required this.totalValue,
    required this.totalCost,
    required this.profitLoss,
    required this.profitLossPercent,
    required this.dayChange,
    required this.dayChangePercent,
    required this.items,
    this.hasMissingPrices = false,
  });

  final double totalValue;
  final double totalCost;
  final double profitLoss;
  final double profitLossPercent;
  final double dayChange;
  final double dayChangePercent;

  final List<PortfolioItem> items;

  /// Bazi varliklarin guncel fiyati alinamadiysa true.
  /// UI eksik kismi ayrica gosterir.
  final bool hasMissingPrices;

  static const PortfolioSummary empty = PortfolioSummary(
    totalValue: 0,
    totalCost: 0,
    profitLoss: 0,
    profitLossPercent: 0,
    dayChange: 0,
    dayChangePercent: 0,
    items: [],
  );

  bool get isEmpty => items.isEmpty;
}

/// Tek bir varligin portfoydeki durumu.
class PortfolioItem {
  const PortfolioItem({
    required this.assetId,
    required this.assetName,
    required this.totalQuantity,
    required this.avgCost,
    required this.totalCost,
    required this.currentValue,
    required this.profitLoss,
    required this.profitLossPercent,
    this.currentPrice,
    this.dayChangePercent,
    this.currency,
    this.hasPrice = true,
  });

  final String assetId;
  final String assetName;
  final double totalQuantity;
  final double avgCost;
  final double totalCost;
  final double currentValue;
  final double profitLoss;
  final double profitLossPercent;

  /// Guncel fiyat; alinamadiysa null (sahte deger yok).
  final double? currentPrice;
  final double? dayChangePercent;
  final String? currency;
  final bool hasPrice;

  /// Degerin portfoydeki agirligi (%).
  double shareOf(double portfolioTotal) {
    if (portfolioTotal <= 0 || !portfolioTotal.isFinite) return 0;
    final v = currentValue / portfolioTotal * 100;
    return v.isFinite ? v : 0;
  }
}
