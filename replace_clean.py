# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the QuoteCard build method (from @override to before _priceText)
idx = content.find('  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);', 9600)
method_end = content.find('\n  String _priceText', idx)
old_build = content[idx:method_end]

new_build = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = AssetCatalog.byId(assetId);
    final changePercent = quote.effectiveChangePercent;
    final directionColor = AppPalette.direction(changePercent);

    if (isGrid) {
      return _buildGridCard(context, theme, asset, directionColor, changePercent);
    }

    // LIST MODE: [AssetIdentity] [Price + Change] [Sparkline]
    final showSpread = this.showSpread && (quote.bid != null || quote.ask != null);

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
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AssetIdentity(
                      assetId: assetId,
                      subtitle: quote.source.label,
                      freshness: quote.freshness,
                      isStale: quote.isStale,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Fiyat metni asla "12.2..." gibi kirpilmaz;
                        // sinirlanmis kartta FittedBox ile kucultulur.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _priceText(asset, quote),
                            maxLines: 1,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
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
                  Sparkline(
                    data: sparkline,
                    color: directionColor,
                    width: 60,
                    height: 30,
                  ),
                ],
              ),
              if (showSpread) ...[
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
              // UST: Asset adi + sembol + WatchStar
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

              // ORTA: Sparkline (tam genislik)
              if (hasSparkline) ...[
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

              // ALT: Fiyat + % Degisim (saga hizali)
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
  }'''

# Read content
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the exact old build
idx = content.find('  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);', 9600)
old_build = content[idx:content.find('\n  String _priceText', idx)]

if old_build in content:
    content = content.replace(old_build, new_build)
    with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS: Replaced build method')
else:
    print('OLD BUILD NOT FOUND')
    # Write actual for comparison
    idx = content.find('  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);', 9600)
    actual = content[idx:content.find('\n  String _priceText', idx)]
    with open('actual_found.txt', 'w', encoding='utf-8') as f:
        f.write(content[idx:content.find('\n  String _priceText', idx)])
    print('Written actual to actual_found.txt')
    print('Length:', len(actual))