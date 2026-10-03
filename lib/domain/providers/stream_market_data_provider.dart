import 'dart:async';

import '../../core/error/failures.dart';
import '../entities/quote.dart';
import 'market_data_provider.dart';

// =============================================================================
// GOLD v2 - Gercek zamanli veri arastirmasi ve akis (stream) arayuzu
// =============================================================================
//
// Amac: "fiyat tik geldikce, saniye/salise seviyesinde guncellensin" istegi
// icin **gercekten** kullanilabilir bir kaynak arastirildi. Sonuc:
//
//  | Kaynak                       | WS/stream | BIST gercek zamanli | Gecikme        | Ucretsiz | API anahtari | Lisans / ticari kisit                  | Mobil | Bid/Ask + tick |
//  |------------------------------|-----------|---------------------|----------------|----------|--------------|----------------------------------------|-------|----------------|
//  | Yahoo REST (Mevcut)          | Yok       | Hayir (snapshot)    | kendi 30 sn sorg| Evet     | Hayir        | Yahoo ToS otomatik erisimi kisitlar     | Evet  | Bid/ask snapshot|
//  | Yahoo WS `streamer.finance.` | Evet*     | Dogrulanmadi        | ~anlik (diger) | Evet     | Hayir        | *RESMI DEGIL + BIST lisansi belirsiz    | Evet  | Var             |
//  | Finnhub                      | Evet      | Hayir (fri: US/LSE) | anlik (US)     | Kisitli  | EVET         | Free = gelistirme amacli                | Evet  | Var             |
//  | Twelve Data                  | Evet      | XIST var; plana bagli| anlik (ucretli)| REST 800 | EVET         | Ucretsiz plan ticari kullanima kapali   | Evet  | Var             |
//  | BIST resmi (VERDA/CONNECT)   | Evet      | EVET                | sifir          | HAYIR    | Uyelik       | **Data Distribution Agreement zorunlu**  | altap | Tam             |
//  | Matriks (TR saglayici)       | Evet      | EVET                | anlik          | HAYIR    | EVET         | Kurumsal lisans                        | Evet  | Tam             |
//
//  * Yahoo WebSocket resmi dokumana sahip degil (protokol protobuf, ucmus
//    istemcilerle ortaya cikmis); ticari kullanima uygunlugu dogrulanmadi.
//
// SONUC (2026-10-02 itibariyla):
//  * **BIST gercek zamanli verinin uygulamada gosterilmesi Borsa Istanbul
//    Data Distribution Agreement lisansi gerektirir.** Bu bir lisans/hukuki
//    belirsizlik durumudur; kaynak secimi ve satin alma **kullanici onayina**
//    birakilmistir.
//  * Ucretsiz + anahtarsiz + tek teknik olarak akis saglayan aday Yahoo'nun
//    **resmi olmayan** WebSocket'idir; BIST icin gercek anliklik dogrulanmadi.
//
// Bu dosya o yuzden yalnizca **sözlesmeyi (contract) hazirlar**: kaynak
// secilmeden hicbir saglayici bu arayuzu uygulamaz ve hicbir ekran "Canlı"
// etiketi **uyduramaz**. Kaynak secildiginde tek yapilacak sey yeni
// saglayiciyi `app_providers.dart`'teki kaynak listesine eklemektir; UI ve
// repository kodu degismez (mimari `Data Provider -> Stream -> Repository ->
// UI`).
//
// =============================================================================
// Akis sozlesmesinin kurallari (SAHTE VERI YASAGI)
// =============================================================================
//
//  1. Akis, **gercekten** kaynaktan gelen tik/hedef fiyatlarini tasir.
//     Arayuz, uretilmis/ rastgele/ yavaslatilmis "canli gorunumu" isteyen bir
//     davranisi **desteklemez**: `watchQuotes` yalnizca [Quote] uretir, zaman
//     atlamasi veya deger uydurmak icin bir parametre almaz.
//  2. [StreamableMarketDataProvider.watchQuotes] yalnizca o saglayicinin
//     **hicbir arac cozmeden** verdigi degerleri icerir.
//  3. Akis `Success` verisi gonderdiginde [Quote.updatedAt] kaynagin kendi
//     islem zamanidir; uygulama saati degil.
//  4. Baglanti koparsa akis `Err` yayar veya biter; repository son **gercek**
//     veriyi korur, `isStale: true` isaretler ve yeniden baglanir. Veri
//     **asla** "hala guncel" gibi gosterilmez.
//  5. [Quote.freshness] yalnizca kaynak **tick seviyesinde ve lisansli**ysa
//     `DataFreshness.live` olabilir. Gecikmeli kaynak `delayed`, gunluk resmi
//     oran `daily`, piyasa kapaliysa `closed` kullanir. `live` uydurmak
//     yasaktir.
//  6. API anahtari gerekliyse [streamRequiresApiKey] `true` olur ve anahtar
//     hicbir yere kodlanmaz; `--dart-define` ile verilir. Anahtar/uyelik/
//     satin alma gerektiren bir kaynak **kullanici onayi olmadan eklenmez**.
// =============================================================================

/// Gercek zamanli **fiyat akisi** (WebSocket / SSE / MQTT) saglayabilen
/// piyasa verisi saglayicisi.
///
/// [MarketDataProvider]'in **ustune** cikan opsiyonel bir sozlesmedir:
/// mevcut saglayicilar (Yahoo REST, TCMB) bunu **uygulamaz**; cunku
/// periyodik HTTP sorgusu bir akis degildir. Boylece "canli" etiketi,
/// arayuzu uygulayan ilk saglayici gorunmeden **hiçbir yerde beliremez**.
///
/// ### Repository ile entegrasyon
/// Kaynak secildikten sonra repository, istenen varliklarin tamami icin
/// `source is StreamableMarketDataProvider && supportsStreaming(id)` ise bu
/// akisi, aksi halde mevcut periyodik sorgulamayi (polling) kullanir.
/// Ekran ve durum yonetimi degismez.
///
/// ### Neden `Result` yayar?
/// Akista hata bir **degerdir**, istisna degil: `Err` geldiginde repository
/// son gercek fiyati korur ve `isStale: true` ile "guncel degil" gosterir.
/// Akisin kendisi kapanirse (`onDone`) ayni islem yapilir ve yeniden
/// baglanilir. Boylece ag kopmasi asla uydurma fiyatla kapatilmaz.
abstract interface class StreamableMarketDataProvider
    implements MarketDataProvider {
  /// Akis protokolu. Yalnizca rapor/gorunum icindir. Orn. `'WebSocket'`.
  String get streamProtocol;

  /// Kaynagin **kendi** beyan ettigi uc-to-uc gecikme suresi.
  ///
  /// * `Duration.zero` -> tik seviyesinde (borsa islem akisi).
  /// * Birkac saniye   -> hedef fiyat yayini.
  /// * Bu deger `live`/`delayed` ayrimini **kaynak belirler**; uygulama
  ///   sureden "canli" diye **sonuc cikarmaz**.
  Duration get streamLatency;

  /// Akis icin API anahtari / uye girisi gerekiyor mu?
  ///
  /// `true` ise anahtar yalnizca `--dart-define` ile verilir ve bu kaynak
  /// **kullanici onayi olmadan** projeye eklenmez.
  bool get streamRequiresApiKey;

  /// Bu kaynak akis biciminde [assetId] varligini saglayabilir mi?
  ///
  /// `false` dondugu varlik icin repository polling'e duser; akis **asla**
  /// desteklenmeyen varlik icin veri **uretmez**.
  bool supportsStreaming(String assetId);

  /// Fiyat akisi.
  ///
  /// Akis sadece istenen varliklari icerir. Ilk paket gelene kadar ekran
  /// yuklemede kalir; hic paket gelmezse yukleme hatasi gosterilir ve
  /// uydurma fiyat cizilmez.
  ///
  /// Akis kuralari dosya basindaki "SAHTE VERI YASAGI" bolumunde listelenir.
  Stream<Result<Map<String, Quote>>> watchQuotes(List<String> assetIds);
}
