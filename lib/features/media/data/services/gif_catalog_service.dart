import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_transport.dart';

/// What the picker is showing right now.
enum GifQueryStatus { idle, loading, ready, empty, error, unavailable }

/// The picker's whole observable state, in one immutable value.
///
/// One object rather than six flags on the widget: "loading" and "rate
/// limited" and "degraded" are not mutually exclusive, and a picker that
/// derives its body from independent booleans grows a state nobody designed —
/// a spinner over stale results, or an empty grid that also says retry.
@immutable
class GifQueryState {
  const GifQueryState({
    required this.status,
    required this.query,
    required this.items,
    this.catalog,
    this.nextCursor,
    this.degraded = false,
    this.rateLimitedRetrySeconds,
    this.unavailableReason,
  });

  static const initial = GifQueryState(
    status: GifQueryStatus.idle,
    query: '',
    items: <GifAsset>[],
  );

  final GifQueryStatus status;
  final String query;
  final List<GifAsset> items;
  final GifCatalog? catalog;
  final String? nextCursor;

  /// The server served a cached or fallback page because the hour's provider
  /// budget was spent. The picker says "Showing popular GIFs" rather than
  /// presenting them as results for what was typed.
  final bool degraded;

  /// Non-null while a "slow down" line is showing. The GRID IS KEPT: a person
  /// who typed quickly should not lose what they were looking at.
  final int? rateLimitedRetrySeconds;

  final GifUnavailableReason? unavailableReason;

  bool get isTrending => query.isEmpty;
  bool get hasResults => items.isNotEmpty;

  GifQueryState copyWith({
    GifQueryStatus? status,
    String? query,
    List<GifAsset>? items,
    GifCatalog? catalog,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? degraded,
    int? rateLimitedRetrySeconds,
    bool clearRateLimit = false,
    GifUnavailableReason? unavailableReason,
  }) {
    return GifQueryState(
      status: status ?? this.status,
      query: query ?? this.query,
      items: items ?? this.items,
      catalog: catalog ?? this.catalog,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      degraded: degraded ?? this.degraded,
      rateLimitedRetrySeconds: clearRateLimit
          ? null
          : (rateLimitedRetrySeconds ?? this.rateLimitedRetrySeconds),
      unavailableReason: unavailableReason ?? this.unavailableReason,
    );
  }
}

/// Search state for one open picker, and the client half of the rate budget.
///
/// Four things happen here, and each of them is the difference between one
/// provider call and five:
///
///  * a 350 ms debounce, so a word typed at speed is one request;
///  * a minimum query length, so a single character never reaches the server
///    (trending needs none, and is what a person sees before typing);
///  * in-flight cancellation, so an older response can never overwrite a newer
///    one — the classic search race, and the reason [_generation] exists;
///  * a per-session memo keyed by `(query, cursor)`, so backspacing to a query
///    already fetched costs nothing at all.
///
/// The server enforces its own limits regardless. This is not a security
/// control; it is what keeps the client from spending the budget the server
/// then has to refuse.
class GifCatalogService extends ChangeNotifier {
  GifCatalogService({
    required GifTransport transport,
    Duration debounce = const Duration(milliseconds: 350),
    String locale = 'en',
  }) : _transport = transport,
       _debounce = debounce,
       _locale = locale;

  static const int minimumQueryLength = 2;
  static const int _memoCapacity = 40;

  final GifTransport _transport;
  final Duration _debounce;
  String _locale;

  GifQueryState _state = GifQueryState.initial;
  GifQueryState get state => _state;

  GifCatalog? _catalog;
  GifCatalog? get catalog => _catalog;

  Timer? _debounceTimer;
  Future<void>? _starting;
  int _generation = 0;
  int? _pagingGeneration;
  bool _disposed = false;

  final Map<String, GifSearchPage> _memo = <String, GifSearchPage>{};

  set locale(String value) {
    if (_locale == value) return;
    _locale = value;
    // A language change invalidates the memo: the same words return different
    // results, and serving the old ones would be a stale answer that looks
    // like a fresh one.
    _memo.clear();
  }

  /// Fetch availability, then the first trending page if it is available.
  ///
  /// Called on the first open of the GIF tab, not at app start: nothing should
  /// pay for a feature nobody has asked for yet.
  Future<void> start() {
    if (_disposed || _catalog?.available == true) return Future<void>.value();
    return _starting ??= _loadCatalog().whenComplete(() => _starting = null);
  }

  Future<void> _loadCatalog() async {
    _emit(_state.copyWith(status: GifQueryStatus.loading));
    final catalog = await _transport.catalog();
    if (_disposed) return;
    _catalog = catalog;
    if (!catalog.available) {
      _emit(
        _state.copyWith(
          status: GifQueryStatus.unavailable,
          catalog: catalog,
          unavailableReason:
              catalog.reason ?? GifUnavailableReason.notConfigured,
          items: const <GifAsset>[],
        ),
      );
      return;
    }
    _emit(_state.copyWith(catalog: catalog));
    // The person can type while availability is loading. Continue their
    // current query, not an initial trending query that would overwrite it.
    // Any still-pending debounce is replaced by this one immediate request.
    _debounceTimer?.cancel();
    final query = _state.query;
    if (query.isNotEmpty && query.length < minimumQueryLength) {
      _emit(
        _state.copyWith(
          status: _state.hasResults
              ? GifQueryStatus.ready
              : GifQueryStatus.idle,
          clearNextCursor: true,
        ),
      );
      return;
    }
    await _run(query, immediate: true);
  }

  /// A keystroke. Debounced, deduplicated and cancellable.
  void query(String value) {
    final trimmed = value.trim();
    if (trimmed == _state.query && _state.status != GifQueryStatus.error) {
      return;
    }
    _debounceTimer?.cancel();
    // Every keystroke invalidates any response still in flight, so a slow
    // answer for "ko" can never land on top of a fast one for "kotek".
    _generation += 1;
    if (trimmed.isNotEmpty && trimmed.length < minimumQueryLength) {
      // Below the floor we do not call the server and we do not clear the
      // grid: the person is mid-word, and an empty screen between two
      // keystrokes reads as a failure.
      _emit(
        _state.copyWith(
          query: trimmed,
          status: _state.hasResults
              ? GifQueryStatus.ready
              : GifQueryStatus.idle,
          // Retained results belong to the previous query. Their cursor
          // must not turn one character into a new provider request.
          clearNextCursor: true,
        ),
      );
      return;
    }
    _emit(_state.copyWith(query: trimmed, status: GifQueryStatus.loading));
    _debounceTimer = Timer(_debounce, () => unawaited(_run(trimmed)));
  }

  /// Retry after an error, or reload trending.
  Future<void> retry() {
    _generation += 1;
    return _run(_state.query, immediate: true, bypassMemo: true);
  }

  /// Fetch the next page and append it. Silently does nothing at the end of
  /// the results — an infinite scroll has no error state to show there.
  Future<void> loadMore() async {
    final cursor = _state.nextCursor;
    if (_disposed ||
        cursor == null ||
        _state.status == GifQueryStatus.loading ||
        _pagingGeneration == _generation) {
      return;
    }
    // _run advances the generation synchronously. Keep the grid visible,
    // but permit only one page request for that generation. A query change
    // cancels this guard logically, and an old completion cannot clear the
    // guard belonging to a newer query's page.
    final pageGeneration = _generation + 1;
    _pagingGeneration = pageGeneration;
    try {
      await _run(_state.query, cursor: cursor, immediate: true, append: true);
    } finally {
      if (_pagingGeneration == pageGeneration) _pagingGeneration = null;
    }
  }

  Future<void> _run(
    String query, {
    String? cursor,
    bool immediate = false,
    bool append = false,
    bool bypassMemo = false,
  }) async {
    if (_catalog?.available != true) return;
    final generation = ++_generation;
    if (!immediate) {
      _emit(_state.copyWith(status: GifQueryStatus.loading, query: query));
    }

    final key = '$query|${cursor ?? ''}';
    if (!bypassMemo && _memo.containsKey(key)) {
      _apply(_memo[key]!, query: query, append: append, generation: generation);
      return;
    }

    try {
      final page = await _transport.search(
        query: query,
        locale: _locale,
        cursor: cursor,
        limit: _catalog?.pageSize,
      );
      if (_disposed || generation != _generation) return;
      _remember(key, page);
      _apply(page, query: query, append: append, generation: generation);
    } on GifTransportException catch (error) {
      if (_disposed || generation != _generation) return;
      switch (error.failure) {
        case GifFailure.rateLimited:
          // Results are KEPT on purpose. Being told to slow down should not
          // also take away what you were looking at.
          _emit(
            _state.copyWith(
              status: _state.hasResults
                  ? GifQueryStatus.ready
                  : GifQueryStatus.idle,
              query: query,
              rateLimitedRetrySeconds: error.retryAfterSeconds ?? 3,
            ),
          );
        case GifFailure.unavailable:
          _catalog = const GifCatalog.unavailable(
            GifUnavailableReason.providerUnavailable,
          );
          _emit(
            _state.copyWith(
              status: GifQueryStatus.unavailable,
              query: query,
              items: const <GifAsset>[],
              unavailableReason: GifUnavailableReason.providerUnavailable,
            ),
          );
        case GifFailure.transient:
          _emit(_state.copyWith(status: GifQueryStatus.error, query: query));
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _emit(_state.copyWith(status: GifQueryStatus.error, query: query));
    }
  }

  void _apply(
    GifSearchPage page, {
    required String query,
    required bool append,
    required int generation,
  }) {
    if (generation != _generation) return;
    final items = append
        ? <GifAsset>[
            ..._state.items,
            ...page.items.where((item) => !_state.items.contains(item)),
          ]
        : page.items;
    _emit(
      GifQueryState(
        status: items.isEmpty ? GifQueryStatus.empty : GifQueryStatus.ready,
        query: query,
        items: List<GifAsset>.unmodifiable(items),
        catalog: _catalog,
        nextCursor: page.nextCursor,
        degraded: page.degraded,
      ),
    );
  }

  void _remember(String key, GifSearchPage page) {
    // A degraded page is a fallback, not an answer to what was asked, so it is
    // never memoized — otherwise one budget-exhausted minute would pin the
    // wrong results for the rest of the session.
    if (page.degraded) return;
    _memo[key] = page;
    while (_memo.length > _memoCapacity) {
      _memo.remove(_memo.keys.first);
    }
  }

  /// Report one asset. Returns true when the queue accepted it.
  Future<bool> report({
    required GifAsset asset,
    required String reason,
    String note = '',
    String? contextPath,
  }) async {
    try {
      await _transport.report(
        provider: asset.provider,
        gifId: asset.id,
        reason: reason,
        note: note,
        contextPath: contextPath,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _emit(GifQueryState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
