import 'dart:async';

import 'package:gold/core/error/failures.dart';
import 'package:gold/domain/entities/candle.dart';
import 'package:gold/domain/entities/quote.dart';
import 'package:gold/domain/repositories/market_data_repository.dart';

/// Testlerde kullanilan **fiyat deposu sahtesi**.
///
/// Gercek ag cikmaz; verilen quote haritasini dondurur. Mum desteği ve
/// akis varsayilan olarak "yok"tur (testler bunlari dogrulamaz).
class FakeMarketRepository implements MarketDataRepository {
  FakeMarketRepository({
    Map<String, Quote> quotes = const {},
    bool neverCompletes = false,
  })  : _quotes = quotes,
        _neverCompletes = neverCompletes;

  final Map<String, Quote> _quotes;

  /// `true` ise hicbir istek bitmez (loading durumu testleri icin).
  final bool _neverCompletes;

  final Completer<void> _pending = Completer<void>();

  @override
  Future<Result<Quote>> getQuote(String assetId) async {
    if (_neverCompletes) await _pending.future;
    final q = _quotes[assetId];
    if (q == null) return const Err(EmptyFailure('veri yok'));
    return Success(q);
  }

  @override
  Future<Result<Map<String, Quote>>> getQuotes(
    List<String> assetIds, {
    bool forceRefresh = false,
  }) async {
    if (_neverCompletes) await _pending.future;
    final out = <String, Quote>{
      for (final id in assetIds)
        if (_quotes.containsKey(id)) id: _quotes[id]!,
    };
    if (out.isEmpty) return const Err(EmptyFailure('veri yok'));
    return Success(out);
  }

  @override
  Duration refreshInterval(List<String> assetIds) =>
      const Duration(minutes: 1);

  @override
  Stream<Map<String, Quote>> watchQuotes(
    List<String> assetIds, {
    Duration? interval,
    bool Function()? isActive,
  }) =>
      const Stream<Map<String, Quote>>.empty();

  @override
  Future<Result<CandleSeries>> getCandles({
    required String assetId,
    required ChartInterval interval,
    int limit = 300,
    bool forceRefresh = false,
  }) async =>
      const Err(EmptyFailure('mum yok'));

  @override
  void invalidateQuotes() {}

  @override
  void invalidateCandles() {}
}
