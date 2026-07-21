import 'package:cloud_firestore/cloud_firestore.dart';

class VoiceMoment {
  const VoiceMoment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhotoUrl,
    required this.caption,
    required this.audioUrl,
    required this.durationSeconds,
    required this.likeCount,
    required this.commentCount,
    required this.isPublished,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String caption;
  final String? audioUrl;
  final int durationSeconds;
  final int likeCount;
  final int commentCount;
  final bool isPublished;
  final DateTime? createdAt;

  factory VoiceMoment.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    return VoiceMoment(
      id: document.id,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'YoVoice user',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      caption: data['caption'] as String? ?? '',
      audioUrl: data['audioUrl'] as String?,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      isPublished: data['isPublished'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
