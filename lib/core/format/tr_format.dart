import 'package:intl/intl.dart';

/// Turkce sayi/tarih bicimlendirme tek noktada toplanir.
///
/// Ornek ciktilar:
///   money(6024.5)     -> "6.024,50"
///   signed(1.42)      -> "+1,42"
///   percent(1.42)     -> "%+1,42"
///   date(...)         -> "2 Ekim 2026"
///
/// `NaN` / `null` asla ekrana yazdirilmaz; yerine [noData] dondurulur.
abstract final class TrFormat {
  static const String noData = '—';

  static const Map<int, String> _months = {
    1: 'Ocak',
    2: 'Şubat',
    3: 'Mart',
    4: 'Nisan',
    5: 'Mayıs',
    6: 'Haziran',
    7: 'Temmuz',
    8: 'Ağustos',
    9: 'Eylül',
    10: 'Ekim',
    11: 'Kasım',
    12: 'Aralık',
  };

  static const Map<int, String> _weekdays = {
    1: 'Pazartesi',
    2: 'Salı',
    3: 'Çarşamba',
    4: 'Perşembe',
    5: 'Cuma',
    6: 'Cumartesi',
    7: 'Pazar',
  };

  static final NumberFormat _money = NumberFormat('#,##0.00', 'tr_TR');
  static final NumberFormat _moneyInt = NumberFormat('#,##0', 'tr_TR');
  static final NumberFormat _plain = NumberFormat('0.00', 'tr_TR');
  static final NumberFormat _plain4 = NumberFormat('0.0000', 'tr_TR');

  /// Guvenli kontrol: null veya non-finite ise gecersizdir.
  static bool isValid(num? value) => value != null && value.isFinite;

  /// Lokal, promote edilmis deger dondurur; boylece cagri yerinde
  /// null kontrolu tekrarlanmak zorunda kalinmaz.
  static double? _valid(num? value) =>
      (value != null && value.isFinite) ? value.toDouble() : null;

  static NumberFormat _dec(int decimals) =>
      decimals <= 0 ? _moneyInt : NumberFormat('0.${'#' * decimals}', 'tr_TR');

  /// `money` icin ondalik basina bir kez olusturulan bicimleyiciler.
  ///
  /// Binlik ayirici + **sabit** ondalik sayisi: "1.234,5678".
  static final Map<int, NumberFormat> _moneyByDecimals = <int, NumberFormat>{
    0: NumberFormat('#,##0', 'tr_TR'),
    2: NumberFormat('#,##0.00', 'tr_TR'),
  };

  static NumberFormat _moneyDec(int decimals) {
    final d = decimals < 0 ? 0 : decimals;
    return _moneyByDecimals.putIfAbsent(
      d,
      // '0' zorunlu basamak: 2 -> "#,##0.00" (eski `_money` ile birebir),
      // 4 -> "#,##0.0000" (eski `_plain4` ama binlik ayiricili).
      () => NumberFormat('#,##0${d == 0 ? '' : '.${'0' * d}'}', 'tr_TR'),
    );
  }

  /// "6.024,50" - ondalikli para. Gecerli degilse [noData].
  ///
  /// **Not:** eski uygulamada yalnizca 0/2/4 elden geciyordu; 1, 3, 6 gibi
  /// degerler sessizce 2 ondaliga dusuyordu (USD/TRY "42,123" -> "42,12",
  /// 1 altindaki varlik "0,123456" -> "0,12"). Artik istenen her basamak
  /// aynen yazilir.
  static String money(num? value, {int decimals = 2}) {
    final v = _valid(value);
    if (v == null) return noData;
    return _moneyDec(decimals).format(v);
  }

  /// "6.024,50 TL" eki ile.
  static String moneyWithCurrency(
    num? value,
    String currency, {
    int decimals = 2,
  }) {
    final v = _valid(value);
    if (v == null) return noData;
    return '${money(v, decimals: decimals)} $currency';
  }

  /// Fiyat gosterimi - buyuklug gore ayarli ondalik.
  static String price(num? value) {
    final v = _valid(value);
    if (v == null) return noData;
    final abs = v.abs();
    if (abs >= 1000) return _money.format(v);
    if (abs >= 1) return _plain.format(v);
    return _plain4.format(v);
  }

  /// "+1,42" - imzali degisim. Gecerli degilse [noData].
  static String signed(num? value, {int decimals = 2}) {
    final v = _valid(value);
    if (v == null) return noData;
    final s = _dec(decimals).format(v);
    return v > 0 ? '+$s' : s;
  }

  /// "%+1,42" - yuzde degisim (isaretli).
  static String percent(num? value, {int decimals = 2, bool withSign = true}) {
    final v = _valid(value);
    if (v == null) return noData;
    final s = _dec(decimals).format(v);
    if (!withSign) return '%$s';
    return v > 0 ? '%+$s' : '%$s';
  }

  /// Turkce giris metnini sayiya cevirir (formatin tersi).
  ///
  /// Kabul edilenler: "3.500,50" / "3500.50" / "3500,50" / "1.5" / "-2".
  ///
  /// **Eski hata:** `replaceAll('.', '').replaceAll(',', '.')` her noktayi
  /// binlik sayiyordu; kullanici "1.5" yazdiginda sonuc **15** oluyordu.
  /// Artik ayirici rolu son ayiriciya gore belirlenir:
  ///
  ///  * iki ayirici de varsa son gorulen ondaliktir
  ///    ("1.500,25" -> 1500.25, "1,500.25" -> 1500.25),
  ///  * yalnizca virgul -> ondalik (Turkce kural): "1,5" -> 1.5,
  ///    coklu virgul binlik olarak yorumlanir ("1,500,25" -> 150025),
  ///  * yalnizca nokta -> 3 hane takip ederse binlik ("1.500" -> 1500),
  ///    aksi halde ondalik ("1.5" -> 1.5, "0.500" -> 0.5);
  ///    coklu nokta her zaman binliktir ("1.234.567" -> 1234567).
  ///
  /// Ayirici disinde rakam yoksa `null` (uydurma deger uretilmez).
  static double? parse(String raw) {
    var s = raw.trim().replaceAll(' ', '').replaceAll('\u00A0', '');
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    if (s.isEmpty) return null;

    final hasComma = s.contains(',');
    final hasDot = s.contains('.');
    late final String normalized;

    if (hasComma && hasDot) {
      // Son ayirici ondaliktir; digeri binlik olarak silinir.
      final commaLast = s.lastIndexOf(',') > s.lastIndexOf('.');
      final decimal = commaLast ? ',' : '.';
      final thousand = commaLast ? '.' : ',';
      normalized = s.replaceAll(thousand, '').replaceFirst(decimal, '.');
    } else if (hasComma) {
      normalized = s.indexOf(',') == s.lastIndexOf(',')
          ? s.replaceFirst(',', '.')
          : s.replaceAll(',', '');
    } else if (hasDot) {
      final first = s.indexOf('.');
      if (first != s.lastIndexOf('.')) {
        normalized = s.replaceAll('.', ''); // coklu nokta = binlik
      } else {
        final fractional = s.length - first - 1;
        final intPart = s.substring(0, first);
        // "0.500" -> 0,5 (on sifirla baslayan tam kisim binlik olamaz),
        // "1.500" / "10.500" -> binlik.
        final thousands = fractional == 3 &&
            intPart.isNotEmpty &&
            !intPart.startsWith('0');
        normalized = thousands ? s.replaceFirst('.', '') : s;
      }
    } else {
      normalized = s;
    }

    // ".5" gibi girislerde tam sayi kismi tamamlanir.
    final candidate = normalized.startsWith('.') ? '0$normalized' : normalized;
    if (!RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(candidate)) return null;

    final v = double.tryParse(candidate);
    if (v == null || !v.isFinite) return null;
    return negative ? -v : v;
  }

  /// Buyuk rakamlar icin kisa gosterim: "1,2 Mn" / "3,4 Mr".
  static String compact(num? value) {
    final v = _valid(value);
    if (v == null) return noData;
    final abs = v.abs();
    if (abs >= 1e12) return '${_plain.format(v / 1e12)} T';
    if (abs >= 1e9) return '${_plain.format(v / 1e9)} Mr';
    if (abs >= 1e6) return '${_plain.format(v / 1e6)} Mn';
    if (abs >= 1e3) return '${_moneyInt.format(v / 1e3)} B';
    return _money.format(v);
  }

  /// "2 Ekim 2026"
  static String date(DateTime? d) {
    if (d == null) return noData;
    return '${d.day} ${_months[d.month]} ${d.year}';
  }

  /// "2 Ekim 2026, 14:32"
  static String dateTime(DateTime? d) {
    if (d == null) return noData;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${date(d)}, $h:$m';
  }

  /// "2 Ekim 2026, 14:32:07"
  ///
  /// Fiyatin **ne zaman cekildigini** saniye gorunurluguyle gosterir.
  /// Zamanlayici her tikte bu degeri tazeler; deger donmeyince akisin
  /// durdugu (ag kopmasi / istek limiti / arka plan) gorunur olur.
  /// Boylece "canli" iddiasi **saate** degil gercek istek zamanina bakar.
  static String dateTimeSeconds(DateTime? d) {
    if (d == null) return noData;
    final s = d.second.toString().padLeft(2, '0');
    return '${dateTime(d)}:$s';
  }

  /// "14:32"
  static String time(DateTime? d) {
    if (d == null) return noData;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "Salı" gibi gun etiketi.
  static String weekday(DateTime? d) {
    if (d == null) return noData;
    return _weekdays[d.weekday] ?? noData;
  }

  /// Gecen sureyi insan okunur bicimde: "3 dk once", "2 saat once".
  static String relativeTime(DateTime? d, {DateTime? now}) {
    if (d == null) return noData;
    final ref = now ?? DateTime.now();
    final diff = ref.difference(d);
    if (diff.isNegative) return dateTime(d);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    return date(d);
  }

  /// "02.10.2026"
  static String dateDot(DateTime? d) {
    if (d == null) return noData;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}
