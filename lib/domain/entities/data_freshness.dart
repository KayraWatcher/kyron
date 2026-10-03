/// Verinin **gercek guncellik seviyesi** (saglayici tarafindan beyan edilir).
///
/// Bu etiket hicbir sekilde uydurulmaz; yalnizca saglayicinin verdigi bilgiden
/// turetilir:
///
///  * Yahoo `regularMarketTime` + `currentTradingPeriod` -> piyasa acik/kapali
///    ve **gecikmeli feed** oldugu bilgisi.
///  * TCMB `today.xml` -> gunde bir aciklanan resmi kur -> [DataFreshness.daily].
///
/// "Canlı" yazisi **yalnizca** [DataFreshness.live] icinde bulunur ve bu
/// durum yalnizca saglayici gercek zamanli akisi (WebSocket/stream) dogruladiginda
/// uretilir. Ucretsiz Yahoo/TCMB beslemeleri boyle bir garanti vermedigi icin
/// [DataFreshness.live] uretmezler.
enum DataFreshness {
  /// Saglayici gercek zamanli akis dogrulamis (WebSocket/stream).
  live('Canlı', 'Veri gerçek zamanlı akıştan geliyor'),

  /// Saglayici gecikmeli feed yayinlayabiliyor (Yahoo chart beslemesi gibi).
  delayed('Gecikmeli', 'Sağlayıcı gecikmeli veri yayınlayabiliyor'),

  /// Gunde bir aciklanan resmi veri (TCMB kurlari gibi).
  daily('Günlük resmi', 'Günde bir açıklanan resmi veri'),

  /// Piyasa kapali; deger gunun son islemidir.
  closed('Piyasa kapalı', 'Piyasa kapalı; değer günün son işlemi'),

  /// Guncellik olculmus / kanitlanamamis -> UI asla "Canlı" yazmaz.
  unknown('Tazelik bilinmiyor', 'Verinin güncellik düzeyi doğrulanmadı');

  const DataFreshness(this.label, this.description);

  /// UI'da gosterilen kisa etiket.
  final String label;

  /// Uzun aciklama (tooltip / detay satiri).
  final String description;

  /// Siralama: buyuk sayi daha tazedir.
  int get rank => switch (this) {
        DataFreshness.live => 4,
        DataFreshness.delayed => 3,
        DataFreshness.daily => 2,
        DataFreshness.closed => 1,
        DataFreshness.unknown => 0,
      };

  /// [other]'dan daha taze mi? (esitlikte false)
  bool isFresherThan(DataFreshness other) => rank > other.rank;

  /// Tazelikleri birlestirir (hesaplanan varliklar icin).
  ///
  /// Kurallar:
  ///  * Bilesenlerden herhangi biri [unknown] ise sonuc [unknown] olur -
  ///    bilmedigimiz bir degeri "taze" diye gosterme.
  ///  * Herhangi bir bilesen [closed] ise sonuc [closed] olur: altin piyasasi
  ///    kapaliyken gram altinin sayisi da hareket etmez.
  ///  * Diger durumlarda **en taze** bilesen secilir. Hesaplanan bir degerin
  ///    guncelleme sikligini en hizli degisen bilesen belirler (orn. gram
  ///    altin = ons x USD/TRY; USD/TRY gun boyu sabit kaldigi icin gram
  ///    altinin sayisi onsin akisiyla hareket eder).
  static DataFreshness combine(Iterable<DataFreshness> parts) {
    final list = parts.toList(growable: false);
    if (list.isEmpty) return DataFreshness.unknown;
    if (list.any((f) => f == DataFreshness.unknown)) {
      return DataFreshness.unknown;
    }
    if (list.any((f) => f == DataFreshness.closed)) {
      return DataFreshness.closed;
    }
    return list.reduce((a, b) => a.rank >= b.rank ? a : b);
  }

  /// Bir ekrandaki verilerin **en taze** olani.
  ///
  /// [combine]'in tersine burada `closed` ustunluk kurmaz: ekranda hem kapali
  /// bir borsa (BIST gece) hem acik bir piyasa (ons altin) varsa ozet
  /// "Gecikmeli" demelidir, "Piyasa kapalı" degil.
  ///
  /// Tum degerler `unknown` ise (ya da hic veri yoksa) `unknown` doner.
  static DataFreshness freshest(Iterable<DataFreshness> parts) {
    final list = parts.toList(growable: false);
    if (list.isEmpty) return DataFreshness.unknown;
    final known = list.where((f) => f != DataFreshness.unknown).toList();
    if (known.isEmpty) return DataFreshness.unknown;
    return known.reduce((a, b) => a.rank >= b.rank ? a : b);
  }
}
