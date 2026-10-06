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
/// **Coklu kaynak:** tek beslemeye bagimli degildir. Varsayilan olarak
/// Anadolu Ajansi, Bloomberg HT, Foreks, Ekonomim ve Sabah beslemeleri
/// **paralel ve bagimsiz** cekilir; biri hata/timeout/429 aldiginda
/// digerlerinin sonucu kaybolmaz.
///
/// **Telif:** Yalnizca `<title>`, `<description>` (ozet), `<pubDate>`,
/// `<link>`, `<guid>` ve `<image>` alanlari okunur. Haber metninin
/// tamami asla istenmez, okunmaz veya depolanmaz.
class NewsRssProvider implements NewsProvider {
  NewsRssProvider(this._client, {List<RssFeed>? feeds})
      : feeds = feeds ?? defaultFeeds;

  final ApiClient _client;
  final List<RssFeed> feeds;

  @override
  String get id => 'aa-rss';

  @override
  String get displayName => 'RSS Beslemeleri (çoklu kaynak)';

  /// Tum beslemeleri **paralel ve bagimsiz** ceker.
  ///
  /// Hata izolasyonu:
  ///  * Her besleme kendi try/caku icinde calisir ([_fetchFeedIsolated]);
  ///    bir besleme firlaticak olsa bile `Future.wait` tumunu iptal etmez.
  ///  * En az **bir** besleme basariliysa sonuc `Success` doner; hatali
  ///    beslemeler yalnizca `lastFailure` olarak taşınir.
  ///  * Hepsi hataliysa son hata doner (arayuz `Err` bekler) - ancak
  ///    repository onbellekteki son gecerli haberleri geri sunar.
  ///  * `limit` besleme sayisina degil **toplam** haber sayisina uygulanir.
  @override
  Future<Result<List<NewsItem>>> fetchAll({int limit = 30}) async {
    final responses = await Future.wait(
      feeds.map((f) => _fetchFeedIsolated(f, limit: limit)),
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

    // 1) En yeni en ustte.
    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    // 2) Kaynaklar-arasi tekrar eden haberleri azalt (ayni id, ayni baslik
    //    ya da basligin uzatilmis hali).
    final deduped = deduplicate(items);

    if (deduped.isEmpty) return const Err(EmptyFailure());
    return Success(deduped.take(limit).toList());
  }

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

  // ---------------------------------------------------------------------------
  // IKINCI KAYNAKLAR
  //
  // Tek kaynaga bagimlilik kaldirilir. Her besleme **bagimsiz** cekilir;
  // biri hata/timeout/429 aldiginda digerleri sonucunu kaybetmez.
  //
  // Secim kriterleri (hepsi yasam testi ile dogrulandi):
  //  * RSS 2.0 + `title`/`link`/`pubDate` alani mevcut
  //    (mevcut [NewsRssProvider._parse] birebir calisir),
  //  * RFC 822 tarih bicimi (var olan [_parseDate] ile uyumlu),
  //  * ucretsiz, anahtarsiz, resmi RSS,
  //  * tazelik: en yeni haber 0,1 - 5 saat arasinda.
  //
  // Not: Hürriyet/Milliyet/NTV/Investing denendi ama **elendi**:
  //  * Hürriyet ekonomi beslemesi 2 yillik "nasil yapilir" yazilari donduruyor,
  //  * Milliyet `<link>` yerine `atom:link` atiyor (mevcut ayristirici atlar),
  //  * NTV Atom biciminde, Investing tarihi RFC 822 disi.
  // ---------------------------------------------------------------------------

  /// Bloomberg HT - Turk finans medyasi, ~50 guncel haber (RSS 2.0).
  static final RssFeed bloombergHt = RssFeed(
    url: Uri.parse('https://www.bloomberght.com/rss'),
    defaultCategory: NewsCategory.ekonomi,
    sourceName: 'Bloomberg HT',
    categoryMap: const {'Haberler': NewsCategory.ekonomi},
  );

  /// Foreks (ForInvest) - Turk finansal veri/takuas ajansi, ~100 guncel haber.
  static final RssFeed foreks = RssFeed(
    url: Uri.parse('https://www.foreks.com/rss/haberler.xml'),
    defaultCategory: NewsCategory.ekonomi,
    sourceName: 'Foreks',
    categoryMap: const {'Economy': NewsCategory.ekonomi},
  );

  /// Ekonomim - Turk ekonomi gazetesi, ~25 guncel haber.
  static final RssFeed ekonomim = RssFeed(
    url: Uri.parse('https://www.ekonomim.com/rss/ekonomi.xml'),
    defaultCategory: NewsCategory.ekonomi,
    sourceName: 'Ekonomim',
  );

  /// Sabah Ekonomi - ~10 guncel ekonomi haberi (kategori etiketi ile gelir).
  static final RssFeed sabahEkonomi = RssFeed(
    url: Uri.parse('https://www.sabah.com.tr/rss/ekonomi.xml'),
    defaultCategory: NewsCategory.ekonomi,
    sourceName: 'Sabah',
    categoryMap: const {'Ekonomi': NewsCategory.ekonomi},
  );

  /// Aktif beslemeler. Sira **oncelik** degildir: hepsi paralel cekilir,
  /// sonuclar birlestirilir ve yenilik sirasina gore siralanir.
  static final List<RssFeed> defaultFeeds = [
    aaEkonomi,
    bloombergHt,
    foreks,
    ekonomim,
    sabahEkonomi,
  ];

  /// Beslemeyi **hicbir sekilde firlatmadan** ceker.
  ///
  /// Hata izolasyonu: beklenmeyen bir istisna (ag kutuphanesi, kodlama,
  /// xml paketleyici) bile olsa yalnizca o beslemeyi devre disi birakir;
  /// diger beslemlerin sonucu korunur.
  Future<Result<List<NewsItem>>> _fetchFeedIsolated(
    RssFeed feed, {
    required int limit,
  }) async {
    try {
      return await fetchFeed(feed, limit: limit);
    } catch (e) {
      return Err(UnknownFailure('${feed.sourceName} beslemesi okunamadı.', e));
    }
  }

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

  // ---------------------------------------------------------------------------
  // KAYNAKLAR-ARASI TEKRAR (DUPLICATE) AZALTMA
  //
  // Ayni olay farkli ajanslar tarafindan farkli basliklarla gecabilir;
  // birebir ayni baslik da yaygin bir sekilde syndicate edilir. Burada
  // **korumaci** bir eslesme yapilir: yanlis birlestirme (farkli haberin
  // kaybolmasi) yanlis ayirma'dan (ayni haberin iki kez gorunmesinden)
  // daha kotudur.
  //
  // Kural 1: ayni `id` (guid)      -> tekrar
  // Kural 2: normalize edilmis baslik birebir ayni -> tekrar
  // Kural 3: bir baslik digerinin **icinde** geciyorsa (kaynak/sufiks
  //          eklenmis hali) -> tekrar. Bu kural ters anlami DEGISTIRMEZ:
  //          "yukselisle" ve "dususle" birbirinin icinde gecmez.
  // ---------------------------------------------------------------------------

  /// Basligi karsilastirma icin normalize eder.
  ///
  /// Kucuk harf + Turkce harf katlamasi (ı->i, İ->i, ş->s, ğ->g, ü->u,
  /// ö->o, ç->c) yapilir; noktalama isaretleri silinir, rakamlar **korunur**
  /// (BIST 100 ile BIST 30 ayni sayilmamali), bosluklar tek bosluga
  /// indirgenir.
  static String normalizeTitle(String title) {
    const fold = {
      'ı': 'i', 'İ': 'i', 'I': 'i', 'i': 'i',
      'ş': 's', 'Ş': 's',
      'ğ': 'g', 'Ğ': 'g',
      'ü': 'u', 'Ü': 'u',
      'ö': 'o', 'Ö': 'o',
      'ç': 'c', 'Ç': 'c',
    };
    final buffer = StringBuffer();
    for (final ch in title.toLowerCase().split('')) {
      buffer.write(fold[ch] ?? ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Tekrar eden haberleri azaltir. Girdi sirasi korunur.
  static List<NewsItem> deduplicate(List<NewsItem> items) {
    final seenIds = <String>{};
    final keptNorm = <String>[];
    final out = <NewsItem>[];

    for (final item in items) {
      if (!seenIds.add(item.id)) continue;

      final norm = normalizeTitle(item.title);
      if (norm.isNotEmpty) {
        var duplicated = false;
        for (final prev in keptNorm) {
          if (_isSameStory(prev, norm)) {
            duplicated = true;
            break;
          }
        }
        if (duplicated) continue;
        keptNorm.add(norm);
      }

      out.add(item);
    }
    return out;
  }

  /// Iki normalize edilmis basligin ayni habere ait olup olmadigi.
  static bool _isSameStory(String a, String b) {
    if (a == b) return true;

    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;

    // Cok kisa basliklar fazla ozeldir (yanlis eslesme riski yuksek).
    if (shorter.length < _minDedupLength) return false;
    // Uzunluk farki orantili degilse (bir baslik bambaşka bir haberin
    // uzantisi degilse) tekrar sayilmaz.
    if (longer.length - shorter.length > longer.length * 0.4) return false;

    return longer.contains(shorter);
  }

  /// Kapsayan-baslik kurali icin en kisa kabul edilen baslik uzunlugu.
  static const int _minDedupLength = 20;

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
      // **TEK TIRNAK DESTEĞI ZORUNLU:** Foreks `<img ... src='...'>` tek
      // tirnak kullanir; yalnizca cift tirnak arayan ifade gorseli bulamaz
      // ve haberler gorselsiz kalirdi (canli dogrulama 2026-10-06: Foreks
      // beslemesindeki 100 haberin 100'unde gorsel var; hotlink/401 yok).
      final match = RegExp(
        r'''<img[^>]*?\ssrc\s*=\s*(?:"([^"]+)"|'([^']+)')''',
        caseSensitive: false,
      ).firstMatch(desc);
      if (match != null) {
        final url = (match.group(1) ?? match.group(2))?.trim();
        if (url != null && url.startsWith('http')) return url;
      }
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
