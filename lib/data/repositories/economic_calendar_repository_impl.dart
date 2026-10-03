import '../../core/error/failures.dart';
import '../../domain/entities/economic_event.dart';
import '../../domain/providers/economic_calendar_provider.dart';
import '../../domain/repositories/economic_calendar_repository.dart';

/// Ekonomik takvim repository implementasyonu.
///
/// ## Kaynak durumu
/// `source` (bkz. `economicCalendarSourceProvider`) su an **null**'dur: uygun
/// ve hukuki acidan net bir veri kaynagi secilmedi (bkz. `pubspec` / asama 15
/// notlari). Boylece uygulama **sahte olay uretmez**; repository acik bir
/// `EmptyFailure` dondurur ve ekran "veri yok" durumunu gosterir.
///
/// Kaynak eklenince tek yapilacak sey `economicCalendarSourceProvider` icinde
/// yeni saglayiciyi dondurmektir - baska hicbir dosya degismez.
class EconomicCalendarRepositoryImpl implements EconomicCalendarRepository {
  EconomicCalendarRepositoryImpl(
    this.source, {
    this.cacheTtl = const Duration(minutes: 15),
  });

  /// Yapilandirilmis kaynak. `null` = henuz baglanmadi.
  final EconomicCalendarProvider? source;

  final Duration cacheTtl;

  List<EconomicEvent>? _cached;
  DateTime? _cachedAt;
  (DateTime, DateTime)? _cachedRange;

  @override
  Future<Result<List<EconomicEvent>>> getEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    final provider = source;
    if (provider == null) {
      return const Err(EmptyFailure(
        'Ekonomik takvim veri kaynağına henüz bağlanılamadı.',
      ));
    }

    if (!to.isAfter(from)) {
      return const Err(BadRequestFailure('Geçersiz tarih aralığı.'));
    }

    // Onbellek yalnizca ayni aralik icin gecerlidir.
    final now = DateTime.now();
    final cached = _cached;
    final at = _cachedAt;
    final range = _cachedRange;
    if (cached != null &&
        at != null &&
        range != null &&
        range.$1 == from &&
        range.$2 == to &&
        now.difference(at) < cacheTtl) {
      return Success(cached);
    }

    final res = await provider.fetchEvents(from: from, to: to);

    if (res case Success(data: final items)) {
      // Kaynakta olmayan alanlar zaten null olarak gelir; burada **hicbir**
      // deger tamamlanmaz.
      final sorted = [...items]..sort((a, b) => a.date.compareTo(b.date));
      _cached = sorted;
      _cachedAt = now;
      _cachedRange = (from, to);
      return Success(sorted);
    }

    // Ag hatasinda son gecerli veriyi goster (cevrimdisi destegi).
    final offline = _cached;
    if (offline != null && offline.isNotEmpty) return Success(offline);

    return Err(res.failureOrNull ?? const NetworkFailure());
  }

  void invalidateCache() {
    _cached = null;
    _cachedAt = null;
    _cachedRange = null;
  }
}
