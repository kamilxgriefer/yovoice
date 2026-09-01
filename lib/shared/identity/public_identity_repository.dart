import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/shared/identity/public_identity.dart';

/// The one way a client learns anyone's official role and VIP state.
///
/// Reads ONLY the server-written publicBadges projection, through the
/// bounded `getPublicBadges` callable — never a private user document,
/// and never a role or VIP field embedded in a message, which would be
/// whatever the sender's client claimed at write time.
///
/// Built so that a list of a hundred messages costs at most a couple of
/// requests, not a hundred:
///
///  * every lookup within one flush window (a few frames) coalesces into
///    a single batched call, chunked to the callable's 20-uid bound;
///  * results are cached in memory for the session;
///  * a uid already being fetched is never requested twice (in-flight
///    dedup);
///  * the cache empties the moment the signed-in account changes;
///  * any failure resolves to [PublicIdentity.fallback] — an ordinary
///    USER badge, never a staff claim and never an error state.
///
/// [revision] bumps whenever cached identities may have changed (after
/// [invalidate]); badge widgets listen and re-resolve, which is how a
/// role assignment or VIP change made in Staff Center propagates to
/// everything on screen without a restart.
class PublicIdentityRepository {
  PublicIdentityRepository({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    @visibleForTesting
    Future<Map<String, dynamic>> Function(List<String> uids)? fetchOverride,
    @visibleForTesting Duration? flushDelay,
  }) : _functionsOverride = functions,
       _auth = auth,
       _fetchOverride = fetchOverride,
       _flushDelay = flushDelay ?? const Duration(milliseconds: 40);

  /// The app-wide instance. Tests swap it for one with a fake fetcher and
  /// restore it afterwards.
  static PublicIdentityRepository instance = PublicIdentityRepository();

  /// The callable's hard request bound; larger sets are chunked.
  static const int maxBatchSize = 20;

  final FirebaseFunctions? _functionsOverride;
  final FirebaseAuth? _auth;
  final Future<Map<String, dynamic>> Function(List<String> uids)?
  _fetchOverride;
  final Duration _flushDelay;

  final Map<String, PublicIdentity> _cache = <String, PublicIdentity>{};
  final Map<String, List<Completer<PublicIdentity>>> _pending =
      <String, List<Completer<PublicIdentity>>>{};
  final Set<String> _inFlight = <String>{};
  Timer? _flushTimer;
  String? _cacheAccountUid;

  /// Bumped by [invalidate]; listeners re-resolve what they display.
  final ChangeNotifier revision = _RevisionNotifier();

  String? get _currentAccountUid {
    try {
      return (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    } catch (_) {
      // Firebase not initialized (widget tests): behave as signed out.
      return null;
    }
  }

  /// Drops every cached identity the moment the signed-in account is not
  /// the one the cache was built under — a signed-out session must not
  /// inherit the previous account's view.
  void _guardAccount() {
    final uid = _currentAccountUid;
    if (uid != _cacheAccountUid) {
      _cache.clear();
      _cacheAccountUid = uid;
    }
  }

  /// The cached identity, if resolution already landed. Never triggers a
  /// request — callers wanting one use [resolve].
  PublicIdentity? peek(String uid) {
    _guardAccount();
    return _cache[uid];
  }

  /// Resolves one uid, batched with every other resolution requested in
  /// the same flush window.
  Future<PublicIdentity> resolve(String uid) {
    _guardAccount();

    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return Future.value(PublicIdentity.fallback);

    final cached = _cache[cleanUid];
    if (cached != null) return Future.value(cached);

    // Signed out: the callable would refuse anyway; the safe answer is
    // immediate.
    if (_currentAccountUid == null) {
      return Future.value(PublicIdentity.fallback);
    }

    final completer = Completer<PublicIdentity>();
    _pending.putIfAbsent(cleanUid, () => <Completer<PublicIdentity>>[]);
    _pending[cleanUid]!.add(completer);
    _flushTimer ??= Timer(_flushDelay, _flush);
    return completer.future;
  }

  /// Primes the cache for a known-visible set (a page of participants, a
  /// screenful of messages). Same batching path as [resolve].
  Future<Map<String, PublicIdentity>> resolveAll(Iterable<String> uids) async {
    final unique = uids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet();
    final entries = await Future.wait(
      unique.map((uid) async => MapEntry(uid, await resolve(uid))),
    );
    return Map<String, PublicIdentity>.fromEntries(entries);
  }

  /// Forgets one uid (or everything, when null) and tells listening
  /// badges to re-resolve. Called after a role assignment, a VIP change,
  /// or any server action that rewrites a badge.
  void invalidate([String? uid]) {
    if (uid == null) {
      _cache.clear();
    } else {
      _cache.remove(uid.trim());
    }
    (revision as _RevisionNotifier).bump();
  }

  /// Full reset — account switch or sign-out.
  void clear() {
    _cache.clear();
    _cacheAccountUid = _currentAccountUid;
    (revision as _RevisionNotifier).bump();
  }

  Future<void> _flush() async {
    _flushTimer = null;

    // A uid already on the wire stays with its existing completers; only
    // genuinely new uids form the next request.
    final batch = _pending.keys
        .where((uid) => !_inFlight.contains(uid))
        .toList(growable: false);
    if (batch.isEmpty) return;
    _inFlight.addAll(batch);

    for (var start = 0; start < batch.length; start += maxBatchSize) {
      final chunk = batch.sublist(
        start,
        start + maxBatchSize > batch.length
            ? batch.length
            : start + maxBatchSize,
      );
      Map<String, dynamic> badges;
      var failed = false;
      try {
        badges = await _fetch(chunk);
      } catch (_) {
        badges = const <String, dynamic>{};
        failed = true;
      }

      for (final uid in chunk) {
        final raw = badges[uid];
        // Absence is the DESIGNED common case — an ordinary account has
        // no badge document — so it caches as the fallback. A failed
        // request also answers with the fallback but is NOT cached, so a
        // later screen retries instead of freezing a transient error.
        final identity = raw is Map
            ? PublicIdentity.fromWire(Map<String, dynamic>.from(raw))
            : PublicIdentity.fallback;
        if (!failed) _cache[uid] = identity;

        final waiters = _pending.remove(uid) ?? const [];
        _inFlight.remove(uid);
        for (final waiter in waiters) {
          waiter.complete(identity);
        }
      }
    }
  }

  Future<Map<String, dynamic>> _fetch(List<String> uids) async {
    if (_fetchOverride != null) return _fetchOverride(uids);
    final functions =
        _functionsOverride ??
        FirebaseFunctions.instanceFor(region: 'europe-west1');
    final result = await functions
        .httpsCallable('getPublicBadges')
        .call<Map<String, dynamic>>(<String, dynamic>{'uids': uids});
    return Map<String, dynamic>.from(result.data['badges'] as Map? ?? const {});
  }
}

class _RevisionNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
