import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/channel_session.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';

void main() {
  test('five server types never change the two room experiences', () {
    expect(ServerType.values.length, 5);
    expect(RoomExperience.values, [
      RoomExperience.community,
      RoomExperience.broadcast,
    ]);
    expect(RoomExperience.fromValue('podcast'), RoomExperience.broadcast);
  });

  test('legacy families retain the private boundary and identifiers', () {
    final family = Server.fromMap('family_owner', {
      'name': 'Nasz dom',
      'ownerId': 'owner',
      'type': 'family',
      'defaultChatChannelId': 'chat',
      'loungeRoomId': 'old-room',
    });
    expect(family.type, ServerType.family);
    expect(family.privacy, ServerPrivacy.inviteOnly);
    expect(family.isLegacy, isTrue);
    expect(family.id, 'family_owner');
    expect(family.loungeRoomId, 'old-room');
  });

  test('unsupported V1 values fail closed rather than becoming public', () {
    final root = <String, dynamic>{
      'serverSchemaVersion': 1,
      'serverType': 'company',
      'name': 'Team',
      'ownerId': 'owner',
      'privacy': 'inviteOnly',
      'serverActivationState': 'held',
    };
    expect(Server.fromMap('s', root).isHeld, isTrue);
    for (final mutation in [
      {'serverType': 'future'},
      {'privacy': 'future'},
      {'privacy': 'public'},
      {'serverSchemaVersion': 2},
    ]) {
      expect(
        () => Server.fromMap('s', {...root, ...mutation}),
        throwsFormatException,
      );
    }
  });

  test('channel preserves its own room instead of substituting the lounge', () {
    final voice = ServerChannel.fromMap('server', 'gaming', {
      'name': 'Gaming',
      'type': 'voice',
      'roomId': 'gaming-room',
      'experience': 'podcast',
    });
    expect(voice.roomId, 'gaming-room');
    expect(voice.experience, RoomExperience.broadcast);
  });

  test('V1 channel requires binding, access and explicit media contracts', () {
    final channel = <String, dynamic>{
      'serverSchemaVersion': 1,
      'serverId': 's',
      'kind': 'stage',
      'name': 'Studio LIVE',
      'roomId': 'r',
      'experience': 'broadcast',
      'mediaMode': 'audio',
      'accessMode': 'members',
      'isPrivate': false,
      'status': 'active',
    };
    expect(
      ServerChannel.fromMap('s', 'c', channel).kind,
      ServerChannelKind.stage,
    );
    for (final mutation in [
      {'serverId': 'other'},
      {'accessMode': 'future'},
      {'isPrivate': true},
      {'roomId': null},
      {'experience': 'podcast'},
      {'mediaMode': 'screen'},
    ]) {
      expect(
        () => ServerChannel.fromMap('s', 'c', {...channel, ...mutation}),
        throwsFormatException,
      );
    }
  });

  test('session lifecycle is separate from server lifetime', () {
    final session = ChannelSession.fromMap({
      'serverId': 's',
      'channelId': 'c',
      'roomId': 'r',
      'sessionId': 'g',
      'experience': 'broadcast',
      'mediaMode': 'audio',
      'status': 'ended',
    });
    expect(session.status, ChannelSessionStatus.ended);
    expect(session.serverId, 's');
    expect(
      () => ChannelSession.fromMap({'status': 'future'}),
      throwsFormatException,
    );
  });

  test(
    'creation result rejects a default channel outside its returned graph',
    () {
      expect(
        () => ServerCreationResult.fromMap({
          'serverId': 's',
          'defaultChannelId': 'outside',
          'channelIds': ['c'],
          'alreadyExisted': false,
        }),
        throwsFormatException,
      );
    },
  );
}
