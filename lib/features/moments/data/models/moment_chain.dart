import 'package:flutter/foundation.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

/// One author's ordered run of active Voice Moments — the unit the story
/// strip and the story viewer both consume.
///
/// Order INSIDE a chain is oldest → newest, because a story is listened
/// to in the order it was told. The order is derived from `createdAt`
/// at build time; nothing stores a sequence number, so there is no second
/// source of truth to drift (ties break on id so the order is total and
/// stable across rebuilds).
@immutable
class MomentChain {
  MomentChain({required this.moments})
    : assert(moments.isNotEmpty, 'A chain cannot be empty.');

  /// Oldest first. Every Moment shares one `authorId`.
  final List<VoiceMoment> moments;

  String get authorId => moments.first.authorId;
  String get authorName => moments.last.authorName;
  String? get authorPhotoUrl => moments.last.authorPhotoUrl;

  int get length => moments.length;

  /// When this author last posted — what the strip sorts on.
  DateTime? get newestCreatedAt => moments.last.createdAt;

  /// A chain is unviewed while ANY of its Moments lacks the caller's
  /// `momentViews` doc. Fully viewed only when every link has been heard.
  bool hasUnviewed(Set<String> viewedMomentIds) =>
      moments.any((moment) => !viewedMomentIds.contains(moment.id));

  /// Where the viewer should open: the first Moment the caller has not
  /// viewed yet, or the start of the chain when everything was heard.
  int firstUnviewedIndex(Set<String> viewedMomentIds) {
    final index = moments.indexWhere(
      (moment) => !viewedMomentIds.contains(moment.id),
    );
    return index < 0 ? 0 : index;
  }
}

/// Groups active Moments into per-author chains.
///
///  * within one author: oldest → newest (`createdAt` ascending, ties on
///    id — a total order, so two builds of the same data never disagree);
///  * across authors: the author with the NEWEST Moment first, which is
///    what puts the freshest voice at the front of the strip.
///
/// The input is expected to be already expiry-filtered; this function
/// does not re-check `expiresAt` so a test can hand it any corpus.
List<MomentChain> buildMomentChains(List<VoiceMoment> moments) {
  final byAuthor = <String, List<VoiceMoment>>{};
  for (final moment in moments) {
    if (moment.authorId.isEmpty) continue;
    byAuthor.putIfAbsent(moment.authorId, () => <VoiceMoment>[]).add(moment);
  }

  DateTime dateOf(VoiceMoment moment) =>
      moment.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final chains = <MomentChain>[];
  for (final run in byAuthor.values) {
    run.sort((a, b) {
      final byDate = dateOf(a).compareTo(dateOf(b));
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
    chains.add(MomentChain(moments: List<VoiceMoment>.unmodifiable(run)));
  }

  chains.sort((a, b) {
    final aNewest = a.newestCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bNewest = b.newestCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byNewest = bNewest.compareTo(aNewest);
    if (byNewest != 0) return byNewest;
    return a.authorId.compareTo(b.authorId);
  });
  return List<MomentChain>.unmodifiable(chains);
}
