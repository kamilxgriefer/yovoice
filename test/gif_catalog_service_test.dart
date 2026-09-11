import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/gif_transport.dart';

import 'support/fake_gif_transport.dart';

/// The client half of the rate budget, tested without a widget tree.
///
/// Debounce, minimum length, in-flight cancellation and the session memo are
/// what stand between one word typed at speed and five provider calls. The
/// server enforces its own limits regardless — this is not a security control
/// — but it is what keeps the client from spending a budget the server then
/// has to refuse.
void main() {
  group('availability', () {
    for (final query in ['cat', 'c', '']) {
      test('delayed availability keeps the current query "$query"', () async {
        final availability = Completer<GifCatalog>();
        final transport = _ControlledGifTransport(availability: availability);
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        final firstOpen = service.start();
        final reopened = service.start();
        expect(transport.catalogCalls, 1);
        service.query(query);
        // Let the zero-duration debounce run while catalog is still pending.
        await Future<void>.delayed(Duration.zero);
        expect(transport.pending, isEmpty);
        availability.complete(FakeGifTransport.availableCatalog);
        await Future<void>.delayed(Duration.zero);
        if (query == 'c') {
          expect(transport.pending, isEmpty);
          expect(service.state.status, GifQueryStatus.idle);
        } else {
          expect(transport.pending, hasLength(1));
          expect(transport.pending.single.query, query);
          transport.pending.single.result.complete(_page([0]));
        }
        await Future.wait([firstOpen, reopened]);
        expect(service.state.query, query);
        expect(service.state.status, isNot(GifQueryStatus.loading));
      });
    }

    test(
      'an unavailable catalog is reported, never optimistically assumed',
      () async {
        final service = GifCatalogService(
          transport: FakeGifTransport(
            catalogResult: const GifCatalog.unavailable(
              GifUnavailableReason.notConfigured,
            ),
          ),
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);

        await service.start();
        expect(service.state.status, GifQueryStatus.unavailable);
        expect(
          service.state.unavailableReason,
          GifUnavailableReason.notConfigured,
        );
        expect(service.state.items, isEmpty);
      },
    );

    test('an unavailable catalog makes every later query a no-op', () async {
      final transport = FakeGifTransport(
        catalogResult: const GifCatalog.unavailable(
          GifUnavailableReason.disabled,
        ),
      );
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);

      await service.start();
      service.query('kotek');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Not one provider call was attempted, so a disabled feature costs
      // nothing however hard somebody types into a picker they cannot see.
      expect(transport.searchCalls, isEmpty);
    });

    test(
      'start fetches trending exactly once, and blank means trending',
      () async {
        final transport = FakeGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);

        await service.start();
        await service.start();
        expect(transport.searchCalls, <String>['']);
        expect(service.state.status, GifQueryStatus.ready);
        expect(service.state.isTrending, isTrue);
      },
    );
  });

  group('the client rate budget', () {
    test(
      'a short query cancels initial loading even after its response arrives',
      () async {
        final transport = _ControlledGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        final starting = service.start();
        await Future<void>.delayed(Duration.zero);
        expect(transport.pending, hasLength(1));
        expect(service.state.status, GifQueryStatus.loading);

        service.query('c');
        expect(service.state.status, GifQueryStatus.idle);
        expect(service.state.items, isEmpty);
        transport.pending.single.result.complete(
          _page([0], nextCursor: 'next'),
        );
        await starting;
        expect(service.state.query, 'c');
        expect(service.state.status, GifQueryStatus.idle);
        expect(service.state.items, isEmpty);
        expect(service.state.nextCursor, isNull);
      },
    );

    test(
      'a short query retains ready results but never their paging cursor',
      () async {
        final transport = _ControlledGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        final starting = service.start();
        await Future<void>.delayed(Duration.zero);
        transport.pending.single.result.complete(
          _page([0], nextCursor: 'next'),
        );
        await starting;
        final previousItems = service.state.items;

        service.query('cat');
        await Future<void>.delayed(Duration.zero);
        expect(transport.pending, hasLength(2));
        service.query('c');
        expect(service.state.status, GifQueryStatus.ready);
        expect(service.state.items, previousItems);
        expect(service.state.nextCursor, isNull);
        await service.loadMore();
        expect(transport.pending, hasLength(2));
        transport.pending.last.result.complete(_page([1], nextCursor: 'other'));
        await Future<void>.delayed(Duration.zero);
        expect(service.state.status, GifQueryStatus.ready);
        expect(service.state.items, previousItems);
        expect(service.state.query, 'c');
        expect(service.state.nextCursor, isNull);
      },
    );

    test('a word typed at speed makes one call, for the final query', () async {
      final transport = FakeGifTransport();
      final service = GifCatalogService(
        transport: transport,
        debounce: const Duration(milliseconds: 40),
      );
      addTearDown(service.dispose);
      await service.start();
      transport.searchCalls.clear();

      service.query('k');
      service.query('ko');
      service.query('kot');
      service.query('kote');
      service.query('kotek');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(transport.searchCalls, <String>['kotek']);
    });

    test('a single character never leaves the device', () async {
      final transport = FakeGifTransport();
      final service = GifCatalogService(
        transport: transport,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(service.dispose);
      await service.start();
      transport.searchCalls.clear();

      service.query('k');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(transport.searchCalls, isEmpty);
    });

    test('a repeat of a query already fetched costs nothing', () async {
      final transport = FakeGifTransport();
      final service = GifCatalogService(
        transport: transport,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(service.dispose);
      await service.start();

      service.query('kot');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      service.query('kotek');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      transport.searchCalls.clear();

      // Backspacing to a query already in the session memo.
      service.query('kot');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(transport.searchCalls, isEmpty);
      expect(service.state.query, 'kot');
      expect(service.state.status, GifQueryStatus.ready);
    });

    test(
      'a slow answer for an old query never lands on top of a new one',
      () async {
        // The classic search race. Without generation tracking, "ko" resolving
        // after "kotek" would replace the newer results with older ones — and it
        // would look like the picker simply ignored the last three keystrokes.
        final transport = FakeGifTransport(
          searchDelay: const Duration(milliseconds: 60),
        );
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        await service.start();

        service.query('dog');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        service.query('cat');
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(service.state.query, 'cat');
        for (final item in service.state.items) {
          expect(item.title.toLowerCase(), contains('cat'));
        }
      },
    );

    test(
      'switching language clears the memo, because the answers change',
      () async {
        final transport = FakeGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: const Duration(milliseconds: 10),
        );
        addTearDown(service.dispose);
        await service.start();
        service.query('kot');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        transport.searchCalls.clear();

        service.locale = 'pl';
        service.query('');
        service.query('kot');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(transport.searchCalls, contains('kot'));
      },
    );
  });

  group('failure handling', () {
    test('a refusal keeps the results and records the retry hint', () async {
      final transport = FakeGifTransport();
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await service.start();
      final before = service.state.items;
      expect(before, isNotEmpty);

      transport.searchFailure = const GifTransportException(
        GifFailure.rateLimited,
        retryAfterSeconds: 7,
      );
      service.query('kot');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(service.state.rateLimitedRetrySeconds, 7);
      expect(service.state.items, before);
      expect(service.state.status, GifQueryStatus.ready);
    });

    test('an unavailable answer mid-session flips the whole surface', () async {
      // A revoked key trips the server's breaker between two searches. The
      // client must go to its disabled state rather than showing an error
      // toast on every keystroke forever.
      final transport = FakeGifTransport();
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await service.start();

      transport.searchFailure = const GifTransportException(
        GifFailure.unavailable,
      );
      service.query('kot');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(service.state.status, GifQueryStatus.unavailable);
      expect(
        service.state.unavailableReason,
        GifUnavailableReason.providerUnavailable,
      );
      expect(service.state.items, isEmpty);
    });

    test('a transient failure is retryable and recovers', () async {
      final transport = FakeGifTransport(
        searchFailure: const GifTransportException(GifFailure.transient),
      );
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await service.start();
      expect(service.state.status, GifQueryStatus.error);

      transport.searchFailure = null;
      await service.retry();
      expect(service.state.status, GifQueryStatus.ready);
      expect(service.state.items, isNotEmpty);
    });

    test('a degraded page is never memoized, but a real one is', () async {
      // Otherwise one budget-exhausted minute would pin fallback results as
      // the answer to a real query for the rest of the session.
      final transport = FakeGifTransport()..degraded = true;
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await service.start();

      service.query('kot');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(service.state.degraded, isTrue);

      transport.degraded = false;
      service.query('dog');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(service.state.degraded, isFalse);

      transport.searchCalls.clear();
      service.query('kot');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(transport.searchCalls, <String>[
        'kot',
      ], reason: 'the degraded page was memoized');
      expect(service.state.degraded, isFalse);

      // Contrast: the healthy page for "dog" IS memoized, so returning to it
      // costs nothing.
      transport.searchCalls.clear();
      service.query('dog');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(transport.searchCalls, isEmpty);
    });
  });

  group('paging', () {
    test(
      'repeated near-bottom events share one in-flight cursor request',
      () async {
        final transport = _ControlledGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        final starting = service.start();
        await Future<void>.delayed(Duration.zero);
        transport.pending.single.result.complete(
          _page([0], nextCursor: 'page2'),
        );
        await starting;

        final first = service.loadMore();
        await service.loadMore();
        await service.loadMore();
        expect(transport.pending, hasLength(2));
        expect(transport.pending.last.cursor, 'page2');
        expect(service.state.status, GifQueryStatus.ready);
        transport.pending.last.result.complete(
          _page([0, 1], nextCursor: 'page3'),
        );
        await first;
        expect(service.state.items, hasLength(2));

        final next = service.loadMore();
        expect(transport.pending, hasLength(3));
        expect(transport.pending.last.cursor, 'page3');
        transport.pending.last.result.complete(_page([2]));
        await next;
        expect(service.state.items, hasLength(3));
        expect(service.state.nextCursor, isNull);
      },
    );

    test(
      'a canceled page cannot append or unlock a newer query page',
      () async {
        final transport = _ControlledGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        addTearDown(service.dispose);
        final starting = service.start();
        await Future<void>.delayed(Duration.zero);
        transport.pending.single.result.complete(
          _page([0], nextCursor: 'old-page'),
        );
        await starting;
        final oldPage = service.loadMore();

        service.query('cat');
        await Future<void>.delayed(Duration.zero);
        transport.pending[2].result.complete(
          _page([1], nextCursor: 'cat-page'),
        );
        await Future<void>.delayed(Duration.zero);
        final newPage = service.loadMore();
        expect(transport.pending, hasLength(4));
        expect(transport.pending.last.query, 'cat');
        expect(transport.pending.last.cursor, 'cat-page');

        transport.pending[1].result.complete(_page([2], nextCursor: 'stale'));
        await oldPage;
        await service.loadMore();
        expect(
          transport.pending,
          hasLength(4),
          reason: 'old completion unlocked new page',
        );
        expect(service.state.items, [FakeGifTransport.defaultAssets[1]]);
        transport.pending.last.result.complete(_page([3]));
        await newPage;
        expect(service.state.query, 'cat');
        expect(service.state.items, [
          FakeGifTransport.defaultAssets[1],
          FakeGifTransport.defaultAssets[3],
        ]);
      },
    );

    test(
      'paging failure releases its guard and disposal ignores late completion',
      () async {
        final transport = _ControlledGifTransport();
        final service = GifCatalogService(
          transport: transport,
          debounce: Duration.zero,
        );
        final starting = service.start();
        await Future<void>.delayed(Duration.zero);
        transport.pending.single.result.complete(
          _page([0], nextCursor: 'next'),
        );
        await starting;
        final failedPage = service.loadMore();
        transport.pending.last.result.completeError(
          const GifTransportException(GifFailure.transient),
        );
        await failedPage;
        expect(service.state.status, GifQueryStatus.error);
        final retriedPage = service.loadMore();
        expect(transport.pending, hasLength(3));
        var notifications = 0;
        service.addListener(() => notifications++);
        service.dispose();
        transport.pending.last.result.complete(_page([1]));
        await retriedPage;
        await service.loadMore();
        expect(notifications, 0);
        expect(transport.pending, hasLength(3));
        expect(service.state.items, [FakeGifTransport.defaultAssets[0]]);
      },
    );

    test('loadMore appends without duplicating', () async {
      final transport = FakeGifTransport(pageSize: 3);
      final service = GifCatalogService(
        transport: transport,
        debounce: Duration.zero,
      );
      addTearDown(service.dispose);
      await service.start();
      // The catalog's declared pageSize wins over the fake's default, so ask
      // for the fake's own page size explicitly through a cursor walk.
      final first = service.state.items.length;

      await service.loadMore();
      await service.loadMore();
      final ids = service.state.items.map((item) => item.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'a page was duplicated');
      expect(service.state.items.length, greaterThanOrEqualTo(first));
    });

    test('the wire parser drops one malformed item, not the page', () {
      final page = GifSearchPage.fromWire(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'provider': 'fake',
            'id': 'ok1',
            'url': 'https://fake.invalid/gif/ok1/200h.gif',
            'title': 'Fine',
            'rating': 'g',
            'width': 200,
            'height': 200,
          },
          <String, Object?>{'provider': 'fake'},
          'not a map',
        ],
        'nextCursor': '1',
        'degraded': false,
      });
      expect(page.items, hasLength(1));
      expect(page.items.single.id, 'ok1');
      expect(page.nextCursor, '1');
    });

    test('an item with no title still renders as something', () {
      final asset = GifAsset.fromWire(<String, Object?>{
        'provider': 'fake',
        'id': 'notitle',
        'url': 'https://fake.invalid/gif/notitle/200h.gif',
      });
      // The title is what a dead CDN URL and an old app install both fall back
      // to, so it can never be empty.
      expect(asset!.title, 'GIF');
      expect(asset.rating, 'g');
      expect(asset.width, 200);
    });
  });
}

GifSearchPage _page(List<int> indexes, {String? nextCursor}) => GifSearchPage(
  items: [for (final index in indexes) FakeGifTransport.defaultAssets[index]],
  nextCursor: nextCursor,
  degraded: false,
  cacheHit: false,
  attribution: FakeGifTransport.availableCatalog.attribution,
);

/// Each request completes only when the test says so; no timing races or
/// artificial network sleeps are needed to prove cancellation/single-flight.
class _ControlledGifTransport extends FakeGifTransport {
  _ControlledGifTransport({this.availability});

  final Completer<GifCatalog>? availability;
  final pending = <_PendingSearch>[];
  var catalogCalls = 0;

  @override
  Future<GifCatalog> catalog() {
    catalogCalls++;
    return availability?.future ?? super.catalog();
  }

  @override
  Future<GifSearchPage> search({
    required String query,
    required String locale,
    String? cursor,
    int? limit,
  }) {
    final request = _PendingSearch(query, cursor);
    pending.add(request);
    return request.result.future;
  }
}

class _PendingSearch {
  _PendingSearch(this.query, this.cursor);

  final String query;
  final String? cursor;
  final result = Completer<GifSearchPage>();
}
