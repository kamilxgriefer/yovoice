import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

/// Why a Moment was dropped from the discovery pool. Kept as data rather
/// than folded into a single count, so the screen can tell the two
/// genuinely different empty states apart:
///
///  * the corpus really is empty (nobody has published), versus
///  * the corpus is NOT empty and everything in it was unplayable —
///    which is an upload-pipeline failure wearing a friendly
///    "no Moments yet" mask.
enum MomentDropReason {
  /// Author deleted it (or the integrity sweep marked it deleting).
  deleted,

  /// No audio URL: a draft, or an upload that never finished. Playing it
  /// would show a control that does nothing.
  unplayable,

  /// The viewer blocked this author.
  blockedAuthor,

  /// Past its chosen life, or marked expired by the sweeper. A document
  /// with no `expiresAt` at all is PERMANENT under the amended
  /// availability contract and is never dropped for this reason. The
  /// client filter is what covers the sweeper's ≤10-minute gap.
  expired,
}

/// The outcome of one discovery load. Every field is measured, never
/// assumed — the screen's copy ("that's all of them", "N of M") is
/// derived from these numbers and from nothing else.
@immutable
class MomentDiscoveryFeed {
  const MomentDiscoveryFeed({
    required this.moments,
    required this.fetchedCount,
    required this.drops,
    required this.seed,
    required this.poolExhausted,
  });

  /// Ranked, weighted-shuffled and author-spaced. Ready to page through.
  final List<VoiceMoment> moments;

  /// How many DISTINCT published Moments the two pool queries returned,
  /// before any client-side filtering. `fetchedCount == 0` is the only
  /// honest basis for "nobody has published a Voice Moment yet".
  final int fetchedCount;

  /// Why each dropped Moment was dropped. `drops.length ==
  /// fetchedCount - moments.length`.
  final Map<String, MomentDropReason> drops;

  /// The shuffle seed actually used. Held by the screen so the order is
  /// stable across rebuilds and different across sessions.
  final int seed;

  /// True when at least one pool query came back full, i.e. more
  /// published Moments exist than were fetched. When false, what you
  /// hold IS the entire published corpus and the end-of-stack copy may
  /// say so without lying.
  final bool poolExhausted;

  bool get isEmpty => moments.isEmpty;

  /// The corpus is genuinely empty — nobody has published anything.
  bool get corpusIsEmpty => fetchedCount == 0;

  /// Published Moments exist but none of them can be played. A distinct
  /// state on purpose: collapsing it into [corpusIsEmpty] is exactly how
  /// a broken upload path hides behind a pre-launch empty state.
  bool get everythingFiltered => fetchedCount > 0 && moments.isEmpty;
}

/// The two counters a Moment document carries that can change while it
/// is on screen.
///
/// Kept as its own type rather than a second [VoiceMoment]: a live
/// counter update must never be able to change WHICH Moment a tile is,
/// only how much engagement it reports.
@immutable
class MomentEngagement {
  const MomentEngagement({required this.likeCount, required this.commentCount});

  final int likeCount;
  final int commentCount;

  @override
  bool operator ==(Object other) =>
      other is MomentEngagement &&
      other.likeCount == likeCount &&
      other.commentCount == commentCount;

  @override
  int get hashCode => Object.hash(likeCount, commentCount);
}

/// The global Voice Moments discovery feed: every published Moment from
/// every user, shuffled, weighted so genuinely popular ones surface more
/// often.
///
/// Design constraints this class exists to absorb, all of them properties
/// of Firestore rather than choices:
///
///  * Firestore cannot order by a computed sum of two fields, so
///    `likeCount + commentCount` can never be an `orderBy`.
///  * Firestore cannot randomise server-side.
///  * `orderBy('likeCount')` SILENTLY OMITS any document missing the
///    field, which would make legacy Moments vanish with no error.
///
/// Both arithmetic problems are solved on a bounded, two-query union and
/// no new field is written to `voiceMoments` — deliberately. That
/// collection is validated server-side against an EXACT 20-key
/// allowlist (`functions/moments/integrity.js`, `validateMoment`), so an
/// added `score` field would not be an additive optional field: it would
/// break liking, commenting and deleting on every document carrying it.
class MomentDiscoveryService {
  MomentDiscoveryService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// How many documents each pool query fetches. Two pools, so a load
  /// costs at most 2x this in reads.
  static const int defaultPoolSize = 60;

  /// How far a single author's Moments are spread apart: at most
  /// [maxPerWindow] of any [spacingWindow] consecutive positions.
  static const int spacingWindow = 10;
  static const int maxPerWindow = 2;

  /// Comments count for half a like in the weighting.
  ///
  /// Not because a comment is worth less attention — because
  /// `commentCount` is the weaker signal of the two. The client-side
  /// Firestore rule that guards it (`firestore.rules`, the voiceMoments
  /// update block) permits a signed-in caller to increment it WITHOUT
  /// proving a comment document was created, while the like branch is
  /// bound to a `likes/{uid}` document. See the report accompanying this
  /// change for the proposed rule text that closes it.
  static const double commentWeight = 0.5;

  /// Sets how strongly engagement bends the shuffle. See
  /// [discoveryWeight].
  static const double popularityGain = 3.0;

  CollectionReference<Map<String, dynamic>> get _moments =>
      _firestore.collection('voiceMoments');

  /// The weight a Moment carries in the shuffle. Strictly increasing in
  /// both counters — more popular really does surface more — but
  /// LOGARITHMIC, which is the point.
  ///
  /// A linear weight makes a forged counter a jackpot: neither counter
  /// is currently bound tightly enough in `firestore.rules` for a linear
  /// weight to be safe (the author branch permits an author to write any
  /// field on their own Moment, including `likeCount`). Compressing the
  /// weight means the difference between an honest hit and a fabricated
  /// one is bounded:
  ///
  ///   engagement    0 -> 1.0      10 -> ~11.4
  ///   engagement  100 -> ~18.0    1e6 -> ~60.8
  ///
  /// A million fake likes buys roughly 60x the odds of a brand new
  /// Moment, not a million times. That is a ceiling on abuse, not a
  /// substitute for the rule fix.
  @visibleForTesting
  static double discoveryWeight(VoiceMoment moment) {
    final likes = moment.likeCount < 0 ? 0 : moment.likeCount;
    final comments = moment.commentCount < 0 ? 0 : moment.commentCount;
    final engagement = likes + commentWeight * comments;
    return 1 + popularityGain * (log(1 + engagement) / ln2);
  }

  /// One-pass weighted shuffle WITHOUT replacement (Efraimidis–Spirakis):
  /// draw `key = u^(1/w)` per item and sort by key descending.
  ///
  /// The `+1` floor inside [discoveryWeight] guarantees every weight is
  /// at least 1, so a Moment with zero engagement always has a real,
  /// non-zero chance of any position. Nothing in the corpus is ever
  /// unreachable — which matters most in a pre-launch product where
  /// almost everything has zero likes and a naive weighting would render
  /// the feed as a frozen hall of fame.
  @visibleForTesting
  static List<VoiceMoment> weightedShuffle(
    List<VoiceMoment> moments,
    Random random,
  ) {
    final keyed = <({VoiceMoment moment, double key})>[
      for (final moment in moments)
        (
          moment: moment,
          // nextDouble() can return exactly 0, whose key is 0 for every
          // weight — that would rank by input order, not by chance.
          key: pow(
            1e-12 + random.nextDouble() * (1 - 1e-12),
            1 / discoveryWeight(moment),
          ).toDouble(),
        ),
    ];
    keyed.sort((a, b) => b.key.compareTo(a.key));
    return [for (final entry in keyed) entry.moment];
  }

  /// Ranks strictly by engagement, most-engaged FIRST, with no randomness
  /// at all.
  ///
  /// [weightedShuffle] answers "surface the popular more often"; this
  /// answers the different question "put the most-engaged at the very
  /// top", which is what the avatar board shows by default. Both read the
  /// same [discoveryWeight], so there is exactly one definition of
  /// engagement in this codebase — a like plus half a comment, compressed
  /// logarithmically so a forged counter cannot buy the whole board.
  ///
  /// Total and deterministic: ties break on recency and then on id, so
  /// the board never reorders between two builds of the same data.
  /// Author spacing is deliberately NOT applied — spacing exists to stop
  /// one account owning a shuffled feed, and applying it here would push
  /// a genuinely top-ranked Moment down, which is the exact opposite of
  /// what this ordering is for.
  static List<VoiceMoment> rankByEngagement(List<VoiceMoment> moments) {
    final ranked = List<VoiceMoment>.of(moments);
    ranked.sort((a, b) {
      final byWeight = discoveryWeight(b).compareTo(discoveryWeight(a));
      if (byWeight != 0) return byWeight;
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
    return List<VoiceMoment>.unmodifiable(ranked);
  }

  /// Spreads one author out: at most [maxPerWindow] of any
  /// [spacingWindow] consecutive positions. Without this, a single
  /// prolific account owns a small corpus and the feed stops looking
  /// like discovery.
  ///
  /// Order-preserving and total: every input Moment appears exactly once
  /// in the output. When the constraint cannot be met (few authors, many
  /// Moments) the remainder is appended rather than dropped — a
  /// discovery feed must never silently lose real content to a cosmetic
  /// rule.
  @visibleForTesting
  static List<VoiceMoment> spaceAuthors(List<VoiceMoment> ranked) {
    final remaining = List<VoiceMoment>.of(ranked);
    final output = <VoiceMoment>[];

    while (remaining.isNotEmpty) {
      final windowStart = output.length - spacingWindow + 1;
      final recent = <String, int>{};
      for (var i = windowStart < 0 ? 0 : windowStart; i < output.length; i++) {
        recent.update(
          output[i].authorId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }

      var pickedIndex = remaining.indexWhere(
        (moment) => (recent[moment.authorId] ?? 0) < maxPerWindow,
      );
      // Nothing satisfies the constraint: take the next best rather than
      // dropping real Moments on the floor.
      if (pickedIndex < 0) pickedIndex = 0;
      output.add(remaining.removeAt(pickedIndex));
    }
    return output;
  }

  /// Drops what must never reach a discovery stack, and records WHY.
  ///
  /// Note what is deliberately NOT filtered on: `status == 'published'`.
  /// [VoiceMoment.isCanonicalPublished] additionally requires
  /// `schemaVersion == 2`, and the model defaults pre-Stage-B documents
  /// to `status: 'legacy'`, `schemaVersion: 0`. Filtering on canonical
  /// status would make every legacy Moment disappear from the feed with
  /// no error and no empty state — invisible data loss. `isPublished`
  /// is what both existing feeds already prove works in production.
  ///
  /// What IS filtered on since the expiry contract landed:
  /// [VoiceMoment.isActiveAt]. A Moment past its `expiresAt` or marked
  /// `status: 'expired'` by the sweeper is dropped as
  /// [MomentDropReason.expired] — the client-side half of the two-layer
  /// enforcement, covering the sweeper's ≤10-minute gap so a dead Moment
  /// never renders. A Moment with NO `expiresAt` is PERMANENT under the
  /// amended availability contract ("keep until deleted") and is kept.
  @visibleForTesting
  static ({List<VoiceMoment> kept, Map<String, MomentDropReason> drops})
  filterPlayable(
    List<VoiceMoment> moments, {
    Set<String> blockedAuthorIds = const <String>{},
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final kept = <VoiceMoment>[];
    final drops = <String, MomentDropReason>{};
    for (final moment in moments) {
      if (moment.isDeleted) {
        drops[moment.id] = MomentDropReason.deleted;
        continue;
      }
      if (!moment.isActiveAt(effectiveNow)) {
        drops[moment.id] = MomentDropReason.expired;
        continue;
      }
      if (blockedAuthorIds.contains(moment.authorId)) {
        drops[moment.id] = MomentDropReason.blockedAuthor;
        continue;
      }
      if (!moment.hasMediaReference) {
        drops[moment.id] = MomentDropReason.unplayable;
        continue;
      }
      kept.add(moment);
    }
    return (kept: kept, drops: drops);
  }

  /// The signed-in user's block list. One read per blocked account, and
  /// the set is tiny for every real account.
  ///
  /// KNOWN LIMITATION, stated rather than hidden: this covers only
  /// "I blocked them". "They blocked me" lives in THEIR `blocked`
  /// subcollection, which `firestore.rules` deliberately makes
  /// unreadable to the blocked party, and `setUserBlock` writes no
  /// reciprocal mirror. A global feed therefore cannot filter that
  /// direction from the client at all. See the report.
  Future<Set<String>> _blockedAuthorIds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const <String>{};
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('blocked')
        .get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  /// The most-liked published Moments, in order, unshuffled.
  ///
  /// For a small supporting module that says "Most liked" and means it.
  /// Deliberately NOT labelled trending or popular: this orders on
  /// `likeCount` alone, and a heading that implies a blended signal over
  /// a single-signal ordering is a fabricated one.
  ///
  /// Uses the same `isPublished ASC + likeCount DESC` composite index as
  /// the discovery pool, so it adds no index surface of its own.
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async {
    // Over-fetch, because unplayable documents are dropped below and a
    // module that asks for 3 and shows 1 looks broken.
    final snapshot = await _moments
        .where('isPublished', isEqualTo: true)
        .orderBy('likeCount', descending: true)
        .limit(limit * 4)
        .get();
    final moments = snapshot.docs
        .map(VoiceMoment.fromFirestore)
        .toList(growable: false);
    return filterPlayable(moments).kept.take(limit).toList(growable: false);
  }

  /// Fetches both pools, unions them, filters, weights and shuffles.
  ///
  /// Deliberately a ONE-SHOT `get()`, not `snapshots()`. On a globally
  /// ordered query, any like by any user anywhere near the pool boundary
  /// re-delivers documents — billing reads and, worse, re-ordering the
  /// stack under the user's finger while they are listening. Refresh is
  /// an explicit gesture instead.
  ///
  /// Throws whatever Firestore throws. The screen renders a real error
  /// state from it; a missing composite index surfaces as
  /// `failed-precondition` and MUST stay visible rather than being
  /// swallowed into an empty list.
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = defaultPoolSize,
    int? seed,
  }) async {
    final effectiveSeed = seed ?? DateTime.now().microsecondsSinceEpoch;

    // Two pools, because one is not enough:
    //
    //  * popularity alone freezes the feed into a hall of fame the
    //    moment the corpus outgrows the pool — nothing new is ever
    //    reachable, which is the opposite of discovery;
    //  * recency alone is not what was asked for.
    //
    // The union is what makes "weighted so the popular surface more"
    // and "from ALL users" both true at once.
    final results = await Future.wait([
      _moments
          .where('isPublished', isEqualTo: true)
          .orderBy('likeCount', descending: true)
          .limit(poolSize)
          .get(),
      _moments
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(poolSize)
          .get(),
    ]);

    final byId = <String, VoiceMoment>{};
    var anyPoolFull = false;
    for (final snapshot in results) {
      if (snapshot.docs.length >= poolSize) anyPoolFull = true;
      for (final document in snapshot.docs) {
        final moment = VoiceMoment.fromFirestore(document);
        byId[moment.id] = moment;
      }
    }

    Set<String> blocked = const <String>{};
    try {
      blocked = await _blockedAuthorIds();
    } catch (_) {
      // A block list that will not load must not take the feed down with
      // it, but it must not be treated as "nobody is blocked" either.
      // Fail closed on the only thing we can: hide nothing extra, and
      // let the caller know the list is unavailable by leaving it empty.
      // The alternative — failing the whole load — hides every Moment
      // because one small read failed, which is worse.
      blocked = const <String>{};
    }

    final fetched = byId.values.toList(growable: false);
    final filtered = filterPlayable(fetched, blockedAuthorIds: blocked);
    final ranked = weightedShuffle(filtered.kept, Random(effectiveSeed));

    return MomentDiscoveryFeed(
      moments: spaceAuthors(ranked),
      fetchedCount: fetched.length,
      drops: filtered.drops,
      seed: effectiveSeed,
      poolExhausted: anyPoolFull,
    );
  }

  /// Live `likeCount` / `commentCount` for the Moments on screen.
  ///
  /// This is the companion to [loadDiscoveryFeed]'s deliberate one-shot
  /// `get()`. That decision is right for the ORDER — a globally ordered
  /// `snapshots()` re-delivers on any like by anyone and would rearrange
  /// the board under the reader's finger — but it also froze the two
  /// counters, so a like or a comment made in the app only appeared after
  /// a full reload. Splitting the two is what fixes that: order stays
  /// fixed for the life of a load, counters stay live.
  ///
  /// ONE listener over the same recency pool the feed already reads, so
  /// it needs no new composite index and costs one document read per
  /// change rather than a re-query.
  ///
  /// KNOWN AND STATED, not hidden: this covers the [poolSize] most recent
  /// published Moments. In a corpus larger than that, an older Moment
  /// that only reached the board through the popularity pool keeps the
  /// counters it was loaded with — real numbers, just not live ones.
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = defaultPoolSize,
  }) {
    return _moments
        .where('isPublished', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(poolSize)
        .snapshots()
        .map((snapshot) {
          final counters = <String, MomentEngagement>{};
          for (final document in snapshot.docs) {
            final data = document.data();
            counters[document.id] = MomentEngagement(
              likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
              commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
            );
          }
          return counters;
        });
  }
}
