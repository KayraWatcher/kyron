import 'data_freshness.dart';

/// Bir varligin anlik fiyat gorunumu.
///
/// Tum alanlar nullable degildir; veri yoksa deger [QuoteSource.unavailable]
/// ile birlikte sifirlanir ve UI "—" gosterir. Asla NaN/uydurma fiyat yok.
class Quote {
  const Quote({
    required this.assetId,
    required this.source,
    required this.updatedAt,
    this.price,
    this.bid,
    this.ask,
    this.open,
    this.previousClose,
    this.dayHigh,
    this.dayLow,
    this.change,
    this.changePercent,
    this.currency,
    this.volume,
    this.isStale = false,
    this.freshness = DataFreshness.unknown,
    this.marketTime,
  });

  final String assetId;
  final QuoteSourceLabel source;
  final DateTime updatedAt;

  /// Guncel fiyat (son islem).
  final double? price;
  final double? bid;
  final double? ask;
  final double? open;
  final double? previousClose;
  final double? dayHigh;
  final double? dayLow;
  final double? change;
  final double? changePercent;
  final String? currency;
  final double? volume;

  /// Onbellekten geliyorsa true - UI "son güncelleme" etiketi gosterir.
  final bool isStale;

  /// Kaynagin beyan ettigi veri guncelligi.
  ///
  /// "Canlı" etiketi **yalnizca** [DataFreshness.live] icinde gosterilir ve
  /// bu durum yalnizca saglayici gercek zamanli akisi dogruladiginda uretilir.
  final DataFreshness freshness;

  /// Kaynagin bildirdigi son islem zamani (varsa).
  ///
  /// Yahoo `regularMarketTime` gibi. Yoksa `updatedAt` (cekme ani) kullanilir.
  final DateTime? marketTime;

  bool get hasPrice => price != null && price!.isFinite;

  /// Makas (ask - bid). Gecerli degilse null.
  double? get spread {
    final a = ask;
    final b = bid;
    if (a == null || b == null) return null;
    final v = a - b;
    return v.isFinite ? v : null;
  }

  /// Makas yuzdesi.
  double? get spreadPercent {
    final s = spread;
    final a = ask;
    if (s == null || a == null || a == 0) return null;
    final v = s / a * 100;
    return v.isFinite ? v : null;
  }

  /// Degisim yoksa previousClose'tan hesapla.
  double? get effectiveChange {
    final c = change;
    if (c != null && c.isFinite) return c;
    final p = price;
    final pc = previousClose;
    if (p == null || pc == null) return null;
    final v = p - pc;
    return v.isFinite ? v : null;
  }

  double? get effectiveChangePercent {
    final c = changePercent;
    if (c != null && c.isFinite) return c;
    final p = price;
    final pc = previousClose;
    if (p == null || pc == null || pc == 0) return null;
    final v = (p - pc) / pc * 100;
    return v.isFinite ? v : null;
  }

  Quote copyWith({
    double? price,
    double? bid,
    double? ask,
    double? open,
    double? previousClose,
    double? dayHigh,
    double? dayLow,
    double? change,
    double? changePercent,
    String? currency,
    double? volume,
    QuoteSourceLabel? source,
    DateTime? updatedAt,
    bool? isStale,
    DataFreshness? freshness,
    DateTime? marketTime,
  }) =>
      Quote(
        assetId: assetId,
        source: source ?? this.source,
        updatedAt: updatedAt ?? this.updatedAt,
        price: price ?? this.price,
        bid: bid ?? this.bid,
        ask: ask ?? this.ask,
        open: open ?? this.open,
        previousClose: previousClose ?? this.previousClose,
        dayHigh: dayHigh ?? this.dayHigh,
        dayLow: dayLow ?? this.dayLow,
        change: change ?? this.change,
        changePercent: changePercent ?? this.changePercent,
        currency: currency ?? this.currency,
        volume: volume ?? this.volume,
        isStale: isStale ?? this.isStale,
        freshness: freshness ?? this.freshness,
        marketTime: marketTime ?? this.marketTime,
      );

  static Quote unavailableFor(String assetId) => Quote(
        assetId: assetId,
        source: QuoteSourceLabel.unavailable,
        updatedAt: DateTime.now(),
        freshness: DataFreshness.unknown,
      );
}

/// Yeni gelen fiyat haritasini oncekiyle birlestirir.
///
/// Saglayici sembol atlatabilir (Yahoo `GC=F` / `SI=F` gecici olarak
/// donmeyebilir). Boyle bir yanitta **mevcut degerler kaybolmaz**: yeni
/// haritada yer almayan ama onceki yanitta bilinen varliklar son degeriyle
/// korunur ve `isStale = true` ile isaretlenir. Boylece ana sayfadaki
/// Ons Altin / Ons Gumus kartlari bir anda silinmez; "son bilinen veriler"
/// olarak ekranda kalir ve saglayici tekrar dondugunde tazelenir.
///
/// Kural:
///  * gelen degerler her zaman oncekinin uzerine yazar,
///  * gelmeyen id'ler silinmez, yalnizca bayat olarak isaretlenir,
///  * [prev] null/bos ise yalnizca [next] doner.
Map<String, Quote> mergeQuotes(
  Map<String, Quote>? prev,
  Map<String, Quote> next,
) {
  if (prev == null || prev.isEmpty) return next;

  final merged = <String, Quote>{...prev, ...next};
  for (final key in prev.keys) {
    if (next.containsKey(key)) continue;
    final old = prev[key]!;
    // Zaten bayatsa yeniden olusturma (gereksiz rebuild engellenir).
    if (!old.isStale) merged[key] = old.copyWith(isStale: true);
  }
  return merged;
}

/// Veri kaynagi etiketi - UI'da "hesaplanan" ayrimi icin kullanilir.
enum QuoteSourceLabel {
  market('Piyasa'),
  calculated('Hesaplanan'),
  otc('Serbest Piyasa'),
  unavailable('Veri Yok');

  const QuoteSourceLabel(this.label);

  final String label;

  bool get isUnavailable => this == QuoteSourceLabel.unavailable;
}
