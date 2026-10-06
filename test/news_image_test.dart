import 'package:flutter_test/flutter_test.dart';
import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/news_rss_provider.dart';
import 'package:gold/domain/entities/news_item.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Haber thumbnail (gorsel) ayristirma testleri.
///
/// **Canli inceleme sonucu (2026-10-06):** Foreks beslemesi gorseli
/// `<img ... src='...'>` biciminde (TEK tirnak) verir; onceki ayristirici
/// yalnizca cift tirnak aradigi icin bu kaynagin haberleri gorselsiz
/// kaliyordu. CDN/hotlink engeli **yok** (gorseller her User-Agent ile
/// HTTP 200 donuyor) - yani sorun kaynakta degil ayristiriciydi ve burada
/// duzeltildi.
void main() {
  final feed = RssFeed(
    url: Uri.parse('https://example.com/rss'),
    defaultCategory: NewsCategory.ekonomi,
    sourceName: 'Test Kaynak',
  );

  String _rss(String description) => '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>Test</title>
  <item>
    <title>Fed faiz kararı beklentisi</title>
    <link>https://ornek.com/haber/1</link>
    <description>$description</description>
    <guid>https://ornek.com/haber/1</guid>
    <pubDate>Mon, 05 Oct 2026 10:00:00 +0300</pubDate>
  </item>
</channel></rss>''';

  Future<List<NewsItem>> parse(String description) async {
    final provider = NewsRssProvider(
      ApiClient(
        client: MockClient(
          (_) async => http.Response(
            _rss(description),
            200,
            headers: const {'content-type': 'text/xml; charset=utf-8'},
          ),
        ),
      ),
    );
    final r = await provider.fetchFeed(feed);
    return r.dataOrNull ?? const <NewsItem>[];
  }

  test('TEK tirnakli img src (Foreks bicimi) bulunur', () async {
    final items = await parse(
      "<![CDATA[<img align=\"left\" alt=\"x\" hspace=\"8\" "
      "src='https://news-files.foreks.com/images/608eaec.jpeg'/>"
      "<br />Ozet metni]]>",
    );
    expect(items, hasLength(1));
    expect(
      items.single.imageUrl,
      'https://news-files.foreks.com/images/608eaec.jpeg',
      reason: 'tek tirnakli src de ayristirilmalidir (Foreks bicimi)',
    );
    expect(items.single.hasImage, isTrue);
  });

  test('CIFT tirnakli img src (AA / Bloomberg HT bicimi) bulunur', () async {
    final items = await parse(
      '<![CDATA[<img src="https://cdn.ornek.com/a.jpg" width="100" /> Ozet]]>',
    );
    expect(items.single.imageUrl, 'https://cdn.ornek.com/a.jpg');
  });

  test('Gorsel yoksa imageUrl null kalir (uydurma gorsel uretilmez)', () async {
    final items = await parse('Sadece yazi iceren ozet.');
    expect(items.single.imageUrl, isNull);
    expect(items.single.hasImage, isFalse);
  });

  test('Gorselsiz haber yine de listede kalir (kaynak atilmaz)', () async {
    final items = await parse('Gorsel olmayan haber.');
    expect(items, hasLength(1));
    expect(items.single.title, 'Fed faiz kararı beklentisi');
  });

  test('Ozet metni gorsel etiketiyle birlikte temizlenir', () async {
    final items = await parse(
      "<![CDATA[<img src='https://x.com/a.jpg'/>Brent petrol geriledi.]]>",
    );
    expect(items.single.imageUrl, 'https://x.com/a.jpg');
    expect(items.single.summary, isNot(contains('<img')));
    expect(items.single.summary, contains('Brent'));
  });
}
