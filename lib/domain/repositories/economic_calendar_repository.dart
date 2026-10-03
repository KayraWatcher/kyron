import '../../core/error/failures.dart';
import '../entities/economic_event.dart';

/// Ekonomik takvim repository arayuzu.
///
/// UI yalnizca bu arayuzu gorur. Kaynak (varsa) data katmaninda
/// yapilandirilir; hicbir kaynak yapilandirilmamissa [Err] (bos) doner ve
/// arayuz "veri yok" durumunu gosterir.
abstract interface class EconomicCalendarRepository {
  /// [from, to] araligindaki olaylar.
  Future<Result<List<EconomicEvent>>> getEvents({
    required DateTime from,
    required DateTime to,
  });
}
