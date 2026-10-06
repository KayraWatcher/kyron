# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the exact current method (from @override to before _priceText)
idx = content.find('  @override\n  Widget build(BuildContext context) {', 9600)
method_end = content.find('\n  String _priceText', 9600)
actual = content[idx:content.find('\n  String _priceText', 9600)]

print('Actual length:', len(actual))

# The difference is at pos 977: actual has ';' but expected has '\n'
# Let's write the exact old build with the semicolon
old_build = content[content.find('  @override\n  Widget build(BuildContext context) {', 9600):content.find('\n  String _priceText', 9600)]

print('Old build length:', len(old_build))

# Write old build to file for verification
with open('old_build_exact.txt', 'w', encoding='utf-8') as f:
    f.write(old_build)
print('Written old_build_exact.txt')

# Now define new build
new_build = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    if (isGrid) {
      return _buildGridCard(context, theme, asset, directionColor, changePercent);
    }

    // LIST MODE: [SOL sparkline] [ORTA varlık adı] [SAĞ fiyat + değişim]
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
    rowChildren.add(const SizedBox(width: 10));
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
    );

    // Alış/satım ana satirin DISINDA, kartin alt satirinda gosterilir:
    // Row disi cocuklar sinirsiz (unbounded) ana eksen kisiti alir; Expanded
    // icerik bu sinirda patlar. Column altinda genislik kart genisligiyle
    // sinirli oldugundan guvenlidir.
    final showBidAsk = showSpread && (quote.bid != null || quote.ask != null);

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
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    ThemeData theme,
    AssetDescriptor? asset,
    Color directionColor,
    double? changePercent,
  ) {
    final hasSparkline = sparkline?.isValid == true;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ÜST: Asset adı + sembol + WatchStar
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset?.name ?? assetId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (asset != null) ...[
                              Flexible(
                                child: Text(
                                  asset.symbol,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              if (asset.isCalculated) ...[
                                const SizedBox(width: 4),
                                _CalculatedBadge(label: asset.category.label),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),

              const SizedBox(height: 8),

              // ORTA: Sparkline (tam genişlik)
              if (sparkline?.isValid == true) ...[
                SizedBox(
                  height: 36,
                  child: Sparkline(
                    data: sparkline!,
                    color: directionColor,
                    width: double.infinity,
                    height: 36,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ALT: Fiyat + % Değişim (sağa hizalı)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _priceText(asset, quote),
                            maxLines: 1,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        ChangeBadge(
                          value: changePercent,
                          percent: true,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }"""

# Read full content
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Get the exact old build (from @override to before _priceText)
idx = content.find('  @override\n  Widget build(BuildContext context) {', 9600)
old_build = content[idx:content.find('\n  String _priceText', 9600)]

new_build = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    if (isGrid) {
      return _buildGridCard(context, theme, asset, directionColor, changePercent);
    }

    // LIST MODE: [SOL sparkline] [ORTA varlık adı] [SAĞ fiyat + değişim]
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
    rowChildren.add(const SizedBox(width: 10));
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
    );

    // Alış/satım ana satirin DISINDA, kartin alt satirinda gosterilir:
    // Row disi cocuklar sinirsiz (unbounded) ana eksen kisiti alir; Expanded
    // icerik bu sinirda patlar. Column altinda genislik kart genisligiyle
    // sinirli oldugundan guvenlidir.
    final showBidAsk = showSpread && (quote.bid != null || quote.ask != null);

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
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    ThemeData theme,
    AssetDescriptor? asset,
    Color directionColor,
    double? changePercent,
  ) {
    final hasSparkline = sparkline?.isValid == true;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ÜST: Asset adı + sembol + WatchStar
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset?.name ?? assetId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (asset != null) ...[
                              Flexible(
                                child: Text(
                                  asset.symbol,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              if (asset.isCalculated) ...[
                                const SizedBox(width: 4),
                                _CalculatedBadge(label: asset.category.label),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),

              const SizedBox(height: 8),

              // ORTA: Sparkline (tam genişlik)
              if (sparkline?.isValid == true) ...[
                SizedBox(
                  height: 36,
                  child: Sparkline(
                    data: sparkline!,
                    color: directionColor,
                    width: double.infinity,
                    height: 36,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ALT: Fiyat + % Değişim (sağa hizalı)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _priceText(asset, quote),
                            maxLines: 1,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        ChangeBadge(
                          value: changePercent,
                          percent: true,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }"""

# Read content
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Get exact old build
idx = content.find('  @override\n  Widget build(BuildContext context) {', 9600)
old_build = content[idx:content.find('\n  String _priceText', 9600)]

new_build = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    if (isGrid) {
      return _buildGridCard(context, theme, asset, directionColor, changePercent);
    }

    // LIST MODE: [SOL sparkline] [ORTA varlık adı] [SAĞ fiyat + değişim]
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
    rowChildren.add(const SizedBox(width: 10));
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
    );

    // Alış/satım ana satirin DISINDA, kartin alt satirinda gosterilir:
    // Row disi cocuklar sinirsiz (unbounded) ana eksen kisiti alir; Expanded
    // icerik bu sinirda patlar. Column altinda genislik kart genisligiyle
    // sinirli oldugundan guvenlidir.
    final showBidAsk = showSpread && (quote.bid != null || quote.ask != null);

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
    );
  }

  Widget _buildGridCard(
    BuildContext context,
    ThemeData theme,
    AssetDescriptor? asset,
    Color directionColor,
    double? changePercent,
  ) {
    final hasSparkline = sparkline?.isValid == true;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ÜST: Asset adı + sembol + WatchStar
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset?.name ?? assetId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (asset != null) ...[
                              Flexible(
                                child: Text(
                                  asset.symbol,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              if (asset.isCalculated) ...[
                                const SizedBox(width: 4),
                                _CalculatedBadge(label: asset.category.label),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),

              const SizedBox(height: 8),

              // ORTA: Sparkline (tam genişlik)
              if (sparkline?.isValid == true) ...[
                SizedBox(
                  height: 36,
                  child: Sparkline(
                    data: sparkline!,
                    color: directionColor,
                    width: double.infinity,
                    height: 36,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ALT: Fiyat + % Değişim (sağa hizalı)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _priceText(asset, quote),
                            maxLines: 1,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        ChangeBadge(
                          value: changePercent,
                          percent: true,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }"""

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find exact old build
idx = content.find('  @override\n  Widget build(BuildContext context) {', 9600)
old_build = content[idx:content.find('\n  String _priceText', 9600)]

# Read the file content
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

if old_build in content:
    content = content.replace(old_build, new_build)
    with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS: Replaced build method')
else:
    print('OLD BUILD NOT FOUND')
    # Write actual for comparison
    idx = content.find('  @override\n  Widget build(BuildContext context) {', 9600)
    actual = content[idx:content.find('\n  String _priceText', 9600)]
    with open('actual_found.txt', 'w', encoding='utf-8') as f:
        f.write(content[idx:content.find('\n  String _priceText', 9600)])
    print('Written actual to actual_found.txt')