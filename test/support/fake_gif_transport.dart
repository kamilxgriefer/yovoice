import 'dart:async';

import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_transport.dart';

/// The client half of the fake transport.
///
/// This is what makes every picker state reachable in a widget test with no
/// network, no Firebase project and no API key: available, unavailable for
/// each of its five reasons, loading, populated, empty, error, rate-limited,
/// degraded and paged. It mirrors `functions/media/gif/fake_provider.js` —
/// same shape of catalog, same deterministic ids — so a test written against
/// one reads the same as a test written against the other.
///
/// Its URLs point at `fake.invalid`, a domain RFC 2606 reserves and nothing
/// can resolve. A fixture must never cause a real network fetch.
class FakeGifTransport implements GifTransport {
  FakeGifTransport({
    this.catalogResult,
    this.searchFailure,
    this.searchDelay = Duration.zero,
    this.pageSize = 24,
    List<GifAsset>? assets,
  }) : assets = assets ?? defaultAssets;

  /// Overrides what [catalog] answers. Defaults to an available catalog with
  /// the same attribution contract GIPHY imposes.
  final GifCatalog? catalogResult;

  /// When set, every [search] throws it. Use it for the error, rate-limited
  /// and unavailable states. MUTABLE so a test can start healthy, show real
  /// results, and then make the next call fail — which is the only way to
  /// prove the picker keeps its grid when it is told to slow down.
  GifTransportException? searchFailure;

  /// Lets a test observe the loading state before results arrive.
  final Duration searchDelay;

  final int pageSize;
  final List<GifAsset> assets;

  /// Every call made, in order, so a test can assert the debounce collapsed
  /// five keystrokes into one request.
  final List<String> searchCalls = <String>[];
  final List<String> reportCalls = <String>[];

  /// Set to serve a degraded page — the state the server returns when the
  /// hour's provider budget is spent.
  bool degraded = false;

  static final defaultAssets = List<GifAsset>.unmodifiable(<GifAsset>[
    for (final entry in const <List<String>>[
      ['fakeCat01', 'Happy cat', 'cat kot'],
      ['fakeCat02', 'Cat typing fast', 'cat kot'],
      ['fakeDog01', 'Dog says hello', 'dog pies'],
      ['fakeLol01', 'Laughing out loud', 'lol laugh'],
      ['fakeYes01', 'Absolutely yes', 'yes tak'],
      ['fakeNo001', 'Hard no', 'no nie'],
      ['fakeDan01', 'Dance party', 'dance taniec'],
      ['fakeThx01', 'Thank you so much', 'thanks dzieki'],
      [
        'fakeEdg02',
        'A title so long that it exists purely to prove the hundred character '
            'ceiling holds in the picker too',
        'edge long',
      ],
    ])
      GifAsset(
        provider: 'fake',
        id: entry[0],
        title: entry[1],
        rating: 'g',
        previewUrl: 'https://fake.invalid/preview/${entry[0]}.gif',
        url: 'https://fake.invalid/gif/${entry[0]}/200h.gif',
        width: 200,
        height: 200,
      ),
  ]);

  static const _tags = <String, String>{
    'fakeCat01': 'cat kot happy',
    'fakeCat02': 'cat kot typing',
    'fakeDog01': 'dog pies hello',
    'fakeLol01': 'lol laugh smiech',
    'fakeYes01': 'yes tak agree',
    'fakeNo001': 'no nie',
    'fakeDan01': 'dance taniec party',
    'fakeThx01': 'thanks dzieki',
    'fakeEdg02': 'edge long title',
  };

  static const availableCatalog = GifCatalog(
    available: true,
    reason: null,
    provider: 'fake',
    attribution: GifAttribution(text: 'Powered by GIPHY', required: true),
    categories: <String>['trending', 'love', 'happy'],
    pageSize: 24,
    minimumQueryLength: 2,
    ratingLabel: 'g',
  );

  @override
  Future<GifCatalog> catalog() async => catalogResult ?? availableCatalog;

  @override
  Future<GifSearchPage> search({
    required String query,
    required String locale,
    String? cursor,
    int? limit,
  }) async {
    searchCalls.add(query);
    if (searchDelay > Duration.zero) await Future<void>.delayed(searchDelay);
    final failure = searchFailure;
    if (failure != null) throw failure;

    final terms = query.toLowerCase().split(' ').where((t) => t.isNotEmpty);
    final matching = query.isEmpty
        ? assets
        : assets
              .where((asset) {
                final haystack =
                    '${_tags[asset.id] ?? ''} ${asset.title.toLowerCase()}';
                return terms.every(haystack.contains);
              })
              .toList(growable: false);

    final start = int.tryParse(cursor ?? '0') ?? 0;
    final size = limit ?? pageSize;
    final slice = matching.skip(start).take(size).toList(growable: false);
    final consumed = start + slice.length;
    return GifSearchPage(
      items: slice,
      nextCursor: consumed < matching.length ? '$consumed' : null,
      degraded: degraded,
      cacheHit: false,
      attribution: (catalogResult ?? availableCatalog).attribution,
    );
  }

  @override
  Future<void> report({
    required String provider,
    required String gifId,
    required String reason,
    String note = '',
    String? contextPath,
  }) async {
    reportCalls.add('$provider:$gifId:$reason');
  }
}
