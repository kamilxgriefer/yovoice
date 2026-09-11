import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/media/data/models/gif_asset.dart';

/// Why a GIF call failed, in terms the picker can render.
///
/// A closed set rather than a raw `FirebaseFunctionsException`, because the
/// picker has to say something different for each: "slow down" keeps the
/// results on screen, "unavailable" flips the whole tab to its disabled state,
/// and a transient failure offers Retry.
enum GifFailure {
  /// Per-account token bucket. The grid is KEPT and a "slow down" line is
  /// shown; clearing results would punish somebody for typing quickly.
  rateLimited,

  /// The server says the feature is off — no provider, no key, kill switch, or
  /// an open circuit breaker. The tab goes to its disabled+labelled state.
  unavailable,

  /// Network, timeout, or anything else. Offer Retry.
  transient,
}

@immutable
class GifTransportException implements Exception {
  const GifTransportException(this.failure, {this.retryAfterSeconds});

  final GifFailure failure;

  /// Present on [GifFailure.rateLimited]: what the server said to wait.
  final int? retryAfterSeconds;

  @override
  String toString() => 'GifTransportException($failure)';
}

/// The seam between the picker and the Cloud Functions proxy.
///
/// It exists so every client state — available, unavailable, empty, error,
/// rate-limited, degraded — is reachable in a widget test without a network,
/// a Firebase project, or an API key. `FakeGifTransport` in
/// `test/support/fake_gif_transport.dart` is the other implementation.
abstract interface class GifTransport {
  /// Availability, attribution and page size. Binds no secret server-side, so
  /// it answers honestly even when nothing is configured.
  Future<GifCatalog> catalog();

  /// A page of results. An empty [query] means trending — trending is not a
  /// separate endpoint and not a separate cold start.
  Future<GifSearchPage> search({
    required String query,
    required String locale,
    String? cursor,
    int? limit,
  });

  /// Files an asset-level report into the moderation queue that already
  /// exists. Never throws for an already-filed report: reporting twice is a
  /// successful, idempotent outcome.
  Future<void> report({
    required String provider,
    required String gifId,
    required String reason,
    String note,
    String? contextPath,
  });
}

/// The real transport. Region-pinned like every other callable client in the
/// app; the API key lives only in Secret Manager and is never sent here.
class FunctionsGifTransport implements GifTransport {
  FunctionsGifTransport({
    FirebaseFunctions? functions,
    String Function()? requestIdFactory,
  }) : _functionsOverride = functions,
       _requestIdFactory = requestIdFactory ?? _defaultRequestId;

  final FirebaseFunctions? _functionsOverride;
  final String Function() _requestIdFactory;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static int _requestCounter = 0;

  static String _defaultRequestId() {
    _requestCounter += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'gif-$stamp-$_requestCounter';
  }

  @override
  Future<GifCatalog> catalog() async {
    try {
      final result = await _functions
          .httpsCallable('getGifCatalog')
          .call<Object?>(const <String, Object?>{});
      return GifCatalog.fromWire(result.data);
    } on FirebaseFunctionsException catch (error) {
      // `not-found` is the ordinary answer when GIF_PROVIDER names nothing and
      // the secret-bound callables were never registered — not an error state.
      if (error.code == 'not-found' || error.code == 'failed-precondition') {
        return const GifCatalog.unavailable(GifUnavailableReason.notConfigured);
      }
      return const GifCatalog.unavailable(GifUnavailableReason.unreachable);
    } catch (_) {
      return const GifCatalog.unavailable(GifUnavailableReason.unreachable);
    }
  }

  @override
  Future<GifSearchPage> search({
    required String query,
    required String locale,
    String? cursor,
    int? limit,
  }) async {
    try {
      final result = await _functions.httpsCallable('searchGifs').call<Object?>(
        <String, Object?>{
          'query': query,
          'locale': locale,
          'cursor': ?cursor,
          'limit': ?limit,
        },
      );
      return GifSearchPage.fromWire(result.data);
    } on FirebaseFunctionsException catch (error) {
      throw GifTransportException(
        _failureFor(error),
        retryAfterSeconds: _retryAfter(error),
      );
    } catch (_) {
      throw const GifTransportException(GifFailure.transient);
    }
  }

  @override
  Future<void> report({
    required String provider,
    required String gifId,
    required String reason,
    String note = '',
    String? contextPath,
  }) async {
    try {
      await _functions
          .httpsCallable('reportGifAsset')
          .call<Object?>(<String, Object?>{
            'provider': provider,
            'gifId': gifId,
            'reason': reason,
            'note': note,
            'contextPath': ?contextPath,
            'requestId': _requestIdFactory(),
          });
    } on FirebaseFunctionsException catch (error) {
      // `not-found` here means THIS asset is gone, not that the feature is
      // off — the opposite meaning it carries on the search path — so it must
      // not flip the whole tab to its disabled state.
      throw GifTransportException(
        _failureFor(error, notFoundIsUnavailable: false),
      );
    } catch (_) {
      throw const GifTransportException(GifFailure.transient);
    }
  }

  static GifFailure _failureFor(
    FirebaseFunctionsException error, {
    bool notFoundIsUnavailable = true,
  }) {
    if (error.code == 'resource-exhausted') return GifFailure.rateLimited;
    if (error.code == 'failed-precondition') return GifFailure.unavailable;
    if (error.code == 'not-found') {
      return notFoundIsUnavailable
          ? GifFailure.unavailable
          : GifFailure.transient;
    }
    return GifFailure.transient;
  }

  static int? _retryAfter(FirebaseFunctionsException error) {
    final details = error.details;
    if (details is Map) {
      final value = details['retryAfterSeconds'];
      if (value is int) return value;
      if (value is num) return value.round();
    }
    return null;
  }
}
