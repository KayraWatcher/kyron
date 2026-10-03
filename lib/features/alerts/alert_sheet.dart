import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/entities/price_alert.dart';
import '../asset_detail/asset_detail_providers.dart';
import 'alert_providers.dart';

/// Yeni alarm olusturma sayfasi.
///
/// [assetId] verilirse yalnizca o varliga bagli alarmlar, verilmezse
/// "Onemli haber" alarma izin verilir.
Future<void> showAlertSheet(
  BuildContext context, {
  String? assetId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AlertSheet(assetId: assetId),
  );
}

class _AlertSheet extends ConsumerStatefulWidget {
  const _AlertSheet({this.assetId});

  final String? assetId;

  @override
  ConsumerState<_AlertSheet> createState() => _AlertSheetState();
}

class _AlertSheetState extends ConsumerState<_AlertSheet> {
  late AlertType _type;
  final _thresholdCtrl = TextEditingController();
  final _percentCtrl = TextEditingController();
  AlertDirection _direction = AlertDirection.above;
  NewsCategory? _newsCategory;
  bool _repeat = false;
  String? _error;
  bool _prefilledThreshold = false;

  bool get _assetMode => widget.assetId != null;

  List<AlertType> get _types => _assetMode
      ? const [
          AlertType.priceAbove,
          AlertType.priceBelow,
          AlertType.percentChange,
          AlertType.dayHigh,
          AlertType.dayLow,
        ]
      : const [AlertType.importantNews];

  @override
  void initState() {
    super.initState();
    _type = _types.first;
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assetId = widget.assetId;
    final asset = assetId == null ? null : AssetCatalog.byId(assetId);

    // Mevcut fiyati on dolu goster - kullanici sifirdan yazmak zorunda kalmasin.
    if (assetId != null) {
      final price = ref.watch(assetQuoteProvider(assetId)).value?.price;
      if (price != null && price.isFinite && !_prefilledThreshold) {
        _prefilledThreshold = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _thresholdCtrl.text.isEmpty) {
            _thresholdCtrl.text = TrFormat.money(price);
          }
        });
      }
    }

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Alarm oluştur',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (asset != null) ...[
                const SizedBox(height: 2),
                Text(
                  asset.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),

              // ---- Tur ----
              Text('Koşul',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _types)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() {
                        _type = t;
                        _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- Alana gore alanlar ----
              if (_type == AlertType.priceAbove ||
                  _type == AlertType.priceBelow) ...[
                _numberField(
                  theme,
                  controller: _thresholdCtrl,
                  label: 'Hedef fiyat (TL)',
                  hint: 'Örn. 3.500,00',
                ),
              ] else if (_type == AlertType.percentChange) ...[
                Text('Yön',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                SegmentedButton<AlertDirection>(
                  segments: [
                    for (final d in AlertDirection.values)
                      ButtonSegment(value: d, label: Text(d.label)),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) =>
                      setState(() => _direction = s.first),
                ),
                const SizedBox(height: 12),
                _numberField(
                  theme,
                  controller: _percentCtrl,
                  label: 'Değişim oranı (%)',
                  hint: 'Örn. 2,5',
                ),
              ] else if (_type == AlertType.dayHigh ||
                  _type == AlertType.dayLow) ...[
                Text(
                  'Günün en yüksek / en düşük seviyesi kaynaktan alınır; '
                  'burada ek değer girilmez.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.neutral, height: 1.5),
                ),
              ] else if (_type == AlertType.importantNews) ...[
                Text('Haber kategorisi',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<NewsCategory?>(
                  initialValue: _newsCategory,
                  items: [
                    const DropdownMenuItem<NewsCategory?>(
                      value: null,
                      child: Text('Tüm kategoriler'),
                    ),
                    for (final c in NewsCategory.values)
                      DropdownMenuItem<NewsCategory?>(
                        value: c,
                        child: Text(c.label),
                      ),
                  ],
                  onChanged: (v) => setState(() => _newsCategory = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Yalnizca kaynakta gorunen yeni basliklar icin bildirim '
                  'gonderilir; mevcut haberler icin bildirim gonderilmez.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.neutral, height: 1.5),
                ),
              ],

              const SizedBox(height: 16),
              SwitchListTile(
                value: _repeat,
                contentPadding: EdgeInsets.zero,
                title: const Text('Koşul her sağlanınca yeniden bildir'),
                subtitle: Text(
                  'Kapalıyken alarm bir kez çalar ve kendiliğinden pasifleşir.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.neutral),
                ),
                onChanged: (v) => setState(() => _repeat = v),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppPalette.loss),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Alarmı oluştur'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bildirimler yalnizca bu cihazda, yerel olarak gonderilir. '
                'Hesap veya sunucu kaydi yoktur.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppPalette.neutral, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            // Turkce girdi: virgul ve nokta kabul edilir.
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
          ),
        ),
      ],
    );
  }

  void _save() {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final alert = switch (_type) {
      AlertType.priceAbove || AlertType.priceBelow => PriceAlert(
          type: _type,
          assetId: widget.assetId,
          threshold: _parse(_thresholdCtrl.text),
          direction: _direction,
          repeat: _repeat,
        ),
      AlertType.percentChange => PriceAlert(
          type: _type,
          assetId: widget.assetId,
          percent: _parse(_percentCtrl.text),
          direction: _direction,
          repeat: _repeat,
        ),
      AlertType.dayHigh || AlertType.dayLow => PriceAlert(
          type: _type,
          assetId: widget.assetId,
          repeat: _repeat,
        ),
      AlertType.importantNews => PriceAlert(
          type: _type,
          newsCategory: _newsCategory?.name,
          repeat: true,
        ),
    };

    if (!alert.isValid) {
      setState(() => _error = 'Alarm tanımı geçersiz.');
      return;
    }

    ref.read(alertsProvider.notifier).add(alert);
    Navigator.of(context).pop();
  }

  String? _validate() {
    switch (_type) {
      case AlertType.priceAbove:
      case AlertType.priceBelow:
        final v = _parse(_thresholdCtrl.text);
        if (v == null) return 'Lütfen geçerli bir hedef fiyat girin.';
        if (v <= 0) return 'Hedef fiyat sıfırdan büyük olmalı.';
        return null;
      case AlertType.percentChange:
        final v = _parse(_percentCtrl.text);
        if (v == null) return 'Lütfen geçerli bir oran girin.';
        if (v <= 0) return 'Oran sıfırdan büyük olmalı.';
        if (v > 100) return '%100\'den büyük oran girilemez.';
        return null;
      case AlertType.dayHigh:
      case AlertType.dayLow:
      case AlertType.importantNews:
        return null;
    }
  }

  /// "3.500,50" / "3500.50" / "3500,50" / "1.5" hepsi kabul edilir.
  /// Ayrıştırma tek noktada (`TrFormat.parse`): eski kural "1.5" girdisini
  /// 15 yapıyordu.
  double? _parse(String raw) => TrFormat.parse(raw);
}
