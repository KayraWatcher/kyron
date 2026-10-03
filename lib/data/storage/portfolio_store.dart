import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/portfolio.dart';

/// Portfoy islemlerini yerelde saklar.
///
/// Depolama JSON string olarak yapilir; bozuk/kismi kayitlar sessizce
/// atlanir (uygulama asla cop veri gostermez).
class PortfolioStore {
  PortfolioStore(this._prefs);

  static const String _key = 'portfolio.transactions';

  final SharedPreferences _prefs;

  List<PortfolioTransaction> load() {
    try {
      final raw = _prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final out = <PortfolioTransaction>[];
      for (final e in decoded) {
        final t = _fromJson(e);
        if (t != null && t.isValid) out.add(t);
      }
      return out;
    } catch (_) {
      // Bozuk kayit: guvenli sekilde bos don.
      return const [];
    }
  }

  Future<bool> save(List<PortfolioTransaction> transactions) async {
    try {
      final list = transactions.where((t) => t.isValid).map(_toJson).toList();
      return await _prefs.setString(_key, jsonEncode(list));
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _toJson(PortfolioTransaction t) => {
        'id': t.id,
        'assetId': t.assetId,
        'quantity': t.quantity,
        'price': t.price,
        'date': t.date.toIso8601String(),
        'fee': t.fee,
        'isSell': t.isSell,
        if (t.note != null && t.note!.isNotEmpty) 'note': t.note,
      };

  PortfolioTransaction? _fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();

    final id = m['id'];
    final assetId = m['assetId'];
    final quantity = m['quantity'];
    final price = m['price'];
    final dateRaw = m['date'];

    if (id is! String || id.isEmpty) return null;
    if (assetId is! String || assetId.isEmpty) return null;
    if (quantity is! num || price is! num) return null;

    DateTime? date;
    if (dateRaw is String) date = DateTime.tryParse(dateRaw);
    if (date == null) return null;

    return PortfolioTransaction(
      id: id,
      assetId: assetId,
      quantity: quantity.toDouble(),
      price: price.toDouble(),
      date: date,
      fee: m['fee'] is num ? (m['fee'] as num).toDouble() : 0,
      isSell: m['isSell'] == true,
      note: m['note'] is String ? m['note'] as String? : null,
    );
  }
}
