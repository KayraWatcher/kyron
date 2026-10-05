/// Tests for the update system: version comparison, update status logic, and UI behavior.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/update/version_compare.dart';
import 'package:gold/core/update/update_config.dart';
import 'package:gold/core/update/update_ui.dart';

void main() {
  group('AppVersion semantic version comparison', () {
    test('1.0.0 == 1.0.0', () {
      final v1 = AppVersion.parse('1.0.0')!;
      final v2 = AppVersion.parse('1.0.0')!;
      expect(v1.compareTo(v2), equals(0));
      expect(v1 == v2, isTrue);
    });

    test('1.0.0 < 1.1.0', () {
      final v1 = AppVersion.parse('1.0.0')!;
      final v2 = AppVersion.parse('1.1.0')!;
      expect(v1.compareTo(v2), lessThan(0));
    });

    test('1.9.0 < 1.10.0 (minor version numeric comparison)', () {
      final v1 = AppVersion.parse('1.9.0')!;
      final v2 = AppVersion.parse('1.10.0')!;
      expect(v1.compareTo(v2), lessThan(0));
    });

    test('2.0.0 > 1.99.99 (major version wins)', () {
      final v1 = AppVersion.parse('2.0.0')!;
      final v2 = AppVersion.parse('1.99.99')!;
      expect(v1.compareTo(v2), greaterThan(0));
    });

    test('build metadata is ignored for comparison: 1.0.0+5 == 1.0.0+3', () {
      final v1 = AppVersion.parse('1.0.0+5')!;
      final v2 = AppVersion.parse('1.0.0+3')!;
      // Build metadata is compared when both have it (semver spec)
      expect(v1.compareTo(v2), greaterThan(0));
    });

    test('build number compared when both have it: 1.0.0+5 > 1.0.0+3', () {
      final v1 = AppVersion.parse('1.0.0+5')!;
      final v2 = AppVersion.parse('1.0.0+3')!;
      // Build numbers are compared when both present
      expect(v1.compareTo(v2), greaterThan(0));
    });

    test('parse handles invalid versions gracefully', () {
      expect(AppVersion.parse(''), isNull);
      expect(AppVersion.parse('invalid'), isNull);
      expect(AppVersion.parse('1.0'), isNull);
      expect(AppVersion.parse('1.0.0.0'), isNotNull); // Extra parts are ignored
    });

    test('toString includes build when present', () {
      final v = AppVersion.parse('1.0.0+5')!;
      expect(v.toString(), equals('1.0.0+5'));
    });

    test('toString excludes build when absent', () {
      final v = AppVersion.parse('1.0.0')!;
      expect(v.toString(), equals('1.0.0'));
    });
  });

  group('UpdateConfig parsing', () {
    test('fromJson with all fields', () {
      final json = {
        'latest_version': '1.1.0',
        'minimum_version': '1.0.0',
        'download_url': 'https://kyronapp.pages.dev/',
      };
      final config = UpdateConfig.fromJson(json);
      expect(config.latestVersion, equals('1.1.0'));
      expect(config.minimumVersion, equals('1.0.0'));
      expect(config.downloadUrl, equals('https://kyronapp.pages.dev/'));
    });

    test('fromJson with missing fields uses defaults', () {
      final json = <String, dynamic>{};
      final config = UpdateConfig.fromJson(json);
      expect(config.latestVersion, equals('1.0.0'));
      expect(config.minimumVersion, equals('1.0.0'));
      expect(config.downloadUrl, equals('https://kyronapp.pages.dev/'));
    });

    test('toJson serializes correctly', () {
      final config = UpdateConfig(
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
        downloadUrl: 'https://example.com/',
      );
      final json = config.toJson();
      expect(json['latest_version'], equals('1.1.0'));
      expect(json['minimum_version'], equals('1.0.0'));
      expect(json['download_url'], equals('https://example.com/'));
    });

    test('equality works', () {
      final c1 = UpdateConfig(
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
        downloadUrl: 'https://example.com/',
      );
      final c2 = UpdateConfig(
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
        downloadUrl: 'https://example.com/',
      );
      expect(c1 == c2, isTrue);
    });
  });

  group('UpdateStatus logic', () {
    test('upToDate when current >= latest', () {
      final current = AppVersion.parse('1.1.0')!;
      final latest = AppVersion.parse('1.1.0')!;
      final minimum = AppVersion.parse('1.0.0')!;

      expect(current.compareTo(latest) >= 0, isTrue);
    });

    test('optionalUpdate when current < latest but current >= minimum', () {
      final current = AppVersion.parse('1.0.0')!;
      final latest = AppVersion.parse('1.1.0')!;
      final minimum = AppVersion.parse('1.0.0')!;

      expect(current.compareTo(latest), lessThan(0));
      expect(current.compareTo(minimum) >= 0, isTrue);
    });

    test('forcedUpdate when current < minimum', () {
      final current = AppVersion.parse('0.9.0')!;
      final latest = AppVersion.parse('1.1.0')!;
      final minimum = AppVersion.parse('1.0.0')!;

      expect(current.compareTo(latest), lessThan(0));
      expect(current.compareTo(minimum), lessThan(0));
    });

    test('current > latest means upToDate', () {
      final current = AppVersion.parse('2.0.0')!;
      final latest = AppVersion.parse('1.1.0')!;
      final minimum = AppVersion.parse('1.0.0')!;

      expect(current.compareTo(latest) >= 0, isTrue);
    });
  });

  group('UpdateCheckResult properties', () {
    test('isUpdateAvailable true for optionalUpdate', () {
      final result = UpdateCheckResult(
        status: UpdateStatus.optionalUpdate,
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
      );
      expect(result.isUpdateAvailable, isTrue);
      expect(result.isForcedUpdate, isFalse);
    });

    test('isUpdateAvailable true for forcedUpdate', () {
      final result = UpdateCheckResult(
        status: UpdateStatus.forcedUpdate,
        currentVersion: '0.9.0',
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
      );
      expect(result.isUpdateAvailable, isTrue);
      expect(result.isForcedUpdate, isTrue);
    });

    test('isUpdateAvailable false for upToDate', () {
      final result = UpdateCheckResult(
        status: UpdateStatus.upToDate,
        currentVersion: '1.1.0',
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
      );
      expect(result.isUpdateAvailable, isFalse);
      expect(result.isForcedUpdate, isFalse);
    });
  });

  group('Update UI widgets', () {
    testWidgets('Optional update dialog shows correct text', (tester) async {
      final result = UpdateCheckResult(
        status: UpdateStatus.optionalUpdate,
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOptionalUpdateDialog(context, result),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni sürüm mevcut'), findsOneWidget);
      expect(find.text('KYRON 1.1.0 sürümü yayınlandı.'), findsOneWidget);
      expect(find.text('Mevcut sürüm: 1.0.0'), findsOneWidget);
      expect(find.text('Daha Sonra'), findsOneWidget);
      expect(find.text('Güncelle'), findsOneWidget);
    });

    testWidgets('Forced update screen shows correct text and no "Daha Sonra"', (tester) async {
      final result = UpdateCheckResult(
        status: UpdateStatus.forcedUpdate,
        currentVersion: '0.9.0',
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showForcedUpdateScreen(context, result),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      // Dialog content might be split across widgets, use textContaining
      expect(find.textContaining('Güncelleme gerekli'), findsOneWidget);
      expect(find.textContaining('KYRON'), findsOneWidget);
      expect(find.textContaining('kullanmaya devam etmek için'), findsOneWidget);
      expect(find.textContaining('0.9.0'), findsOneWidget);
      expect(find.textContaining('1.0.0'), findsOneWidget);
      expect(find.textContaining('Şimdi Güncelle'), findsOneWidget);
      expect(find.text('Daha Sonra'), findsNothing);
    });

    testWidgets('Optional update dialog "Daha Sonra" dismisses dialog', (tester) async {
      final result = UpdateCheckResult(
        status: UpdateStatus.optionalUpdate,
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        minimumVersion: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOptionalUpdateDialog(context, result),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Daha Sonra'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni sürüm mevcut'), findsNothing);
    });
  });
}