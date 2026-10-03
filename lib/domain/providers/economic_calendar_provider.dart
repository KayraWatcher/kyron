import '../../core/error/failures.dart';
import '../entities/economic_event.dart';

/// Ekonomik takvim saglayici arayuzu.
///
/// Mimari: `UI -> State -> Repository -> EconomicCalendarProvider -> API`
///
/// ## Veri bicagi (zorunlu)
/// Kaynak yalnizca **kendinde var olan** alanlari dondurur:
///
///  * `actual`    -> gerceklesen deger; **kaynakta yoksa `null`**
///  * `forecast`  -> beklenti; **kaynakta yoksa `null`**
///  * `previous`  -> onceki deger; **kaynakta yoksa `null`**
///  * `importance` -> 1..3; **kaynakta yoksa `null`**
///
/// Bu alanlar hicbir kosulda **tahmin edilmez, hesaplanmaz veya
/// uydurulmaz**. Eksik deger UI'da "—" olarak gosterilir.
///
/// Satici hesap anahtari, abonelik ya da ucretli plan gerektiriyorsa bu
/// arayuz **uygulanmadan once** kullanici onayi alinmalidir.
abstract interface class EconomicCalendarProvider {
  /// Kaynak kimligi. Orn. `fair-economy`, `investing`.
  String get id;

  /// Kaynagin okunabilir adi.
  String get displayName;

  /// [from, to] araligindaki ekonomik olaylari getirir.
  ///
  /// Aralik disindaki olaylar dondurulmez; bulunan olay yoksa [Err]
  /// (bos) donulur - bos liste **uydurulmaz**.
  Future<Result<List<EconomicEvent>>> fetchEvents({
    required DateTime from,
    required DateTime to,
  });
}
