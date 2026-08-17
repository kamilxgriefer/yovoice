import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/features/moments/data/models/voice_moment.dart';

/// The server-owned pointer from a Creator profile to one canonical Voice
/// Moment. Billing details never enter this public projection; rules check the
/// canonical Creator entitlement on every exact-id read.
class CreatorPinnedPost {
  const CreatorPinnedPost({
    required this.creatorId,
    required this.momentId,
    required this.pinnedAt,
  });

  final String creatorId;
  final String momentId;
  final DateTime pinnedAt;

  static const _fields = {
    'schemaVersion',
    'creatorId',
    'momentId',
    'pinnedAt',
    'updatedAt',
  };
  static final RegExp _safeIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  factory CreatorPinnedPost.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final pinnedAt = data?['pinnedAt'];
    if (data == null ||
        data.length != _fields.length ||
        !data.keys.toSet().containsAll(_fields) ||
        data['schemaVersion'] != 1 ||
        data['creatorId'] != snapshot.id ||
        data['momentId'] is! String ||
        !_safeIdPattern.hasMatch(data['momentId'] as String) ||
        pinnedAt is! Timestamp) {
      throw const FormatException('Malformed Creator pinned post.');
    }
    return CreatorPinnedPost(
      creatorId: snapshot.id,
      momentId: data['momentId'] as String,
      pinnedAt: pinnedAt.toDate(),
    );
  }
}

class PinnedVoiceMoment {
  const PinnedVoiceMoment({required this.pin, required this.moment});

  final CreatorPinnedPost pin;
  final VoiceMoment moment;
}
