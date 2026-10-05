import 'package:xml/xml.dart';

import '../../core/error/failures.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/news_item.dart';
import '../../domain/providers/news_provider.dart';

/// RSS beslemesi kaynagi.
class RssFeed {
  const RssFeed({
    required this.url,
    required this.defaultCategory,
    required this.sourceName,
    this.categoryMap = const {},
  });

  final Uri url;
  final NewsCategory defaultCategory;
  final String sourceName;

  /// RSS'teki bolum adi -> [NewsCategory] eslesmesi.
  final Map<String, NewsCategory> categoryMap;
}

/// Acik RSS beslemelerinden haber ceken provider.
///
/// **Telif:** Yalnizca `<title>`, `<description>` (ozet), `<pubDate>`,
/// `<link>`, `<guid>` ve `<image>` alanlari okunur. Haber metninin
/// tamami asla istenmez, okunmaz veya depolanmaz.
///
/// AA (Anadolu Ajansi) RSS beslemesi - yalnizca baslik/ozet/kaynak/zaman/
/// kategori/gorsel tasir, tam metin degil.
class NewsRssProvider implements NewsProvider {
  NewsRssProvider(this._client, {List<RssFeed>? feeds})
      : feeds = feeds ?? defaultFeeds;

  final ApiClient _client;
  final List<RssFeed> feeds;

  @override
  String get id => 'aa-rss';

  @override
  String get displayName => 'Anadolu Ajansı';

  /// Anadolu Ajansi ekonomi - dogrulanmis, calisan besleme.
  static final RssFeed aaEkonomi = RssFeed(
    url: Uri.parse('https://www.aa.com.tr/tr/rss/default?cat=ekonomi'),
    defaultCategory: NewsCategory.ekonomi,
    sourceName: 'Anadolu Ajansı',
    categoryMap: const {
      'Borsa': NewsCategory.borsa,
      'Döviz': NewsCategory.doviz,
      'Altın': NewsCategory.altin,
      'Merkez Bankası': NewsCategory.merkezBankasi,
      'Ekonomi': NewsCategory.ekonomi,
    },
  );

  static final List<RssFeed> defaultFeeds = [aaEkonomi];

  /// Bir beslemeyi cekip normalize eder.
  Future<Result<List<NewsItem>>> fetchFeed(RssFeed feed, {int limit = 30}) async {
    final res = await _client.getXmlText(
      feed.url,
      headers: const {'Accept': 'application/rss+xml, application/xml, text/xml'},
      overrideTimeout: const Duration(seconds: 15),
    );

    return res.when(
      onSuccess: (body) => _parse(body, feed, limit),
      onFailure: (f) => Err(f),
    );
  }

  /// Tum beslemeleri paralel ceker; tek besleme hatali olsa bile
  /// digerlerinin sonucunu kaybetmeyiz.
  @override
  Future<Result<List<NewsItem>>> fetchAll({int limit = 30}) async {
    final responses = await Future.wait(
      feeds.map((f) => fetchFeed(f, limit: limit)),
    );

    final items = <NewsItem>[];
    Failure? lastFailure;
    var ok = false;

    for (final r in responses) {
      if (r case Success(data: final list)) {
        ok = true;
        items.addAll(list);
      } else {
        lastFailure = r.failureOrNull ?? lastFailure;
      }
    }

    if (!ok) return Err(lastFailure ?? const NetworkFailure());

    // En yeni en ustte, tekrar eden id'leri ayikla.
    final seen = <String>{};
    final deduped = <NewsItem>[];
    for (final item in items) {
      if (seen.add(item.id)) deduped.add(item);
    }
    deduped.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    if (deduped.isEmpty) return const Err(EmptyFailure());
    return Success(deduped.take(limit).toList());
  }

  Result<List<NewsItem>> _parse(String body, RssFeed feed, int limit) {
    try {
      final doc = XmlDocument.parse(body);
      final items = doc.findAllElements('item');
      final result = <NewsItem>[];

      for (final item in items) {
        final title = _text(item, 'title');
        final link = _text(item, 'link');
        if (title == null || link == null) continue;

        final guid = _text(item, 'guid') ?? link;
        final published = _parseDate(_text(item, 'pubDate'));
        if (published == null) continue;

        final description = _text(item, 'description');
        final imageUrl = _extractImage(item) ?? _extractMediaThumb(item);

        result.add(NewsItem(
          id: guid,
          title: _clean(title),
          source: feed.sourceName,
          publishedAt: published,
          category: _mapCategory(item, feed),
          url: link,
          summary: description == null ? null : _clean(description),
          imageUrl: imageUrl,
        ));

        if (result.length >= limit) break;
      }

      if (result.isEmpty) return const Err(EmptyFailure());
      return Success(result);
    } catch (e) {
      return Err(ParseFailure('Veri okunamadı.', e));
    }
  }

  NewsCategory _mapCategory(XmlElement item, RssFeed feed) {
    // AA beslemesinde kategori <category> etiketinde gelir.
    final raw = _text(item, 'category');
    if (raw != null) {
      final mapped = feed.categoryMap[raw] ?? NewsCategory.fromLabel(raw);
      if (mapped != null) return mapped;
    }
    return feed.defaultCategory;
  }

  String? _extractImage(XmlElement item) {
    // RSS 2.0 + enclosure, ya da description icindeki ilk <img src>.
    for (final enc in item.findAllElements('enclosure')) {
      final url = enc.getAttribute('url');
      final type = enc.getAttribute('type') ?? '';
      if (url != null && type.startsWith('image')) return url;
    }
    final content = item.getElement('content');
    final contentUrl = content?.getAttribute('url');
    if (contentUrl != null && contentUrl.startsWith('http')) return contentUrl;

    final desc = _text(item, 'description');
    if (desc != null) {
      final match = RegExp(r'<img[^>]+src="([^"]+)"').firstMatch(desc);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? _extractMediaThumb(XmlElement item) {
    for (final el in item.childElements) {
      if (el.name.local.contains('thumbnail') || el.name.local.contains('image')) {
        // Yaygin bicim 1: <media:thumbnail url="https://..." />
        final url = el.getAttribute('url');
        if (url != null && url.startsWith('http')) return url;
        // Yaygin bicim 2 (AA RSS): <image>https://...jpg</image> -
        // URL oznitelik degil, **metin** olarak gelir.
        final text = el.innerText.trim();
        if (text.startsWith('http')) return text;
      }
    }
    return null;
  }

  String? _text(XmlElement parent, String name) {
    for (final el in parent.childElements) {
      if (el.name.local == name) {
        final t = el.innerText.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    // RFC 822: "Fri, 02 Oct 2026 14:32:09 +0300" (+03:00 / -0500 de olur)
    //
    // Eski hata iki katliydi:
    //  * `raw.replaceAll(' +0300', ' +0300')` **hicbir sey yapmiyordu**
    //    (ayni metnin kendisiyle degistirme) - saat ofseti hic okunmuyordu,
    //  * ofset yok sayilip saat **cihaz yerel zamani** saniliyordu; cihaz
    //    UTC'de oldugunda haber "2-3 saat yanlis" gorunuyordu.
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final m = RegExp(
      r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})'
      r'\s*(?:([+-])(\d{2}):?(\d{2})|(GMT|UT))?',
    ).firstMatch(raw);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = months[m.group(2)];
    final year = int.tryParse(m.group(3)!);
    final hour = int.tryParse(m.group(4) ?? '') ?? 0;
    final minute = int.tryParse(m.group(5) ?? '') ?? 0;
    final second = int.tryParse(m.group(6) ?? '') ?? 0;
    if (day == null || month == null || year == null) return null;

    // Ofset: sadece rakamlar varsa yorumlanir; "GMT"/"UT" ya da ofset
    // yoksa RFC 822'de oldugu gibi UTC kabul edilir.
    var offsetMinutes = 0;
    final sign = m.group(7);
    if (sign != null) {
      final oh = int.tryParse(m.group(8) ?? '') ?? 0;
      final om = int.tryParse(m.group(9) ?? '') ?? 0;
      offsetMinutes = (sign == '-' ? -1 : 1) * (oh * 60 + om);
    }

    final asUtc = DateTime.utc(year, month, day, hour, minute, second);
    // Gercek an (epoch) korunur; gosterim icin cihaz yereline cevrilir.
    // Not: Dart 3.13'te parametre adi `isUtc`; varsayilan zaten yerel.
    return DateTime.fromMillisecondsSinceEpoch(
      asUtc.millisecondsSinceEpoch - offsetMinutes * 60000,
    );
  }

  /// HTML etiketlerini temizler ve varliklari kisaltir.
  String _clean(String input) {
    var s = input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length > 400) s = '${s.substring(0, 397)}...';
    return s;
  }
}
