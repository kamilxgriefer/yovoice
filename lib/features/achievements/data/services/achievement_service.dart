import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../achievement_catalog.dart';
import '../models/achievement_definition.dart';

class AchievementService {
  AchievementService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> get _user =>
      _firestore.collection('users').doc(_uid);

  Future<List<AchievementDefinition>> incrementMetric(
    String metric, {
    int by = 1,
  }) async {
    if (by <= 0) return const <AchievementDefinition>[];

    return _firestore.runTransaction<List<AchievementDefinition>>((
      transaction,
    ) async {
      final snapshot = await transaction.get(_user);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final fieldName = _fieldForMetric(metric);
      final current = (data[fieldName] as num?)?.toInt() ?? 0;
      final next = current + by;

      final stats = <String, int>{
        'messages': (data['messageCount'] as num?)?.toInt() ?? 0,
        'followers': (data['followerCount'] as num?)?.toInt() ?? 0,
        'voiceMinutes': (data['voiceMinutes'] as num?)?.toInt() ?? 0,
        'rooms': (data['roomCount'] as num?)?.toInt() ?? 0,
        'communities': (data['communityCount'] as num?)?.toInt() ?? 0,
        'friends': (data['friendCount'] as num?)?.toInt() ?? 0,
        'reactions': (data['reactionCount'] as num?)?.toInt() ?? 0,
        'hostMinutes': (data['hostMinutes'] as num?)?.toInt() ?? 0,
        'activeDays': (data['activeDays'] as num?)?.toInt() ?? 0,
        'moments': (data['momentCount'] as num?)?.toInt() ?? 0,
      };

      stats[metric] = next;

      final previouslyUnlocked =
          (data['unlockedTitleIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toSet();
      final unlocked = AchievementCatalog.unlockedBy(stats);
      final newlyUnlocked = unlocked
          .where((achievement) => !previouslyUnlocked.contains(achievement.id))
          .toList(growable: false);
      final best = AchievementCatalog.bestUnlocked(stats);

      final unlockTimestamps = <String, dynamic>{
        ...(data['unlockedTitleTimestamps'] as Map<String, dynamic>? ??
            const <String, dynamic>{}),
        for (final achievement in newlyUnlocked)
          achievement.id: FieldValue.serverTimestamp(),
      };

      transaction.set(_user, {
        fieldName: next,
        'unlockedTitleIds': unlocked
            .map((item) => item.id)
            .toList(growable: false),
        'unlockedTitleTimestamps': unlockTimestamps,
        if (best != null && (data['selectedTitleId'] as String?) == null)
          'selectedTitleId': best.id,
        'achievementsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return newlyUnlocked;
    });
  }

  Future<void> refreshUnlockedTitles() async {
    final snapshot = await _user.get();
    final data = snapshot.data() ?? const <String, dynamic>{};

    int read(String key) => (data[key] as num?)?.toInt() ?? 0;

    final stats = {
      'messages': read('messageCount'),
      'followers': read('followerCount'),
      'voiceMinutes': read('voiceMinutes'),
      'rooms': read('roomCount'),
      'communities': read('communityCount'),
      'friends': read('friendCount'),
      'reactions': read('reactionCount'),
      'hostMinutes': read('hostMinutes'),
      'activeDays': read('activeDays'),
      'moments': read('momentCount'),
    };

    final unlocked = AchievementCatalog.unlockedBy(stats);
    final best = AchievementCatalog.bestUnlocked(stats);

    final previouslyUnlocked =
        (data['unlockedTitleIds'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toSet();
    final newlyUnlocked = unlocked.where(
      (achievement) => !previouslyUnlocked.contains(achievement.id),
    );
    final unlockTimestamps = <String, dynamic>{
      ...(data['unlockedTitleTimestamps'] as Map<String, dynamic>? ??
          const <String, dynamic>{}),
      for (final achievement in newlyUnlocked)
        achievement.id: FieldValue.serverTimestamp(),
    };

    await _user.set({
      'unlockedTitleIds': unlocked
          .map((item) => item.id)
          .toList(growable: false),
      'unlockedTitleTimestamps': unlockTimestamps,
      if (best != null && (data['selectedTitleId'] as String?) == null)
        'selectedTitleId': best.id,
      'achievementsUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> selectTitle(String achievementId) async {
    final snapshot = await _user.get();
    final unlocked =
        (snapshot.data()?['unlockedTitleIds'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<String>()
            .toSet();

    if (!unlocked.contains(achievementId)) {
      throw StateError('This title has not been unlocked.');
    }

    await _user.set({
      'selectedTitleId': achievementId,
    }, SetOptions(merge: true));
  }

  String _fieldForMetric(String metric) {
    return switch (metric) {
      'messages' => 'messageCount',
      'followers' => 'followerCount',
      'voiceMinutes' => 'voiceMinutes',
      'rooms' => 'roomCount',
      'communities' => 'communityCount',
      'friends' => 'friendCount',
      'reactions' => 'reactionCount',
      'hostMinutes' => 'hostMinutes',
      'activeDays' => 'activeDays',
      'moments' => 'momentCount',
      _ => throw ArgumentError.value(metric, 'metric', 'Unknown metric'),
    };
  }
}
