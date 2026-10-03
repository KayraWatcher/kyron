import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../error/failures.dart';

/// Tum ag cagrilari uzerinden gecen tek nokta.
///
/// * Sure/asim yonetimi
/// * HTTP durum kodu -> [Failure] donusumu
/// * Ham exception'larin disari asla sizmamasi
///
/// Data Provider'lar bu sinifi kullanir; UI bunu asla gormez.
class ApiClient {
  ApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// GET istegi; yanit govdesini ham metin olarak dondurur.
  ///
  /// 4xx/5xx dahil tum HTTP durumlari [Result]a donusturulur; exception
  /// firlatilmaz.
  Future<Result<String>> getText(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? overrideTimeout,
  }) async {
    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(overrideTimeout ?? timeout);
      if (response.statusCode >= 400) {
        return Err(_statusToFailure(response.statusCode));
      }
      return Success(_decodeBody(response));
    } on TimeoutException {
      return const Err(TimeoutFailure());
    } on SocketException catch (e) {
      return Err(NetworkFailure('İnternet bağlantısı kurulamadı.', e));
    } on http.ClientException catch (e) {
      return Err(NetworkFailure('Ağ hatası oluştu.', e));
    } catch (e) {
      return Err(UnknownFailure('Beklenmeyen bir hata oluştu.', e));
    }
  }

  /// GET istegi; ham HTTP yanitini dondurur (durum koduna ihtiyac duyanlar icin).
  Future<Result<http.Response>> getRaw(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? overrideTimeout,
  }) async {
    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(overrideTimeout ?? timeout);
      if (response.statusCode >= 400) {
        return Err(_statusToFailure(response.statusCode));
      }
      return Success(response);
    } on TimeoutException {
      return const Err(TimeoutFailure());
    } on SocketException catch (e) {
      return Err(NetworkFailure('İnternet bağlantısı kurulamadı.', e));
    } on http.ClientException catch (e) {
      return Err(NetworkFailure('Ağ hatası oluştu.', e));
    } catch (e) {
      return Err(UnknownFailure('Beklenmeyen bir hata oluştu.', e));
    }
  }

  /// GET istegi; XML/RSS govdesi icin charset'e duyarli cozum.
  ///
  /// Cozum sirasi tum isteklerde ortaktir (bkz. [_decodeBody]): BOM ->
  /// sikisik UTF-8 -> aciklanan charset -> latin1.
  Future<Result<String>> getXmlText(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? overrideTimeout,
  }) async {
    final rawRes = await getRaw(uri, headers: headers, overrideTimeout: overrideTimeout);
    return rawRes.when(
      // Eski hata: her govde `utf8.decode(allowMalformed: false)` idi;
      // ISO-8859-9 / windows-1254 beslemede FormatException firlatiyordu.
      onSuccess: (response) => Success(_decodeBody(response)),
      onFailure: (f) => Err(f),
    );
  }

  // -------------------------------------------------------------------------
  // Charset cozumu
  // -------------------------------------------------------------------------

  /// Yanit govdesini charset'e gore dogru cozer; **asla firlatmaz**.
  ///
  /// Eski hata iki katli:
  ///  * `getXmlText` her govdeyi sikisik UTF-8 ile cozuyordu; tek bayt
  ///    kodlamada `FormatException` firlatiyordu (haber akisi dusuyordu).
  ///  * `getText` http paketinin `body` alanina birakiyordu; charset
  ///    **belirtilmemis** UTF-8 govde latin1'e cevrilirdi -> "GÜNLÜK"
  ///    mojibake.
  ///
  /// Siralama:
  ///  1. UTF-8 BOM
  ///  2. Sikisik UTF-8 (etiket hatali/eksik olsa bile dogru; tek bayt
  ///     kodlamalarda burada firlatilir)
  ///  3. Aciklanan charset (`Content-Type` -> XML declaration)
  ///  4. latin1 son care (tek bayt, firlatmaz)
  static String _decodeBody(http.Response response) {
    final bytes = response.bodyBytes;

    // 1) UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      try {
        return utf8.decode(bytes.sublist(3), allowMalformed: false);
      } on FormatException {
        // BOM var ama govde bozuk -> asagi duser.
      }
    }

    // 2) Sikisik UTF-8
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      // Tek bayt kodlama olabilir -> 3'e gec.
    }

    // 3) Aciklanan charset
    final decoded =
        _decodeDeclared(_declaredCharset(response, bytes), bytes);
    if (decoded != null) return decoded;

    // 4) Son care
    return latin1.decode(bytes);
  }

  /// Once `Content-Type` charset'i, yoksa XML declaration'i okur.
  static String? _declaredCharset(http.Response response, List<int> bytes) {
    final header = response.headers['content-type'] ?? '';
    // Not: Dart ham stringte `'` kacis kabul etmez; `\'` yerine regex'in
    // unicode kacisi (`\u0027`) kullanilir.
    final m = RegExp(r'charset\s*=\s*["\u0027]?([^;"\u0027\s]+)',
            caseSensitive: false)
        .firstMatch(header);
    if (m != null) return m.group(1);

    // XML declaration ilk ~256 bayttadir ve ASCII uyumludur.
    final head = latin1.decode(
      bytes.length > 256 ? bytes.sublist(0, 256) : bytes,
    );
    final xm = RegExp(r'encoding\s*=\s*["\u0027]([^"\u0027]+)',
            caseSensitive: false)
        .firstMatch(head);
    return xm?.group(1);
  }

  /// Aciklanan charset'i gercek kodlamaya cevirir; desteklenmiyorsa `null`.
  static String? _decodeDeclared(String? charset, List<int> bytes) {
    if (charset == null) return null;
    final n = charset.toLowerCase().trim().replaceAll('_', '-');
    if (n.isEmpty) return null;

    // Turkce tek bayt kodlamalari: latin1'den yalnizca 6 karakterle ayrilir
    // (Ğ İ Ş ğ ı ş). UTF-8 denemesi zaten basarisiz oldu.
    if (n == 'iso-8859-9' ||
        n == 'windows-1254' ||
        n == 'cp1254' ||
        n == 'turkish') {
      return _decodeTurkish1254(bytes);
    }
    if (n == 'utf-8' || n == 'utf8') return null; // 2. adimda denendi
    if (n == 'iso-8859-1' ||
        n == 'latin1' ||
        n == 'latin-1' ||
        n == 'windows-1252' ||
        n == 'cp1252') {
      return latin1.decode(bytes);
    }
    if (n == 'us-ascii' || n == 'ascii') {
      try {
        return ascii.decode(bytes);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// ISO-8859-9 / windows-1254 cozumu (latin1 + 6 Turkce karakter).
  static String _decodeTurkish1254(List<int> bytes) {
    const extra = <int, String>{
      0xD0: 'Ğ',
      0xDD: 'İ',
      0xDE: 'Ş',
      0xF0: 'ğ',
      0xFD: 'ı',
      0xFE: 'ş',
    };
    final base = latin1.decode(bytes);
    if (!base.runes.any(extra.containsKey)) return base;
    final sb = StringBuffer();
    for (final r in base.runes) {
      sb.write(extra[r] ?? String.fromCharCode(r));
    }
    return sb.toString();
  }

  Failure _statusToFailure(int status) {
    if (status >= 500) return ServerFailure('Sunucudan yanıt alınamadı. ($status)');
    if (status >= 400) return BadRequestFailure('İstek reddedildi. ($status)');
    return UnknownFailure('Beklenmeyen HTTP durumu: $status');
  }

  void dispose() => _client.close();
}
