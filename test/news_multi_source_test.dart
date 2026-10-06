// GOLD - Coklu haber kaynagi + hata izolasyonu + tekrar (duplicate) azaltma.
//
// Kurallar:
//  * Varsayilan besleme listesi tek kaynaga bagimli degildir.
//  * Her besleme bagimsiz cekilir: 500 / 429 / exception -> digerleri devam.
//  * En az bir besleme basariliysa sonuc Success'tir.
//  * Tumu hataliysa Err doner (repository onbellege duser).
//  * Tekrar azaltma **korumacidir**: zanli birlestirme yapilmaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gold/core/network/api_client.dart';
import 'package:gold/data/providers/news_rss_provider.dart';
import 'package:gold/domain/entities/news_item.dart';

// ---------------------------------------------------------------------------
// Yardimcilar
// ---------------------------------------------------------------------------

String _item({
  required String title,
  required String url,
  required String pubDate,
  String? category,
}) {
  final cat = category == null ? '' : '<category>$category</category>';
  return '<item>'
      '<title>$title</title>'
      '<link>$url</link>'
      '<description>Özet metni - tam metin değil.</description>'
      '<guid>$url</guid>'
      '<pubDate>$pubDate</pubDate>'
      '$cat'
      '</item>';
}

String _rss(List<String> items) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<rss version="2.0"><channel><title>Kaynak</title>'
    '${items.join()}'
    '</channel></rss>';

RssFeed _feed(String name, String host) => RssFeed(
      url: Uri.parse('https://$host/rss'),
      defaultCategory: NewsCategory.ekonomi,
      sourceName: name,
    );

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: const {'content-type': 'text/xml; charset=utf-8'},
    );

NewsItem _n(String id, String title, {String source = 'Kaynak', int hour = 10}) =>
    NewsItem(
      id: id,
      title: title,
      source: source,
      publishedAt: DateTime.utc(2026, 10, 5, hour),
      category: NewsCategory.ekonomi,
      url: 'https://example.com/$id',
    );

void main() {
  // ---------------------------------------------------------------------------
  group('Varsayilan kaynak listesi', () {
    test('tek kaynaga bagimli degildir', () {
      final feeds = NewsRssProvider.defaultFeeds;

      expect(feeds.length, greaterThanOrEqualTo(5),
          reason: 'en az 5 bagimsiz yayinci olmali');
      expect(
        feeds.map((f) => f.sourceName).toSet(),
        containsAll(<String>[
          'Anadolu Ajansı',
          'Bloomberg HT',
          'Foreks',
          'Ekonomim',
          'Sabah',
        ]),
      );
    });

    test('kaynak adlari benzersiz ve gecerli', () {
      final feeds = NewsRssProvider.defaultFeeds;
      final names = feeds.map((f) => f.sourceName).toList();

      expect(names.toSet(), hasLength(names.length),
          reason: 'kaynak adlari ayni olmamali - UI\'da ayirt edilmeli');
      for (final f in feeds) {
        expect(f.sourceName.trim(), isNotEmpty);
        expect(f.url.isScheme('https'), isTrue, reason: f.url.toString());
        expect(f.url.host, isNotEmpty);
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('fetchAll - coklu kaynak birlestirme', () {
    test('paralel cekilir, en yeni ustte ve kaynak adlari korunur', () async {
      final client = MockClient((req) async {
        switch (req.url.host) {
          case 'a.com':
            return _ok(_rss([
              _item(
                title: 'AAA en yeni',
                url: 'https://a.com/1',
                pubDate: 'Mon, 05 Oct 2026 12:00:00 +0000',
              ),
              _item(
                title: 'AAA en eski',
                url: 'https://a.com/2',
                pubDate: 'Mon, 05 Oct 2026 08:00:00 +0000',
              ),
            ]));
          case 'b.com':
            return _ok(_rss([
              _item(
                title: 'BBB arada',
                url: 'https://b.com/1',
                pubDate: 'Mon, 05 Oct 2026 10:00:00 +0000',
              ),
            ]));
          case 'c.com':
            return _ok(_rss([
              _item(
                title: 'CCC tekrar eden 1',
                url: 'https://c.com/1',
                pubDate: 'Mon, 05 Oct 2026 09:00:00 +0000',
              ),
            ]));
        }
        return http.Response('yok', 404);
      });

      final p = NewsRssProvider(
        ApiClient(client: client),
        feeds: [
          _feed('Kaynak A', 'a.com'),
          _feed('Kaynak B', 'b.com'),
          _feed('Kaynak C', 'c.com'),
        ],
      );

      final res = await p.fetchAll(limit: 30);
      final items = res.dataOrNull;
      expect(items, isNotNull, reason: '${res.failureOrNull}');
      expect(items!.map((i) => i.title).toList(), <String>[
        'AAA en yeni',
        'BBB arada',
        'CCC tekrar eden 1',
        'AAA en eski',
      ]);
      expect(items.map((i) => i.source).toSet(), <String>{
        'Kaynak A',
        'Kaynak B',
        'Kaynak C',
      });
    });

    test('limit toplam haber sayisina uygulanir (besleme sayisina degil)',
        () async {
      final client = MockClient((req) async {
        switch (req.url.host) {
          case 'a.com':
            return _ok(_rss([
              _item(
                title: 'A 1',
                url: 'https://a.com/1',
                pubDate: 'Mon, 05 Oct 2026 12:00:00 +0000',
              ),
              _item(
                title: 'A 2',
                url: 'https://a.com/2',
                pubDate: 'Mon, 05 Oct 2026 11:00:00 +0000',
              ),
            ]));
          case 'b.com':
            return _ok(_rss([
              _item(
                title: 'B 1',
                url: 'https://b.com/1',
                pubDate: 'Mon, 05 Oct 2026 10:00:00 +0000',
              ),
              _item(
                title: 'B 2',
                url: 'https://b.com/2',
                pubDate: 'Mon, 05 Oct 2026 09:00:00 +0000',
              ),
            ]));
        }
        return http.Response('yok', 404);
      });

      final p = NewsRssProvider(
        ApiClient(client: client),
        feeds: [_feed('A', 'a.com'), _feed('B', 'b.com')],
      );

      final items = (await p.fetchAll(limit: 2)).dataOrNull;
      expect(items, hasLength(2));
      expect(items!.map((i) => i.title).toList(), <String>['A 1', 'A 2']);
    });
  });

  // ---------------------------------------------------------------------------
  group('Hata izolasyonu - tek kaynak dusmeli, ekran copmemeli', () {
    Future<({List<NewsItem>? items, Object? failure})> runWith(
      String brokenHost,
      http.Response Function() broken,
    ) async {
      final client = MockClient((req) async {
        if (req.url.host == brokenHost) return broken();
        return _ok(_rss([
          _item(
            title: '${req.url.host} haberleri',
            url: 'https://${req.url.host}/1',
            pubDate: 'Mon, 05 Oct 2026 12:00:00 +0000',
          ),
        ]));
      });

      final p = NewsRssProvider(
        ApiClient(client: client),
        feeds: [
          _feed('Saglikli A', 'a.com'),
          _feed('Saglikli B', 'b.com'),
          _feed('Saglikli C', 'c.com'),
        ],
      );

      final res = await p.fetchAll(limit: 30);
      return (items: res.dataOrNull, failure: res.failureOrNull);
    }

    test('500 (sunucu hatasi) -> diger kaynaklar devam eder', () async {
      final r = await runWith('b.com', () => http.Response('hata', 500));

      expect(r.items, isNotNull, reason: '${r.failure}');
      expect(r.items, hasLength(2));
      expect(r.items!.map((i) => i.source), isNot(contains('Saglikli B')));
    });

    test('429 (rate limit) -> tum ekran copmez, digerleri gelir', () async {
      final r = await runWith(
        'a.com',
        () => http.Response('too many requests', 429),
      );

      expect(r.items, isNotNull, reason: '${r.failure}');
      expect(r.items, hasLength(2));
      expect(r.items!.map((i) => i.source), <String>{'Saglikli B', 'Saglikli C'});
    });

    test('404 (kaynak kaymissa) -> digerleri etkilenmez', () async {
      final r = await runWith('c.com', () => http.Response('yok', 404));

      expect(r.items, isNotNull, reason: '${r.failure}');
      expect(r.items, hasLength(2));
    });

    test('beklenmeyen exception -> yalnizca o besleme devre disi', () async {
      final r = await runWith('b.com', () => throw StateError('bozuk govde'));

      expect(r.items, isNotNull, reason: '${r.failure}');
      expect(r.items, hasLength(2));
      expect(r.items!.map((i) => i.source), isNot(contains('Saglikli B')));
    });

    test('bozuk XML (200 ama govde gecersiz) -> digerleri gelir', () async {
      final r = await runWith('b.com', () => http.Response('degil xml', 200));

      expect(r.items, isNotNull, reason: '${r.failure}');
      expect(r.items, hasLength(2));
    });

    test('tumu hataliysa Err doner (repository son gecerli haberi sunar)',
        () async {
      final client = MockClient((_) async => http.Response('hata', 503));
      final p = NewsRssProvider(
        ApiClient(client: client),
        feeds: [_feed('A', 'a.com'), _feed('B', 'b.com')],
      );

      final res = await p.fetchAll(limit: 10);
      expect(res.dataOrNull, isNull);
      expect(res.failureOrNull, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('Duplicate azaltma - normalizeTitle', () {
    test('turkce harfler katlanir, buyuk/kucuk harf ve noktalama esitlenir',
        () {
      expect(
        NewsRssProvider.normalizeTitle('Merkez Bankası faiz kararını AÇIKLADI!'),
        'merkez bankasi faiz kararini acikladi',
      );
      expect(
        NewsRssProvider.normalizeTitle('ŞUBAT — Ücretler %15 arttı (ÖNCEKİ)'),
        'subat ucretler 15 artti onceki',
      );
      expect(
        NewsRssProvider.normalizeTitle('   GÜNLÜK   RAPOR   '),
        'gunluk rapor',
      );
    });

    test('rakamlar korunur: BIST 100 ile BIST 30 ayni degildir', () {
      expect(
        NewsRssProvider.normalizeTitle('BIST 100 günü kapattı'),
        isNot(NewsRssProvider.normalizeTitle('BIST 30 günü kapattı')),
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('Duplicate azaltma - deduplicate', () {
    test('ayni id iki kez girerse biri elenir', () {
      final out = NewsRssProvider.deduplicate([
        _n('g1', 'TCMB faiz kararını açıkladı', source: 'AA'),
        _n('g1', 'TCMB faiz kararını açıkladı', source: 'Sabah'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.source, 'AA', reason: 'ilk gelen korunur');
    });

    test('ayni baslik farkli kaynaklarda -> tek haber', () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'TCMB faiz kararını açıkladı', source: 'AA'),
        _n('b1', 'TCMB faiz kararını açıkladı', source: 'Foreks'),
        _n('c1', 'TCMB faiz kararını açıkladı', source: 'Ekonomim'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.source, 'AA');
    });

    test('basligin uzatilmis hali (kaynak/sonraki ek) ayni habere sayilir',
        () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'TCMB politika faizini sabit tuttu', source: 'AA'),
        _n(
          'b1',
          'TCMB politika faizini sabit tuttu - Piyasalar tepkili',
          source: 'Bloomberg HT',
        ),
      ]);
      expect(out, hasLength(1),
          reason: 'kapsayan-baslik kurali: uzanti ayni habere ait');
    });

    test('ZANLI BIRLESTIRME YAPMAZ: zit anlaml basliklar ayri kalir', () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'BIST 100 günü yükselişle kapattı'),
        _n('b1', 'BIST 100 günü düşüşle kapattı'),
      ]);
      expect(out, hasLength(2),
          reason: '"yükselişle" ile "düşüşle" birbirinin icinde gecmez');
    });

    test('ZANLI BIRLESTIRME YAPMAZ: rakam farki ayri haberdir', () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'BIST 100 günü yükselişle kapattı'),
        _n('b1', 'BIST 30 günü yükselişle kapattı'),
      ]);
      expect(out, hasLength(2));
    });

    test('ZANLI BIRLESTIRME YAPMAZ: cok kisa baslik konteynirda birlesmez',
        () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'Altın rekor kırdı'),
        _n('b1', 'Altın rekor kırdı dolarda geriledi'),
      ]);
      expect(out, hasLength(2),
          reason: 'kisa basliklar fazla ozel - esik alti korunur');
    });

    test('ayni kisa baslik birebir ayniysa yine birlesir', () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'Altın rekor kırdı'),
        _n('b1', 'Altın rekor kırdı'),
      ]);
      expect(out, hasLength(1));
    });

    test('oran korumasi: asiri uzun ekleme yutulmaz', () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'TCMB enflasyon raporunu yayınladı'),
        _n(
          'b1',
          'TCMB enflasyon raporunu yayınladı; '
          'değerlendirirken piyasalar ne yapmalı '
          've yatırımcılar için hangi senaryolar var '
          'sorusuna uzmanlar yanıt arıyor',
        ),
      ]);
      expect(out, hasLength(2),
          reason: 'fark (37) > 40% * uzunluk (28) -> tekrar sayilmaz');
    });

    test('farkli haberler ayni kalir', () {
      final out = NewsRssProvider.deduplicate([
        _n('a1', 'Merkez Bankası faiz kararını açıkladı', hour: 12),
        _n('b1', 'Brent petrol 100 doları aştı', hour: 11),
        _n('c1', 'BIST 100 günü yükselişle kapattı', hour: 10),
      ]);
      expect(out, hasLength(3));
    });
  });

  // ---------------------------------------------------------------------------
  group('fetchAll - kaynaklar arasi tekrar azaltma (uc-to-uc)', () {
    test('farkli kaynaklar ayni haberi gonderirse ekranda tek gorunur',
        () async {
      final client = MockClient((req) async {
        switch (req.url.host) {
          case 'aa.com':
            return _ok(_rss([
              _item(
                title: 'TCMB politika faizini sabit tuttu',
                url: 'https://aa.com/1',
                pubDate: 'Mon, 05 Oct 2026 12:00:00 +0000',
              ),
              _item(
                title: 'Brent petrol 100 doları aştı',
                url: 'https://aa.com/2',
                pubDate: 'Mon, 05 Oct 2026 11:00:00 +0000',
              ),
            ]));
          case 'bht.com':
            return _ok(_rss([
              _item(
                title: 'TCMB politika faizini sabit tuttu - Piyasalar tepkili',
                url: 'https://bht.com/1',
                pubDate: 'Mon, 05 Oct 2026 12:05:00 +0000',
              ),
            ]));
          case 'foreks.com':
            return _ok(_rss([
              _item(
                title: 'TCMB politika faizini sabit tuttu',
                url: 'https://foreks.com/1',
                pubDate: 'Mon, 05 Oct 2026 12:03:00 +0000',
              ),
              _item(
                title: 'BIST 100 günü yükselişle kapattı',
                url: 'https://foreks.com/2',
                pubDate: 'Mon, 05 Oct 2026 10:00:00 +0000',
              ),
            ]));
        }
        return http.Response('yok', 404);
      });

      final p = NewsRssProvider(
        ApiClient(client: client),
        feeds: [
          _feed('Anadolu Ajansı', 'aa.com'),
          _feed('Bloomberg HT', 'bht.com'),
          _feed('Foreks', 'foreks.com'),
        ],
      );

      final items = (await p.fetchAll(limit: 30)).dataOrNull;
      expect(items, isNotNull);

      final titles = items!.map((i) => i.title).toList();
      expect(
        titles.where((t) => t.contains('TCMB politika faizini')).length,
        1,
        reason: 'ayni haber 3 farkli kaynaktan gelip tek gorunmeli',
      );
      expect(items, hasLength(3),
          reason: 'TCMB tek + Brent tek + BIST tek');
      // En yeni ustte korunur.
      expect(items.first.publishedAt.isAfter(items.last.publishedAt), isTrue);
    });
  });
}
