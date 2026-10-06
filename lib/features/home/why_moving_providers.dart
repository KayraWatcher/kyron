import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../domain/entities/asset_catalog.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/news/news_impact.dart';
import '../../domain/repositories/market_data_repository.dart';

/// Kanit turunu. Yalnizca **gercekten veri varsa** uretilir.
///
/// (Ikonlar bilerek burada degil, kart katmaninda tutulur; bu dosya
/// saf veri/logic katmanidir.)
enum WhyEvidenceKind {
  /// Bilesenlerin (ons altin, USD/TRY ...) fiyat hareketi.
  piyasaHareketi('Piyasa Hareketi'),

  /// Varlikla iliskili guncel haber.
  haber('Haber'),

  /// Ekonomik veri / politika haberi.
  ekonomikVeri('Ekonomik Veri'),

  /// Merkez bankasi haberi.
  merkezBankasi('Merkez Bankası'),

  /// Sirket / sektor haberi.
  sirketHaberi('Şirket / Sektör');

  const WhyEvidenceKind(this.label);

  final String label;

  /// Haber kategorisinden kanit turunu (haber kategorisi = kanit sinifi).
  static WhyEvidenceKind fromNewsCategory(NewsCategory c) => switch (c) {
        NewsCategory.merkezBankasi => WhyEvidenceKind.merkezBankasi,
        NewsCategory.dunyaEkonomisi => WhyEvidenceKind.ekonomikVeri,
        NewsCategory.ekonomi => WhyEvidenceKind.ekonomikVeri,
        NewsCategory.sirketler => WhyEvidenceKind.sirketHaberi,
        _ => WhyEvidenceKind.haber,
      };
}

/// Tek bir kanit satiri.
class WhyEvidence {
  const WhyEvidence({
    required this.kind,
    required this.headline,
    this.detail,
    this.sourceName,
    this.newsUrl,
  });

  final WhyEvidenceKind kind;

  /// Ana metin: orn. "Ons Altın -0,34%" veya haber basligi.
  final String headline;

  /// Ikincil metin (bilesen adi, haber kaynagi vb.).
  final String? detail;

  /// Haber kaynagi (yalnizca haber kanitinda).
  final String? sourceName;

  /// Haber linki (varsa dokunulabilir).
  final String? newsUrl;
}

/// "Neden Hareket Ediyor?" verisi.
///
/// **Yalnizca kanit varsa doludur.** Kanit yoksa [evidences] bos olur ve
/// arayuz bu bolumu **hic gostermez** (bos kutu / "veri yok" yazisi yoktur).
class WhyMovingData {
  const WhyMovingData({required this.assetId, this.evidences = const []});

  final String assetId;
  final List<WhyEvidence> evidences;

  /// Kanit var mi? (Kartin gorunurlugu bununla belirlenir.)
  bool get hasEvidence => evidences.isNotEmpty;
}

/// Bir varlik icin "Neden Hareket Ediyor?" kanit toplayan saglayici.
///
/// **Katmanlar (yalnizca dogrulanabilir veri):**
///  1. **Piyasa Hareketi** - varligin bilesenlerinin (parents) gercek fiyat
///     degisimleri. Gram altin gibi bilesenden hesaplanan varliklarda bu
///     gercek bir ayrimdir; dogrudan kaynakli varliklarda (ons altin,
///     USD/TRY ...) bileseni olmadigi icin bu katman **bos** kalir.
///  2. **Haber / Ekonomik Veri / Merkez Bankasi / Sirket** - varlikla (veya
///     bilesenleriyle) [NewsImpact] kurallarina gore iliskili, son 48 saatte
///     yayimlanmis haberler.
///
/// **Uydurma yapilmaz:** haber ya da fiyat hareketi yoksa liste bos doner.
final whyMovingProvider = FutureProvider.autoDispose
    .family<WhyMovingData, String>((ref, assetId) async {
  final asset = AssetCatalog.byId(assetId);
  if (asset == null) return WhyMovingData(assetId: assetId);

  final evidences = <WhyEvidence>[];

  // ---- 1) Piyasa hareketi (bilesenler) ----
  if (asset.parentIds.isNotEmpty) {
    final repo = ref.watch(marketRepositoryProvider);
    final ids = <String>[assetId, ...asset.parentIds];
    final quotes = await repo.getQuotes(ids);
    quotes.when(
      onSuccess: (map) {
        final main = map[assetId]?.effectiveChangePercent;
        // Bilesenlerin mutlak degisimi, ana varliktan buyukse aciklanabilir.
        final moves = <(String, double)>[];
        for (final parentId in asset.parentIds) {
          final pct = map[parentId]?.effectiveChangePercent;
          if (pct == null || pct.abs() < 0.05) continue;
          moves.add((AssetCatalog.byId(parentId)?.name ?? parentId, pct));
        }
        if (moves.isEmpty) return;
        moves.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
        final top = moves.take(2).toList();
        evidences.add(WhyEvidence(
          kind: WhyEvidenceKind.piyasaHareketi,
          headline: top.first.$1,
          detail: '${_signed(top.first.$2)}'
              '${top.length > 1 ? ' · ${top[1].$1} ${_signed(top[1].$2)}' : ''}',
        ));
        // Ana varligin kendi hareketi de kayit altindadir (bilesen degilse
        // de bilgi kaybi olmasin).
        if (main != null && main.abs() >= 0.5 && moves.length < 2) {
          evidences.add(WhyEvidence(
            kind: WhyEvidenceKind.piyasaHareketi,
            headline: asset.name,
            detail: _signed(main),
          ));
        }
      },
      onFailure: (_) {},
    );
  }

  // ---- 2) Haber kaniti ----
  try {
    final newsRepo = ref.watch(newsRepositoryProvider);
    final res = await newsRepo.getNews(limit: 120);
    res.when(
      onSuccess: (items) {
        // Varlik + bilesenleri: haber bu id'lerden biriyle iliskiliyse kanittir.
        final targets = <String>{assetId, ...asset.parentIds};
        final cutoff = DateTime.now().subtract(const Duration(hours: 48));
        final found = <WhyEvidence>[];
        for (final item in items) {
          if (item.publishedAt.isBefore(cutoff)) continue;
          final related = NewsImpact.linksFor(item)
              .where((l) => targets.contains(l.assetId))
              .toList();
          if (related.isEmpty) continue;
          found.add(WhyEvidence(
            kind: WhyEvidenceKind.fromNewsCategory(item.category),
            headline: item.title,
            detail: item.source,
            sourceName: item.source,
            newsUrl: item.url,
          ));
          if (found.length >= 2) break;
        }
        evidences.addAll(found);
      },
      onFailure: (_) {},
    );
  } catch (_) {
    // Haber kaynagi erisilemezse kanit uretilmez (sessizce atlanir).
  }

  return WhyMovingData(assetId: assetId, evidences: evidences);
});

String _signed(double pct) {
  final s = pct.toStringAsFixed(2);
  return pct > 0 ? '%+$s' : '%$s';
}
