import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/media/data/services/gif_message_controller.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/giphy_client.dart';
import 'package:yovoice/features/media/data/services/giphy_pingbacks.dart';

import 'support/fake_giphy_http.dart';

/// Placeholder only. Tests never see or use a real GIPHY key.
const _testKey = 'placeholder-key-for-tests';

class _MemoryRandomIdStore implements GiphyRandomIdStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

void main() {
  group('GiphyClient (ADR-210 client-side search)', () {
    test('the build carries no key in tests, so the client is absent', () {
      expect(GiphyClient.apiKeyDefine, 'YOVOICE_GIPHY_API_KEY');
      expect(GiphyClient.isConfiguredInBuild, isFalse);
      expect(GiphyClient.fromEnvironment(), isNull);
    });

    test('trending and search pin rating=g and call GIPHY directly', () async {
      final fake = FakeGiphyHttp();
      final client = GiphyClient(apiKey: _testKey, httpClient: fake.client);

      await client.trending(limit: 24);
      await client.search(query: 'kotek', language: 'pl', limit: 99);

      expect(fake.searches, hasLength(2));
      final trending = fake.searches[0];
      final search = fake.searches[1];
      expect(trending.scheme, 'https');
      expect(trending.host, 'api.giphy.com');
      expect(trending.path, '/v1/gifs/trending');
      expect(search.path, '/v1/gifs/search');
      for (final url in fake.searches) {
        expect(url.queryParameters['rating'], 'g');
        expect(url.queryParameters['bundle'], 'messaging_non_clips');
        expect(url.queryParameters['api_key'], _testKey);
      }
      expect(search.queryParameters['q'], 'kotek');
      expect(search.queryParameters['lang'], 'pl');
      expect(search.queryParameters['limit'], '30');
    });

    test('results are re-filtered to g, id-checked and URL-pinned', () async {
      final fake = FakeGiphyHttp(
        items: [
          FakeGiphyHttp.item('goodOne01', title: 'Excited cat GIF by Brand'),
          FakeGiphyHttp.item('pgRated01', rating: 'pg'),
          FakeGiphyHttp.item('../escape'),
          FakeGiphyHttp.item(
            'hostile01',
            preview: 'https://evil.example/track.gif',
          ),
        ],
      );
      final client = GiphyClient(apiKey: _testKey, httpClient: fake.client);
      final page = await client.trending(limit: 24);

      expect(page.results.map((result) => result.asset.id), [
        'goodOne01',
        'hostile01',
      ]);
      final good = page.results.first.asset;
      expect(good.provider, 'giphy');
      expect(good.rating, 'g');
      expect(good.title, 'Excited cat');
      expect(good.url, 'https://media.giphy.com/media/goodOne01/200h.gif');
      expect(good.hasPinnedUrl, isTrue);
      expect(good.width, 300);
      expect(good.height, 200);
      // A preview off GIPHY's media hosts falls back to a GIPHY rendition.
      final hostile = page.results.last.asset;
      expect(hostile.previewUrl, isNot(contains('evil.example')));
      expect(hostile.previewUrl, startsWith('https://media2.giphy.com/'));
      expect(page.results.first.analytics.onLoad?.host, endsWith('giphy.com'));
    });

    test('a denylisted query never reaches GIPHY', () async {
      final fake = FakeGiphyHttp();
      final client = GiphyClient(apiKey: _testKey, httpClient: fake.client);
      for (final query in ['nsfw cats', 'GWAŁT', 'Porno!', 'how to die']) {
        final page = await client.search(query: query, limit: 24);
        expect(page.results, isEmpty, reason: query);
      }
      expect(fake.requests, isEmpty);
      expect(isDeniedGifQuery('assassin creed'), isFalse);
      expect(isDeniedGifQuery('Scunthorpe'), isFalse);
    });

    test(
      'a failed request reports a status and never the key-bearing URL',
      () async {
        final fake = FakeGiphyHttp(status: 429);
        final client = GiphyClient(apiKey: _testKey, httpClient: fake.client);
        await expectLater(
          client.trending(limit: 24),
          throwsA(
            isA<GiphyClientException>()
                .having((error) => error.isRateLimited, 'rate limited', isTrue)
                .having(
                  (error) => error.toString(),
                  'message',
                  isNot(contains(_testKey)),
                ),
          ),
        );
      },
    );

    test('analytics URLs are held to https on giphy.com', () {
      expect(
        GiphyAnalytics.isAllowedUrl(
          Uri.parse('https://giphy-analytics.giphy.com/v2/pingback_simple'),
        ),
        isTrue,
      );
      for (final url in [
        'http://giphy-analytics.giphy.com/x',
        'https://giphy.com.evil.example/x',
        'https://user:pass@pingback.giphy.com/x',
        'https://pingback.giphy.com:8443/x',
      ]) {
        expect(
          GiphyAnalytics.isAllowedUrl(Uri.parse(url)),
          isFalse,
          reason: url,
        );
      }
    });

    test('paging stops at the end of the results', () async {
      final fake = FakeGiphyHttp();
      final client = GiphyClient(apiKey: _testKey, httpClient: fake.client);
      final page = await client.search(query: 'cats', limit: 2);
      expect(page.nextOffset, isNull);
    });
  });

  group('GiphyPingbacks (Action Register)', () {
    late FakeGiphyHttp fake;
    late GiphyClient client;
    late _MemoryRandomIdStore store;
    late GiphyPingbacks pingbacks;

    setUp(() async {
      fake = FakeGiphyHttp();
      client = GiphyClient(apiKey: _testKey, httpClient: fake.client);
      store = _MemoryRandomIdStore();
      pingbacks = GiphyPingbacks(
        client: client,
        store: store,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      pingbacks.remember((await client.trending(limit: 24)).results);
    });

    test(
      'nothing at all is sent while "Load GIFs automatically" is off',
      () async {
        await pingbacks.loaded('giphyOne01', enabled: false);
        await pingbacks.clicked('giphyOne01', enabled: false);
        await pingbacks.sent('giphyOne01');
        expect(fake.pings, isEmpty);
        expect(fake.randomIdCalls, 0);
      },
    );

    test(
      'onload fires once per result, tagged with the install id and ts',
      () async {
        await pingbacks.loaded('giphyOne01', enabled: true);
        await pingbacks.loaded('giphyOne01', enabled: true);
        expect(fake.pings, hasLength(1));
        final ping = fake.pings.single;
        expect(ping.queryParameters['action_type'], 'SEEN');
        expect(ping.queryParameters['customer_id'], 'install-random-1');
        expect(ping.queryParameters['ts'], '1700000000000');
        expect(store.value, 'install-random-1');
        expect(fake.randomIdCalls, 1);
      },
    );

    test('onclick arms exactly one onsent', () async {
      await pingbacks.clicked('giphyTwo02', enabled: true);
      await pingbacks.sent('giphyTwo02');
      await pingbacks.sent('giphyTwo02');
      expect(fake.pings.map((url) => url.queryParameters['action_type']), [
        'CLICK',
        'SENT',
      ]);
    });

    test('a disarmed or never-clicked choice sends no onsent', () async {
      await pingbacks.sent('giphyOne01');
      await pingbacks.clicked('giphyOne01', enabled: true);
      pingbacks.disarm('giphyOne01');
      await pingbacks.sent('giphyOne01');
      expect(fake.pings.map((url) => url.queryParameters['action_type']), [
        'CLICK',
      ]);
    });

    test('the install id is reused, not fetched again', () async {
      store.value = 'stored-install-id';
      await pingbacks.loaded('giphyOne01', enabled: true);
      expect(fake.randomIdCalls, 0);
      expect(
        fake.pings.single.queryParameters['customer_id'],
        'stored-install-id',
      );
    });

    test(
      'the send controller registers onsent only after the server commits',
      () async {
        await pingbacks.clicked('giphyOne01', enabled: true);
        const asset = GifAsset(
          provider: 'giphy',
          id: 'giphyOne01',
          title: 'Happy dance',
          rating: 'g',
          previewUrl: 'https://media.giphy.com/media/giphyOne01/200h.gif',
          url: 'https://media.giphy.com/media/giphyOne01/200h.gif',
          width: 300,
          height: 200,
        );
        var fail = true;
        final controller = GifMessageController(
          callable: 'sendDirectMessage',
          target: const {'conversationId': 'chat'},
          currentUserId: () => 'me',
          giphyPingbacks: pingbacks,
          invoke: (_, _) async {
            if (fail) throw StateError('lost');
            return {'conversationId': 'chat', 'messageId': 'm1'};
          },
        );
        addTearDown(controller.dispose);
        await controller.send(asset);
        await Future<void>.delayed(Duration.zero);
        expect(
          fake.pings.where(
            (url) => url.queryParameters['action_type'] == 'SENT',
          ),
          isEmpty,
        );
        fail = false;
        await controller.retry();
        await Future<void>.delayed(Duration.zero);
        expect(
          fake.pings.where(
            (url) => url.queryParameters['action_type'] == 'SENT',
          ),
          hasLength(1),
        );
      },
    );
  });
}
