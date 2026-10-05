// Anonim telemetri servisi testleri (FAZ 15).
//
// Kurallar:
//  * installation id ilk acilista uretilir, sonraki aciliste AYNI kalir.
//  * uygulama versiyonu pubspec'ten dogru okunur (1.0.0+1 -> "1.0.0+1").
//  * telemetri hatasi (offline/5xx) uygulamayi crash ettirmez; olay
//    basarisizsa sonraki aciliste tekrar denenir.
//  * ayni acilis penceresinde app_open SPAM'i yok (cooldown).
//  * yapilandirma yokken TEK BIR ag cagrisi bile yapilmaz.
//  * gonderilen payload anonimdir: yalnizca installation_id + platform +
//    versiyon + olay; kisisel veri/ek alan yok.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/telemetry/telemetry_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sabit/sanallaftirilan saat + yakalanan istekler.
class _Harness {
  _Harness(this.now);

  DateTime now;
  final requests = <http.Request>[];

  http.Response _responseFor(http.Request request) {
    requests.add(request);
    return http.Response('{}', 200);
  }

  TelemetryService serviceOn(
    SharedPreferences prefs, {
    String url = 'https://test-project.supabase.co',
    String anonKey = 'test-anon-key',
  }) {
    return TelemetryService(
      prefs: prefs,
      client: MockClient((request) async => _responseFor(request)),
      url: url,
      anonKey: anonKey,
      now: () => now,
    );
  }

  /// Ag hatasi ureten servis (offline benzeri).
  TelemetryService failingServiceOn(SharedPreferences prefs) {
    return TelemetryService(
      prefs: prefs,
      client: MockClient((_) async {
        throw const SocketException('ag yok');
      }),
      url: 'https://test-project.supabase.co',
      anonKey: 'test-anon-key',
      now: () => now,
    );
  }

  Map<String, dynamic>? bodyOf(int index) =>
      jsonDecode(utf8.decode(requests[index].bodyBytes))
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Harness h;

  setUp(() {
    h = _Harness(DateTime(2026, 10, 4, 12, 0));
    // Surum testleri icin pubspec'teki 1.0.0+1 bicimi taklit edilir.
    PackageInfo.setMockInitialValues(
      appName: 'KYRON',
      packageName: 'com.goldapp.gold',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  group('installation id', () {
    test('ilk acilista uuid uretilir ve prefs\'a yazilir', () async {
      final prefs = await freshPrefs();
      final svc = h.serviceOn(prefs);

      expect(svc.installationId, isNull, reason: 'once initialize edilmeli');
      await svc.initialize();

      final id = svc.installationId;
      expect(id, isNotNull);
      expect(
        id,
        matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        )),
        reason: 'anonim kurulum kimligi gecerli bir uuid olmali',
      );
      expect(prefs.getString(TelemetryService.installationIdKey), id);
    });

    test('sonraki aciliste AYNI id kullanilir (yeni uretilmez)', () async {
      final prefs = await freshPrefs();

      final first = h.serviceOn(prefs);
      await first.initialize();
      final id = first.installationId;

      // Uygulama kapatildi/acildi: yeni servis, ayni prefs.
      final second = h.serviceOn(prefs);
      await second.initialize();
      expect(second.installationId, id);

      // Ucuncu aciliste de ayni.
      final third = h.serviceOn(prefs);
      await third.initialize();
      expect(third.installationId, id);
    });
  });

  group('app version', () {
    test('pubspec surumu okunur: version + build', () async {
      final prefs = await freshPrefs();
      final svc = h.serviceOn(prefs);
      await svc.initialize();

      expect(svc.appVersion, '1.0.0+1');
    });

    test('gonderilen payload surumu dogru tasir', () async {
      final prefs = await freshPrefs();
      final svc = h.serviceOn(prefs);
      await svc.trackAppOpen();

      expect(h.requests, hasLength(1));
      expect(h.bodyOf(0)!['p_app_version'], '1.0.0+1');
    });
  });

  group('devre disi yapilandirma', () {
    test('url/anahtar yokken hicbir sey yapilmaz', () async {
      final prefs = await freshPrefs();
      final svc = TelemetryService(
        prefs: prefs,
        client: MockClient(
          (request) async =>
              fail('yaplandirma yokken ag cagrisi yapilmamali'),
        ),
        url: '',
        anonKey: '',
        now: () => h.now,
      );

      await svc.initialize();
      await svc.trackAppOpen();
      await svc.trackAppUpdate();
      await svc.updateLastSeen();

      expect(svc.enabled, isFalse);
      expect(svc.installationId, isNull, reason: 'pasifken kimlik uretilmez');
      expect(h.requests, isEmpty);
      expect(prefs.getString(TelemetryService.installationIdKey), isNull);
    });
  });

  group('app_open / olay onleme', () {
    test('ilk acilis tek app_open ping\'i gonderir; payload anonimdir',
        () async {
      final prefs = await freshPrefs();
      final svc = h.serviceOn(prefs);
      await svc.trackAppOpen();

      expect(h.requests, hasLength(1));
      final req = h.requests.single;
      expect(req.url.toString(),
          'https://test-project.supabase.co/rest/v1/rpc/telemetry_ping');
      expect(req.headers['apikey'], 'test-anon-key');

      final body = h.bodyOf(0)!;
      expect(
        body.keys.toSet(),
        {'p_installation_id', 'p_platform', 'p_app_version', 'p_event'},
        reason: 'gizlilik: ek alan gonderilmez (FAZ 13)',
      );
      expect(body['p_installation_id'], svc.installationId);
      expect(body['p_platform'], svc.platform);
      expect(body['p_event'], 'app_open');
    });

    test('ayni acilis penceresinde tekrar tekrar acil/kapat SPAM olmaz',
        () async {
      final prefs = await freshPrefs();
      final svc = h.serviceOn(prefs);

      await svc.trackAppOpen();
      await svc.trackAppOpen(); // ayni saniye
      await svc.trackAppOpen(); // hemen tekrar
      expect(h.requests, hasLength(1), reason: 'cooldown icinde tek ping');

      // Cooldown gecerli: 31 dk sonra yeni acilis sayilir.
      h.now = h.now.add(const Duration(minutes: 31));
      await svc.trackAppOpen();
      expect(h.requests, hasLength(2));
      expect(h.bodyOf(1)!['p_event'], 'app_open');
    });

    test('surum degisince app_update gonderilir ve yerel surum guncellenir',
        () async {
      final prefs = await freshPrefs();
      await prefs.setString(TelemetryService.installationIdKey, 'fixed-id');
      await prefs.setString(TelemetryService.lastVersionKey, '0.9.0');

      final svc = h.serviceOn(prefs);
      await svc.trackAppOpen();

      expect(h.requests, hasLength(1));
      final body = h.bodyOf(0)!;
      expect(body['p_event'], 'app_update');
      expect(body['p_installation_id'], 'fixed-id');
      expect(
        prefs.getString(TelemetryService.lastVersionKey),
        '1.0.0+1',
        reason: 'basarili gonderimden sonra surum kaydi guncellenmeli',
      );
    });

    test('updateLastSeen olaysiz gonderir ve throttle calisir', () async {
      final prefs = await freshPrefs();
      final svc = h.serviceOn(prefs);

      await svc.trackAppOpen(); // 1. ping (last_ping_ms yazar)
      await svc.updateLastSeen();
      expect(h.requests, hasLength(1), reason: 'throttle icinde tekrar yok');

      h.now = h.now.add(const Duration(minutes: 6));
      await svc.updateLastSeen();
      expect(h.requests, hasLength(2));
      expect(h.bodyOf(1)!.containsKey('p_event'), isFalse,
          reason: 'olaysiz ping olay alani tasimaz');
    });
  });

  group('hata dayanimi (FAZ 6)', () {
    test('ag hatasi crash ettirmez; olay kaybolmaz, sonraki aciliste tekrarlar',
        () async {
      final prefs = await freshPrefs();

      // 1. deneme: offline
      final offline = h.failingServiceOn(prefs);
      await offline.trackAppOpen(); // hata firlatmamali
      expect(prefs.getInt(TelemetryService.lastOpenEventMsKey), isNull,
          reason: 'basarisiz gonderimde olay sayaci ilerletilmez');

      // 2. deneme: sunucu 500
      var calls = 0;
      final serverErr = TelemetryService(
        prefs: prefs,
        client: MockClient((request) async {
          calls++;
          return http.Response('boom', 500);
        }),
        url: 'https://test-project.supabase.co',
        anonKey: 'test-anon-key',
        now: () => h.now,
      );
      await serverErr.trackAppOpen();
      expect(calls, 1);
      expect(prefs.getInt(TelemetryService.lastOpenEventMsKey), isNull);

      // 3. deneme: ag geri geldi -> ayni acilis yine gonderilir
      final online = h.serviceOn(prefs);
      await online.trackAppOpen();
      expect(h.requests, hasLength(1), reason: 'olay tekrar denenir');
      expect(
        prefs.getInt(TelemetryService.lastOpenEventMsKey),
        h.now.millisecondsSinceEpoch,
        reason: 'basarili gonderimdan sonra sayac yazar',
      );
    });

    test('servis yontemleri hic exception firlatmaz', () async {
      final prefs = await freshPrefs();
      final svc = h.failingServiceOn(prefs);

      await expectLater(svc.initialize(), completes);
      await expectLater(svc.trackAppOpen(), completes);
      await expectLater(svc.trackAppUpdate(), completes);
      await expectLater(svc.updateLastSeen(), completes);
    });
  });
}
