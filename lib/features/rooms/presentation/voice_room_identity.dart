import 'package:yovoice/core/theme/space_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

/// Resolves the visual identity from authoritative room/club models.
///
/// A club lounge is gold while its club document is loading, then becomes
/// emerald only when the immutable `Club.type` confirms it is a Family Room.
/// Names and document-id fragments never decide product identity.
SpaceIdentity voiceRoomIdentity(VoiceRoom room, {Club? club}) {
  if (room.isBroadcast) return SpaceIdentity.podcast;
  if (club != null) {
    return club.isFamilyRoom ? SpaceIdentity.family : SpaceIdentity.club;
  }
  if (room.isClubRoom) return SpaceIdentity.club;
  return SpaceIdentity.community;
}
