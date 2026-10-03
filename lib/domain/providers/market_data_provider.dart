import '../../core/error/failures.dart';
import '../entities/candle.dart';
import '../entities/quote.dart';

/// Ham piyasa verisi saglayici arayuzu.
///
/// Mimari: `UI -> State -> Repository -> MarketDataProvider -> API/RSS`
///
/// Bu arayuz "fiyat nereden geliyor?" sorusunun **tek** cevapidir. TCMB,
/// Yahoo Finance veya ileride lisansli bir saglayici bu arayuzu uygular;
/// repository ve UI somut sinifi **gormez**. Degistirmek icin tek yapilacak
/// sey, yeni saglayiciyi kaynak listesine eklemektir.
///
/// ## Kurallar
///  * Desteklenmeyen varlik icin yalnizca hata donulur; deger uretilmez.
///  * `null` / `NaN` fiyat yerine [EmptyFailure] yahut [Err] donulur.
///  * Kaynak etiketi [Quote.source] icindedir; `displayName` yalnizca
///    ayar/gelistirici gorunumunde kullanilir.
abstract interface class MarketDataProvider {
  /// Kaynak kimligi. Orn. `tcmb`, `yahoo`.
  String get id;

  /// Kaynagin okunabilir adi.
  String get displayName;

  /// Bu kaynak bu varligin **guncel fiyatini** saglayabilir mi?
  bool supports(String assetId);

  /// Bu kaynak mum (OHLC) serisi saglayabilir mi?
  bool supportsCandles(String assetId);

  /// Bu saglayicinin destekledigi **en hizli** guncelleme araligi.
  ///
  /// Mimari `Data Provider -> Stream -> Repository -> UI` oldugundan
  /// zamanlayici araligi **kodda sabitlenmez**, buradan okunur. Boylece
  /// saglayici degistirildiginde (orn. WebSocket'li bir kaynak eklendiginde)
  /// istemci kodu hic degismez.
  ///
  /// * WebSocket/stream varsa saglayici burada kisa bir aralik verir ve
  ///   tazelik `DataFreshness.live` olur.
  /// * Yalnizca periyodik HTTP varsa aralik, **talep icin guvenli** en hizli
  ///   seviyede tanimlanir ve tazelik `delayed`/`daily` kalir - "Canlı"
  ///   etiketi uydurulmaz.
  Duration get refreshInterval;

  /// Varliklarin guncel fiyatlarini toplu getirir.
  ///
  /// Desteklenmeyen yahut verisi bulunmayan varliklar sonuc haritasinda
  /// **yoktur**; hicbir sekilde uydurulmaz.
  Future<Result<Map<String, Quote>>> fetchQuotes(List<String> assetIds);

  /// Mum serisi. Desteklemiyorsa [EmptyFailure] dondurur.
  Future<Result<CandleSeries>> fetchCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
  });
}
