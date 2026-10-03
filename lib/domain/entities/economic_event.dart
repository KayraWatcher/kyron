/// Ekonomik takvim olayi.
///
/// **Onemli:** Veri yoksa alan `null` birakilir; asla uydurma deger
/// gosterilmez. UI bu alanlari "—" olarak isaretler.
class EconomicEvent {
  const EconomicEvent({
    required this.id,
    required this.title,
    required this.country,
    required this.date,
    this.time,
    this.importance,
    this.actual,
    this.forecast,
    this.previous,
    this.source,
    this.category,
  });

  final String id;

  /// Gosterge adi. Orn. "TCMB Faiz Kararı", "TÜİK Enflasyon (Aylık)".
  final String title;

  /// Ulke kodu/adı. "TR", "ABD", "EU", "ALM".
  final String country;

  final DateTime date;

  /// Saat (kaynakta varsa). Yoksa null.
  final DateTime? time;

  /// Onem seviyesi: 1 dusuk, 2 orta, 3 yuksek. Kaynakta yoksa null.
  final int? importance;

  /// Gerceklesen deger. Veri yoksa **null** - asla uydurulmaz.
  final String? actual;

  /// Beklenti. Veri yoksa **null**.
  final String? forecast;

  /// Onceki deger. Veri yoksa **null**.
  final String? previous;

  final String? source;

  /// "faiz" | "enflasyon" | "istihdam" | "buyume" | "ticaret" | "bilanco"
  final String? category;

  bool get hasActual => actual != null && actual!.isNotEmpty;
  bool get hasForecast => forecast != null &&forecast!.isNotEmpty;
  bool get hasPrevious => previous != null && previous!.isNotEmpty;

  EconomicEvent copyWith({String? actual, String? forecast, String? previous}) =>
      EconomicEvent(
        id: id,
        title: title,
        country: country,
        date: date,
        time: time,
        importance: importance,
        actual: actual ?? this.actual,
        forecast: forecast ?? this.forecast,
        previous: previous ?? this.previous,
        source: source,
        category: category,
      );

  @override
  bool operator ==(Object other) => other is EconomicEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
