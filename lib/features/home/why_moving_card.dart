import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/navigator_utils.dart';
import 'why_moving_providers.dart';

/// "Neden Hareket Ediyor?" bölümü.
///
/// **Görünürlük kuralı:** kanıt yoksa bölüm **hiç gösterilmez** - boş kutu,
/// "veri yok", "kanıt bulunamadı" gibi yer tutucu metinler yoktur. Yalnızca
/// gerçek fiyat hareketi veya varlıkla ilişkili güncel haber bulunduğunda
/// görünür.
///
/// **Kanıt türleri (dinamik):** Piyasa Hareketi · Haber · Ekonomik Veri ·
/// Merkez Bankası · Şirket / Sektör - yalnızca o türden kanıt varsa o başlık
/// görünür.
///
/// **Dil:** etki kesin değildir; "etkileyebilir", "ilişkili olabilir" gibi
/// temkinli ifadeler kullanılır. Yatırım tavsiyesi değildir.
class WhyMovingCard extends ConsumerWidget {
  const WhyMovingCard({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(whyMovingProvider(assetId));

    return async.when(
      data: (data) {
        // Kanıt yoksa HİÇBİR ŞEY gösterme.
        if (!data.hasEvidence) return const SizedBox.shrink();
        return _EvidenceCard(data: data);
      },
      // Yükleniyor/hata durumunda da kutu gösterilmez (yer tutucu yasak).
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.data});

  final WhyMovingData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Kanıtları türe göre grupla (gruplama sırası: piyasa → ekonomi → haber).
    final groups = <WhyEvidenceKind, List<WhyEvidence>>{};
    for (final e in data.evidences) {
      groups.putIfAbsent(e.kind, () => []).add(e);
    }
    const order = [
      WhyEvidenceKind.piyasaHareketi,
      WhyEvidenceKind.merkezBankasi,
      WhyEvidenceKind.ekonomikVeri,
      WhyEvidenceKind.sirketHaberi,
      WhyEvidenceKind.haber,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Neden Hareket Ediyor?',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Aşağıdaki başlıklar yalnızca doğrulanabilir veri içerir; '
            'haber etkisi kesin değildir.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.neutral,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),
          for (final kind in order)
            if (groups[kind] != null) ...[
              _EvidenceGroupHeader(kind: kind),
              const SizedBox(height: 4),
              for (final e in groups[kind]!) _EvidenceLine(evidence: e),
              const SizedBox(height: 6),
            ],
          const SizedBox(height: 2),
          Text(
            'Bu bölüm mevcut piyasa verisi ve güncel haberlerden türetilir; '
            'yatırım tavsiyesi değildir.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.neutral,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(WhyEvidenceKind kind) => switch (kind) {
      WhyEvidenceKind.piyasaHareketi => Icons.show_chart_rounded,
      WhyEvidenceKind.merkezBankasi => Icons.account_balance_outlined,
      WhyEvidenceKind.ekonomikVeri => Icons.analytics_outlined,
      WhyEvidenceKind.sirketHaberi => Icons.business_center_outlined,
      WhyEvidenceKind.haber => Icons.article_outlined,
    };

/// Türkçeye duyarlı büyük harf dönüşümü.
///
/// Dart'ın `toUpperCase()` fonksiyonu noktasız 'ı' harfini ASCII 'I' yapar ve
/// 'i' harfini 'İ' yapmaz; başlıklar yanlış görünürdü ("PIYASA" / "HAREKETI").
String _trUpper(String value) =>
    value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

class _EvidenceGroupHeader extends StatelessWidget {
  const _EvidenceGroupHeader({required this.kind});

  final WhyEvidenceKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(_iconFor(kind), size: 14, color: AppPalette.goldDeep),
        const SizedBox(width: 6),
        Text(
          _trUpper(kind.label),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 0.4,
            color: AppPalette.goldDeep,
          ),
        ),
      ],
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({required this.evidence});

  final WhyEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = evidence.newsUrl;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  evidence.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              if (url != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          if (evidence.detail != null && evidence.detail!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                evidence.detail!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.neutral,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );

    if (url == null) return content;
    return InkWell(
      onTap: () => launchNewsUrl(url),
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}
