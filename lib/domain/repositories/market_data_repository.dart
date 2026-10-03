import '../../core/error/failures.dart';
import '../entities/asset.dart';
import '../entities/candle.dart';
import '../entities/quote.dart';

/// Piyasa verisi repository arayuzu.
///
/// UI yalnizca bu arayuzu gorur. Hangi saglayicinin kullanildigi
/// (TCMB / Yahoo / hesaplama) data katmaninda yapilandirilir.
abstract interface class MarketDataRepository {
  /// Tek bir varligin guncel fiyatini getirir.
  Future<Result<Quote>> getQuote(String assetId);

  /// Birden fazla varligi tek seferde getirir (performans icin).
  ///
  /// Basarisiz olan ogeler [Success] icinde [Quote.unavailableFor] olarak
  /// doner; tumu basarisizsa [Err] doner. Boylece tek bir saglayici
  /// hatali tum listeyi dusurmez.
  Future<Result<Map<String, Quote>>> getQuotes(List<String> assetIds);

  /// Verilen varliklari besleyen saglayicilarin **destekledigi en hizli**
  /// guncelleme araligi.
  ///
  /// Zamanlayicilar buradan okunur; boylece aralik kodda degil saglayicinin
  /// kendisinde tanimlidir (saglayici takas edilirse otomatik guncellenir).
  Duration refreshInterval(List<String> assetIds);

  /// Fiyat akisi: `Data Provider -> Stream -> Repository -> UI`.
  ///
  /// Ilk deger saglayicidan geldikten sonra [interval] sureyle tekrarlanir
  /// (varsayilan [refreshInterval]). Kurallar:
  ///
  ///  * Basari -> taze fiyatlar yayinlanir.
  ///  * Sonraki bir istek basarisiz olursa **son gercek veri** yalnizca
  ///    `isStale = true` isaretiyle yayinlanir: ekranda eski fiyat korunur
  ///    ama "guncel degil" olarak gosterilir ve zamanlayici **kendiliginden
  ///    yeniden dener** (otomatik baglanti kurulumu).
  ///  * Ilk istek basarisiz ve hic veri yoksa akis **hata** yayar; UI
  ///    "Tekrar Dene" gorunumune gecer. Sahte deger uretilmez.
  ///  * [isActive] `false` dondurdugunde tik **ag istegine donusturulmez**
  ///    (arka plan); zamanlayici ayakta kalir, istek atilmaz ve
  ///    [isActive] yeniden `true` oldugunda sonraki tik hemen tazeler.
  Stream<Map<String, Quote>> watchQuotes(
    List<String> assetIds, {
    Duration? interval,
    bool Function()? isActive,
  });

  /// Grafik mumlarini getirir. Desteklenmeyen aralik [EmptyFailure] dondurur.
  ///
  /// [forceRefresh] `true` iken onbellek okunmaz (yine de **yazilir**);
  /// buna yalnizca "sik yenileme" gibi acik bir tazeleme niyeti oldugunda
  /// basvurulur. Boylece onbellek suresi ile yenileme zamanlayicisi ayni
  /// degere esit olsa bile sessiz yenileme gercekten yeni veri ceker.
  Future<Result<CandleSeries>> getCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
    bool forceRefresh = false,
  });

  /// Yalnizca **fiyat** onbelleklerini temizler (cekip-yenile icin).
  ///
  /// Mum/mini grafik onbellekleri korunur: fiyat yenilemesi ekranin geri
  /// kalanini gereksiz yere aga goturmesin.
  void invalidateQuotes();

  /// Yalnizca **mum** onbelleklerini temizler.
  void invalidateCandles();
}

/// Varlik kategorilerine gore liste dondurur.
abstract interface class MarketScreenerRepository {
  Future<Result<List<AssetDescriptor>>> getAssets(AssetCategory category);
}
