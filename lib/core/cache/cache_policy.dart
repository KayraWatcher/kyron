/// Uygulama genelinde **tek noktadan** tanimlanan sure/one bellek politikasi.
///
/// Neden tek nokta?
///  * Fiyat, haber ve takvim TTL'leri birbirinden kopuk buyumustu; ayni
///    verinin farkli ekranlarda farkli tazelik gostermesi mumkundu.
///  * Zamanlayici araliklari (izleyici, mini grafik, piyasalar) repository
///    TTL'leriyle **uymak** zorunda: zamanlayici TTL'den kisa olursa her
///    dongude gereksiz ag istegi, uzun olursa ekranda bayat veri kalir.
///
/// Degerler `assert` ile dogrulanir; bozuk bir politika gelistirme
/// derlemesinde hemen firlar.
abstract final class CachePolicy {
  // ---------------------------------------------------------------------------
  // ON BELLEK TTL'leri (repository / saglayici)
  // ---------------------------------------------------------------------------

  /// Guncel fiyat (quote) **yedek** tazelik suresi.
  ///
  /// 60 sn: borsa acikken anlik gosterim icin yeterince taze, ayrica
  /// ekranlar arasi ayni istegin tekrar tekrar gonderilmesini onler.
  ///
  /// **Not (v2):** Gercek sure besleyen saglayicidan gelir
  /// (`MarketDataProvider.refreshInterval`): Yahoo 3 sn, TCMB 5 dk.
  /// Bu deger yalnizca besleyen kaynak tanimsizsa devreye girer.
  static const Duration quoteTtl = Duration(seconds: 60);

  /// Detay ekraninda **odaklanan tek varlik** icin hizli tazeleme ritmi.
  ///
  /// Kullanici bir varligin detayina girdiginde fiyat hizli hizli gelsin
  /// istenir; yalnizca o tek sembol istendigi icin yuk tek sembole iner.
  /// Saglayici hata verirse repository ustel geri cekilmeye gecer
  /// (`MarketDataRepository.watchQuotes`) - istek atilmaya devam edilmez.
  static const Duration focusedQuoteRefreshInterval = Duration(seconds: 1);

  /// Grafik mum serisi TTL'i - fiyat TTL'inin kati katidir (cizim pahali,
  /// veri seyrek degisir).
  static const Duration candleTtl = Duration(seconds: 180);

  /// Haber beslemesi TTL'i.
  static const Duration newsTtl = Duration(minutes: 5);

  /// Ekonomik takvim TTL'i - takvim verisi gunde birkac kez guncellenir.
  static const Duration calendarTtl = Duration(minutes: 15);

  // ---------------------------------------------------------------------------
  // ZAMANLAYICI ARALIKLARI (repository TTL'leri ile uyumlu olmali)
  // ---------------------------------------------------------------------------

  /// Yedek guncelleme araligi.
  ///
  /// **Not (v2):** Zamanlayicilar artik bu sabit yerine
  /// `MarketDataRepository.refreshInterval(...)` ile **saglayicinin
  /// kendisinden** okunur (Yahoo 30 sn, TCMB 5 dk). Bu deger yalnizca
  /// besleyen saglayici tanimsizsa kullanilir.
  static const Duration quoteRefreshInterval = Duration(seconds: 60);

  /// Yedek piyasalar ekrani yenileme araligi (bkz. [quoteRefreshInterval]).
  static const Duration marketsRefreshInterval = Duration(seconds: 60);

  /// Mini grafik yenileme araligi.
  static const Duration miniChartRefreshInterval = Duration(seconds: 60);

  /// Alarm izleyici (watchdog) araligi. Fiyat TTL'inden **kisa** olmali;
  /// boylece her dongude yeni ag istegi gider ve alarmlar zamaninda tetiklenir.
  static const Duration alertEvaluationInterval = Duration(seconds: 30);

  /// Mini grafik onbellek suresi; suresi dolan bellek tasarrufu icin birakilir.
  static const Duration miniChartKeepAlive = Duration(minutes: 5);

  // ---------------------------------------------------------------------------
  // DOGRULAMA
  // ---------------------------------------------------------------------------

  /// Politika tutarliligi - gelistirme derlemesinde kontrol edilir.
  static void _validate() {
    assert(
      alertEvaluationInterval <= quoteTtl,
      'Alarm degerlendirme araligi fiyat TTL\'inden uzun olursa alarm '
      'bayat veriyle degerlendirilir.',
    );
    assert(
      quoteRefreshInterval >= quoteTtl,
      'Yenileme araligi fiyat TTL\'inden kisa olursa ag istegi tekrarlanir.',
    );
    assert(
      candleTtl >= quoteTtl,
      'Mum serisi TTL\'i fiyat TTL\'inden kucuk olmamali.',
    );
    assert(
      quoteTtl > Duration.zero && candleTtl > Duration.zero,
      'TTL degerleri pozitif olmali.',
    );
  }

  /// Ilk erisimde dogrulamayi tetikler.
  static void ensureValid() => _validate();
}
