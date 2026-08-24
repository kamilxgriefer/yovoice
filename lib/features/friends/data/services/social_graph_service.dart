import 'package:cloud_functions/cloud_functions.dart';

class MutualFriendsSummary {
  const MutualFriendsSummary({required this.count, required this.sample});

  final int count;
  final List<SuggestedFriend> sample;

  static const empty = MutualFriendsSummary(count: 0, sample: []);
}

class SuggestedFriend {
  const SuggestedFriend({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.mutualCount,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final int mutualCount;

  factory SuggestedFriend.fromMap(Map<Object?, Object?> map) {
    return SuggestedFriend(
      uid: map['uid'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'YO Voice user',
      photoUrl: map['photoUrl'] as String?,
      mutualCount: (map['mutualCount'] as num?)?.toInt() ?? 0,
    );
  }

  String get initial =>
      displayName.trim().isNotEmpty ? displayName.trim()[0].toUpperCase() : '?';
}

/// Mutual-friend and friend-suggestion computation both require reading
/// OTHER users' friend lists, which `friends/{id}` deliberately keeps
/// owner-read-only in firestore.rules (friend lists are private). Both are
/// computed server-side via callable Cloud Functions instead of loosening
/// that rule — see functions/friends/social_graph.js.
class SocialGraphService {
  SocialGraphService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;

  // Resolved lazily (same pattern as FriendService) so a test double that
  // overrides every callable-backed method can be constructed without an
  // initialised Firebase app.
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async {
    final callable = _functions.httpsCallable('getMutualFriends');
    final result = await callable.call<Map<Object?, Object?>>({
      'targetUserId': targetUserId,
    });
    final data = result.data;
    final sample = (data['sample'] as List<Object?>? ?? const [])
        .map((entry) => SuggestedFriend.fromMap(entry as Map<Object?, Object?>))
        .toList(growable: false);
    return MutualFriendsSummary(
      count: (data['count'] as num?)?.toInt() ?? 0,
      sample: sample,
    );
  }

  Future<List<SuggestedFriend>> getFriendSuggestions({int limit = 10}) async {
    final callable = _functions.httpsCallable('getFriendSuggestions');
    final result = await callable.call<Map<Object?, Object?>>({'limit': limit});
    final data = result.data;
    return (data['suggestions'] as List<Object?>? ?? const [])
        .map((entry) => SuggestedFriend.fromMap(entry as Map<Object?, Object?>))
        .toList(growable: false);
  }
}
