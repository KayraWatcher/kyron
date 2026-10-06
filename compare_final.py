# -*- coding: utf-8 -*-
import sys

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Get the actual current method (from 9659 to before _priceText)
actual = content[9659:content.find('\n  String _priceText', 9659)]

# Expected old build (from reference)
expected = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    // Düzen: [SOL sparkline] [ORTA varlık adı] [SAĞ fiyat + değişim]
    final rowChildren = <Widget>[];

    // SOL: Mini sparkline / hareket grafiği
    if (sparkline?.isValid == true) {
      rowChildren.add(
        Sparkline(
          data: sparkline,
          color: directionColor,
          width: 48,
          height: 28,
        ),
      );
      rowChildren.add(const SizedBox(width: 12));
    }

    // ORTA: varlık adı + sembol/kaynak (fiyat saga tasindi)
    rowChildren.add(
      Expanded(
        flex: 2,
        child: AssetIdentity(
          assetId: assetId,
          subtitle: quote.source.label,
          freshness: quote.freshness,
          isStale: quote.isStale,
        ),
      ),
    )

    // SAĞ: fiyat + gunluk degisim (saga hizali, gereksiz bosluk birakmaz).
    // FlexFit.tight + FittedBox: dar kartta fiyat+degisim **birlikte**
    // kuculur (ChangeBadge asla tasmaz), genis kartta blok sag kenara
    // yapisir; bosluk kalmaz.
    rowChildren.add(const SizedBox(width: 10))
    rowChildren.add(
      Flexible(
        flex: 3,
        fit: FlexFit.tight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _priceText(asset, quote),
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 4),
              ChangeBadge(
                value: changePercent,
                percent: true,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    )

    // Alış/satım ana satirin DISINDA, kartin alt satirinda gosterilir:
    // Row disi cocuklar sinirsiz (unbounded) ana eksen kisiti alir; Expanded
    // icerik bu sinirda patlar. Column altinda genislik kart genisligiyle
    // sinirli oldugundan guvenlidir.
    final showBidAsk = showSpread && (quote.bid != null || quote.ask != null)

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            // Dar yukseklikli grid hucrelerde icerik dikey ortalanir;
            // liste gorunumunde (sinirsiz yukseklik) davranis degismez.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rowChildren,
              ),
              if (showBidAsk) ...[
                const SizedBox(height: 10),
                _BidAskRow(quote: quote),
              ],
            ],
          ),
        ),
      ),
    )
  }'''

# Read current file
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Get actual method
actual = content[9659:content.find('\n  String _priceText', 9659)]
expected = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    // Düzen: [SOL sparkline] [ORTA varlık adı] [SAĞ fiyat + değişim]
    final rowChildren = <Widget>[];

    // SOL: Mini sparkline / hareket grafiği
    if (sparkline?.isValid == true) {
      rowChildren.add(
        Sparkline(
          data: sparkline,
          color: directionColor,
          width: 48,
          height: 28,
        ),
      );
      rowChildren.add(const SizedBox(width: 12));
    }

    // ORTA: varlık adı + sembol/kaynak (fiyat saga tasindi)
    rowChildren.add(
      Expanded(
        flex: 2,
        child: AssetIdentity(
          assetId: assetId,
          subtitle: quote.source.label,
          freshness: quote.freshness,
          isStale: quote.isStale,
        ),
      ),
    )

    // SAĞ: fiyat + gunluk degisim (saga hizali, gereksiz bosluk birakmaz).
    // FlexFit.tight + FittedBox: dar kartta fiyat+degisim **birlikte**
    // kuculur (ChangeBadge asla tasmaz), genis kartta blok sag kenara
    // yapisir; bosluk kalmaz.
    rowChildren.add(const SizedBox(width: 10))
    rowChildren.add(
      Flexible(
        flex: 3,
        fit: FlexFit.tight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _priceText(asset, quote),
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 4),
              ChangeBadge(
                value: changePercent,
                percent: true,
                compact: true,
              ),
            ],
          ),
        ),
      ),
    )

    // Alış/satım ana satirin DISINDA, kartin alt satirinda gosterilir:
    // Row disi cocuklar sinirsiz (unbounded) ana eksen kisiti alir; Expanded
    // icerik bu sinirda patlar. Column altinda genislik kart genisligiyle
    // sinirli oldugundan guvenlidir.
    final showBidAsk = showSpread && (quote.bid != null || quote.ask != null)

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            // Dar yukseklikli grid hucrelerde icerik dikey ortalanir;
            // liste gorunumunde (sinirsiz yukseklik) davranis degismez.
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rowChildren,
              ),
              if (showBidAsk) ...[
                const SizedBox(height: 10),
                _BidAskRow(quote: quote),
              ],
            ],
          ),
        ),
      ),
    )
  }'''

# Read full content
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Get actual method (from 9659 to before _priceText)
actual = content[9659:content.find('\n  String _priceText', 9659)]

# Expected (with @override)
expected_with_override = '  @override\n' + expected

# Write both for comparison
with open('actual.txt', 'w', encoding='utf-8') as f:
    f.write(actual)

with open('expected.txt', 'w', encoding='utf-8') as f:
    f.write(expected)

# Compare
actual_method = actual
expected_method = expected

print('Actual length:', len(actual_method))
print('Expected length:', len(expected_method))

if actual_method == expected_method:
    print('MATCH!')
else:
    print('MISMATCH')
    # Find first difference
    for i, (a, e) in enumerate(zip(actual_method, expected_method)):
        if a != e:
            print(f'First diff at pos {i}: actual={repr(a)}, expected={repr(e)}')
            print(f'Context actual: {repr(actual_method[max(0,i-20):i+20])}')
            print(f'Context expected: {repr(expected_method[max(0,i-20):i+20])}')
            break
    if len(actual_method) != len(expected_method):
        print(f'Length diff: actual={len(actual_method)}, expected={len(expected_method)}')