import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/providers/app_providers.dart';
import '../../domain/entities/economic_event.dart';

/// Takvim ekraninin durumu.
///
/// Bu dosya bilerek **sahte olay listesi uretmez**. Kaynak
/// (`EconomicCalendarProvider`) baglanmadigi surece repository `EmptyFailure`
/// dondurur ve ekran "veri yok" gosterir. Uydurma veri YOKTUR.
sealed class CalendarState {
  const CalendarState();
}

final class CalendarLoading extends CalendarState {
  const CalendarLoading();
}

final class CalendarError extends CalendarState {
  const CalendarError(this.message);
  final String message;
}

final class CalendarReady extends CalendarState {
  const CalendarReady(this.events);
  final List<EconomicEvent> events;
}

/// Secili gun araligi: 0=Bugün 1=Bu Hafta 2=Bu Ay
final calendarRangeProvider =
    NotifierProvider<CalendarRangeNotifier, int>(CalendarRangeNotifier.new);

class CalendarRangeNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void select(int index) => state = index;
}

/// Aralik anahtari -> (baslangic, bitis). Yerel zaman dilimi esas alinir.
(int, DateTime, DateTime) calendarRangeBounds(int index) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  switch (index) {
    case 0: // Bugün
      return (0, today, today.add(const Duration(days: 1)));
    case 2: // Bu Ay
      final first = DateTime(now.year, now.month, 1);
      final last = DateTime(now.year, now.month + 1, 1);
      return (2, first, last);
    default: // Bu Hafta (bugun + 7 gun)
      return (1, today, today.add(const Duration(days: 7)));
  }
}

/// Takvim olaylari.
///
/// **Not:** `economicCalendarSourceProvider` su an `null` oldugundan repository
/// acik bir `EmptyFailure` dondurur; ekran "veri kaynağına henüz bağlanılamadı"
/// durumunu gosterir. Kaynak eklenince bu dosyada hicbir degisiklik gerekmez.
final calendarEventsProvider =
    NotifierProvider<CalendarEventsNotifier, CalendarState>(
  CalendarEventsNotifier.new,
);

class CalendarEventsNotifier extends Notifier<CalendarState> {
  bool _busy = false;

  @override
  CalendarState build() {
    // Ilk yukleme - mikro gorev ile; build icinde durum degistirilmez.
    Future.microtask(refresh);
    return const CalendarLoading();
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    state = const CalendarLoading();

    final (_, from, to) = calendarRangeBounds(ref.read(calendarRangeProvider));

    try {
      final res = await ref
          .read(economicCalendarRepositoryProvider)
          .getEvents(from: from, to: to);
      if (!ref.mounted) return;

      res.when(
        onSuccess: (events) => state = CalendarReady(events),
        onFailure: (f) {
          // Kaynak henuz baglanmadi / sonuc yok -> bos liste gosterilir
          // (ekran "veri yok" der). Diger hatalar acikca gosterilir.
          state = f is EmptyFailure
              ? const CalendarReady([])
              : CalendarError(f.message);
        },
      );
    } catch (_) {
      // Beklenmeyen hata: uygulama dusmez, veri yok sayilir.
      if (ref.mounted) state = const CalendarReady([]);
    } finally {
      _busy = false;
    }
  }
}
