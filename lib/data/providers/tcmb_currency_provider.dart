import 'package:xml/xml.dart';

import '../../core/error/failures.dart';
import '../../core/network/api_client.dart';

/// TCMB serbest piyasa kuru kaydi.
class TcmbRate {
  const TcmbRate({
    required this.code,
    required this.name,
    this.forexBuying,
    this.forexSelling,
    this.banknoteBuying,
    this.banknoteSelling,
  });

  final String code;
  final String name;
  final double? forexBuying;
  final double? forexSelling;
  final double? banknoteBuying;
  final double? banknoteSelling;

  /// Serbest piyasa alis (efektif/alış).
  double? get buying => forexBuying ?? banknoteBuying;

  /// Serbest piyaka satis (efektif/satış).
  double? get selling => forexSelling ?? banknoteSelling;

  /// Makas (satış - alış).
  double? get spread {
    final b = buying;
    final s = selling;
    if (b == null || s == null) return null;
    final v = s - b;
    return v.isFinite ? v : null;
  }

  /// Kapanis/son deger olarak ortalama; makas gosterimi icin.
  double? get mid {
    final b = buying;
    final s = selling;
    if (b == null || s == null) return null;
    final v = (b + s) / 2;
    return v.isFinite ? v : null;
  }

  bool get hasData => buying != null || selling != null;
}

/// TCMB gunluk kurlar XML beslemesi.
///
/// Kaynak: https://www.tcmb.gov.tr/kurlar/today.xml
/// Ucretsiz, anahtarsiz, kamuya acik resmi kaynak.
class TcmbCurrencyProvider {
  TcmbCurrencyProvider(this._client, {Uri? endpoint})
      : _endpoint = endpoint ?? Uri.parse('https://www.tcmb.gov.tr/kurlar/today.xml');

  final ApiClient _client;
  final Uri _endpoint;

  /// Bugunku tum kurlari cekip kod -> [TcmbRate] olarak dondurur.
  Future<Result<Map<String, TcmbRate>>> fetchToday() async {
    final res = await _client.getText(
      _endpoint,
      headers: const {'Accept': 'application/xml'},
      overrideTimeout: const Duration(seconds: 12),
    );
    return res.when(
      onSuccess: _parse,
      onFailure: (f) => Err(f),
    );
  }

  /// Istenen kodlar icin kurlari ceker.
  Future<Result<Map<String, TcmbRate>>> fetchCurrencies(
    Set<String> codes,
  ) async {
    final all = await fetchToday();
    return all.when(
      onSuccess: (map) {
        final filtered = <String, TcmbRate>{};
        for (final c in codes) {
          final r = map[c];
          if (r != null) filtered[c] = r;
        }
        if (filtered.isEmpty) {
          return const Err(EmptyFailure('İstenen para birimleri bulunamadı.'));
        }
        return Success(filtered);
      },
      onFailure: (f) => Err(f),
    );
  }

  Result<Map<String, TcmbRate>> _parse(String body) {
    try {
      final doc = XmlDocument.parse(body);
      final result = <String, TcmbRate>{};

      for (final node in doc.findAllElements('Currency')) {
        final code = node.getAttribute('Kod');
        if (code == null || code.isEmpty) continue;

        result[code] = TcmbRate(
          code: code,
          name: _textOf(node, 'Isim') ?? code,
          forexBuying: _doubleOf(node, 'ForexBuying'),
          forexSelling: _doubleOf(node, 'ForexSelling'),
          banknoteBuying: _doubleOf(node, 'BanknoteBuying'),
          banknoteSelling: _doubleOf(node, 'BanknoteSelling'),
        );
      }

      if (result.isEmpty) {
        return const Err(ParseFailure('Kur verisi boş döndü.'));
      }
      return Success(result);
    } catch (e) {
      return Err(ParseFailure('Veri okunamadı.', e));
    }
  }

  String? _textOf(XmlElement parent, String name) {
    final el = parent.getElement(name);
    final t = el?.innerText.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  double? _doubleOf(XmlElement parent, String name) {
    final t = _textOf(parent, name);
    if (t == null) return null;
    final v = double.tryParse(t);
    return (v != null && v.isFinite && v > 0) ? v : null;
  }
}
