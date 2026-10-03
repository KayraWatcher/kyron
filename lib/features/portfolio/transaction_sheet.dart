import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/tr_format.dart';
import '../../domain/entities/portfolio.dart';
import 'portfolio_providers.dart';

/// Yeni islem ekleme formu.
Future<void> showTransactionSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const Padding(
      padding: EdgeInsets.only(bottom: 0),
      child: SingleChildScrollView(child: _TransactionForm()),
    ),
  );
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm();

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  final _formKey = GlobalKey<FormState>();

  String? _assetId;
  bool _isSell = false;
  DateTime _date = DateTime.now();

  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _feeCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    _feeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = ref.watch(portfolioAssetOptionsProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'İşlem Ekle',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),

            // Al/Sat
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Alış')),
                ButtonSegment(value: true, label: Text('Satış')),
              ],
              selected: {_isSell},
              onSelectionChanged: (s) => setState(() => _isSell = s.first),
            ),
            const SizedBox(height: 16),

            // Varlik
            DropdownButtonFormField<String>(
              initialValue: _assetId,
              decoration: const InputDecoration(labelText: 'Varlık'),
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o.id, child: Text(o.name)),
              ],
              validator: (v) => v == null ? 'Varlık seçin' : null,
              onChanged: (v) => setState(() => _assetId = v),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityCtrl,
                    decoration: const InputDecoration(labelText: 'Miktar'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: _validatePositive('Miktar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Birim Fiyat (TL)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: _validatePositive('Fiyat', allowZero: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _feeCtrl,
                    decoration: const InputDecoration(labelText: 'Komisyon (TL)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: (v) {
                      final n = _parse(v);
                      if (n == null) return 'Geçerli girin';
                      if (n < 0) return 'Negatif olamaz';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tarih'),
                      child: Text(TrFormat.dateDot(_date)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Not (isteğe bağlı)',
              ),
              maxLength: 120,
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: Text(_isSell ? 'Satış Kaydet' : 'Alış Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? Function(String?) _validatePositive(String label,
      {bool allowZero = false}) {
    return (v) {
      final n = _parse(v);
      if (n == null) return 'Geçerli bir $label girin';
      if (allowZero ? n < 0 : n <= 0) {
        return allowZero ? 'Negatif olamaz' : '$label sıfırdan büyük olmalı';
      }
      return null;
    };
  }

  /// Tek noktadan sayi ayrıştırma (`"1.5"` artık 15 değil 1.5 olur).
  double? _parse(String? raw) =>
      raw == null ? null : TrFormat.parse(raw);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final assetId = _assetId;
    if (assetId == null) return;

    final qty = _parse(_quantityCtrl.text)!;
    final price = _parse(_priceCtrl.text)!;
    final fee = _parse(_feeCtrl.text) ?? 0;

    final t = PortfolioTransaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      assetId: assetId,
      quantity: qty,
      price: price,
      date: _date,
      fee: fee,
      isSell: _isSell,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    if (!t.isValid) {
      _showSnack('İşlem bilgileri geçersiz.');
      return;
    }

    await ref.read(portfolioProvider.notifier).add(t);
    if (mounted) {
      Navigator.of(context).pop();
      _showSnack(_isSell ? 'Satış kaydedildi.' : 'Alış kaydedildi.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
