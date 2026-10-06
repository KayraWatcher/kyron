// Diagnostik - Piyasalar > Döviz: QuoteCard alış/satış (spread) düzeni.
//
// Cihazda raporlanan hata:
//   1) Döviz kategorisinde kartlar **bos** gorunuyordu (icerik hic
//      layoutlanamiyordu),
//   2) kategori degistirilince kirmizi ekran:
//      `_dependents.isEmpty` kaskad hatasi.
//
// Kok neden: `_BidAskRow` (icinde `Expanded` olan bir Row) dogrudan kartin
// ana Row cocugu olarak eklenmisti. Row disi cocuklar ana eksende **sinirsiz
// (unbounded)** kisit alir; "non-zero flex but unbounded constraints" hatasi
// tüm kartin layout'unu patlatir. Duzeltme: alis/satir satiri Column altinda,
// kart genisligiyle sinirli ikinci satir olarak gosterilir.
//
// Bu test dar (330px) ve genis kartlarda istisna/taşma olmadigini ve
// Alış/Satış/Makas iceriginin gorunur oldugunu dogrular.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gold/domain/entities/data_freshness.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/shared/widgets/quote_card.dart';
import 'package:gold/shared/widgets/quote_compact_row.dart';

Quote _usdQuote() => Quote(
      assetId: 'usd-try',
      source: QuoteSourceLabel.market,
      updatedAt: DateTime(2026, 10, 4, 10, 0),
      price: 49.01,
      bid: 48.98,
      ask: 49.04,
      previousClose: 48.96,
      change: 0.05,
      changePercent: 0.10,
      currency: 'TRY',
      freshness: DataFreshness.daily,
    );

void main() {
  testWidgets(
      'QuoteCard (showSpread) dar kartta Alış/Satış gösterir, istisna yok',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Piyasalar listesi gibi sinirli genislikte ListView icinde.
          body: Center(
            child: SizedBox(
              width: 330,
              child: ListView(
                children: [
                  QuoteCard(
                    assetId: 'usd-try',
                    quote: _usdQuote(),
                    showSpread: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Alış'), findsOneWidget);
    expect(find.text('Satış'), findsOneWidget);
    expect(find.text('Makas'), findsOneWidget);
    // Fiyat metni de layoutlanir (bos kart degil).
    expect(find.textContaining('49,01'), findsWidgets);
  });

  testWidgets('QuoteCard (showSpread) sabit yukseklikli grid hucresinde de',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 150,
              child: QuoteCard(
                assetId: 'usd-try',
                quote: _usdQuote(),
                showSpread: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Alış'), findsOneWidget);
    expect(find.text('Satış'), findsOneWidget);
  });

  testWidgets('QuoteCard spread olmadiginda (Home) tek satir duzeni bozulmaz',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 330,
              child: QuoteCard(
                assetId: 'usd-try',
                quote: _usdQuote(),
                // Home kartinda alis/satir gosterilmez (showSpread=false).
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Alış'), findsNothing);
    expect(find.textContaining('49,01'), findsWidgets);
  });

  testWidgets('QuoteCompactRow (showSpread) Alış/Satış ile taşmasız',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 330,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QuoteCompactRow(
                    assetId: 'usd-try',
                    quote: _usdQuote(),
                    showSpread: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Al'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
  });
}
