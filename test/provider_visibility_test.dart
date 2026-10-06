import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/providers/app_providers.dart';
import 'package:gold/domain/entities/asset.dart';
import 'package:gold/domain/entities/asset_catalog.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/features/markets/markets_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_market_repository.dart';

/// **Provider gizliligi** testleri.
///
/// Kural: kullanici arayuzunde veri saglayicisi adi **gorunmez**.
/// "CanlıDöviz", "Gold API", "Yahoo", "TCMB", "Frankfurter", "Anlık Altın
/// Fiyatları" gibi teknik adlar yalnizca kod icinde kalir; fallback zinciri
/// aynen calismaya devam eder, sadece **adi** arayuze cikmaz.
void main() {
  const banned = [
    'CanlıDöviz',
    'Canlidoviz',
    'Gold API',
    'Yahoo',
    'TCMB',
    'Frankfurter',
    'Anlık Altın Fiyatları',
    'Veri kaynakları',
  ];

  test('kullaniciya donuk UI dosyalarinda provider adi bulunmaz', () {
    final dir = Directory('lib');
    final offenders = <String>[];

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll('\\', '/');
      // Yalnizca **gorunen metin** taranir: provider siniflari ve yorumlar
      // iceride kalabilir (mimari + dokumantasyon icin).
      if (rel.contains('/providers/') || rel.contains('/canlidoviz/')) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trim();
        if (t.startsWith('//') ||
            t.startsWith('*') ||
            t.startsWith('import ')) {
          continue;
        }
        for (final name in banned) {
          if (t.contains(name)) offenders.add('$rel:${i + 1}: $t');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'UI dosyalarinda provider adi gorunmemeli:\n'
          '${offenders.join('\n')}',
    );
  });

  /// Ekranin normal (dolu) durumunu test etmek icin tum katalog icin fiyat.
  Map<String, Quote> _filledQuotes() {
    return {
      for (final a in AssetCatalog.all)
        a.id: Quote(
          assetId: a.id,
          source: QuoteSourceLabel.market,
          updatedAt: DateTime(2026, 10, 6, 12),
          price: 100,
          currency: a.currency,
          changePercent: 0.5,
        ),
    };
  }

  testWidgets('Piyasalar ekraninda kaynak bolumu YOK', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketRepositoryProvider
              .overrideWithValue(FakeMarketRepository(quotes: _filledQuotes())),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MarketsScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Veri kaynakları'), findsNothing);
    expect(find.textContaining('Yedek kaynaklar'), findsNothing);
    expect(find.textContaining('WebSocket'), findsNothing);
    expect(find.textContaining('TCMB'), findsNothing);
    expect(find.textContaining('Yahoo'), findsNothing);
  });

  test('Kripto kategorisi katalogda ve Piyasalar listesi kapsaminda', () {
    expect(AssetCategory.values.map((c) => c.label), contains('Kripto'));
    expect(AssetCategory.values, hasLength(6)); // borsa, altin, gumus, doviz, kripto, emtia
    final kripto = AssetCatalog.byCategory(AssetCategory.kripto);
    expect(kripto, isNotEmpty);
    expect(kripto.map((a) => a.id), contains(AssetCatalog.bitcoinId));
  });
}
