import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_message_controller.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';

const asset = GifAsset(
  provider: 'giphy',
  id: 'SafeId_1',
  title: 'Happy cat',
  rating: 'g',
  previewUrl: 'https://media.giphy.com/media/SafeId_1/200h.gif',
  url: 'https://media.giphy.com/media/SafeId_1/200h.gif',
  width: 320,
  height: 200,
);

void main() {
  for (final key in ['width', 'height']) {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('malformed $key $value is ignored without throwing', () {
        final wire = {...asset.toWire(), key: value};
        expect(GifAsset.fromWire(wire), isNull);
        expect(GifAsset.fromMessage(wire), isNull);
      });
    }
  }

  for (final entry in <String, Map<String, String>>{
    'sendDirectMessage': {'conversationId': 'chat'},
    'sendRoomMessage': {'roomId': 'room'},
    'sendClubMessage': {'clubId': 'club', 'channelId': 'general'},
  }.entries) {
    test(
      '${entry.key} sends only target, stable intent id and asset reference',
      () async {
        final calls = <Map<String, Object?>>[];
        final controller = GifMessageController(
          callable: entry.key,
          target: entry.value,
          currentUserId: () => 'me',
          invoke: (name, payload) async {
            expect(name, entry.key);
            calls.add(payload);
            if (calls.length == 1) {
              throw TimeoutException('acknowledgement lost');
            }
            return {...entry.value, 'messageId': 'committed'};
          },
        );
        addTearDown(controller.dispose);
        await controller.send(asset);
        expect(controller.asset, asset);
        expect(controller.canRetry, isTrue);
        expect(calls.single.keys.toSet(), {
          ...entry.value.keys,
          'requestId',
          'gif',
        });
        expect(calls.single['gif'], {'provider': 'giphy', 'id': 'SafeId_1'});
        await controller.retry();
        expect(calls[1], calls[0]);
        expect(controller.asset, isNull);
      },
    );
  }

  for (final code in ['invalid-argument', 'failed-precondition', 'not-found']) {
    test(
      '$code keeps a disabled old-server/provider failure with no text write',
      () async {
        var calls = 0;
        final controller = GifMessageController(
          callable: 'sendDirectMessage',
          target: {'conversationId': 'chat'},
          currentUserId: () => 'me',
          invoke: (_, _) async {
            calls++;
            throw FirebaseFunctionsException(
              code: code,
              message: 'unavailable',
            );
          },
        );
        addTearDown(controller.dispose);
        await controller.send(asset, replyToMessageId: 'reply');
        expect(controller.failure, GifSendFailure.unavailable);
        expect(controller.canRetry, isFalse);
        await controller.retry();
        expect(calls, 1);
      },
    );
  }

  test('a second selection cannot replace an in-flight send', () async {
    final gate = Completer<Object?>();
    var calls = 0;
    final controller = GifMessageController(
      callable: 'sendRoomMessage',
      target: {'roomId': 'room'},
      currentUserId: () => 'me',
      invoke: (_, _) {
        calls++;
        return gate.future;
      },
    );
    addTearDown(controller.dispose);
    final sending = controller.send(asset);
    await controller.send(asset);
    expect(calls, 1);
    expect(controller.sending, isTrue);
    gate.complete({'roomId': 'room', 'messageId': 'message'});
    await sending;
    expect(controller.asset, isNull);
  });

  test('retry cannot carry an old account intent to a new account', () async {
    var uid = 'first';
    var calls = 0;
    final controller = GifMessageController(
      callable: 'sendRoomMessage',
      target: {'roomId': 'room'},
      currentUserId: () => uid,
      invoke: (_, _) async {
        calls++;
        throw TimeoutException('offline');
      },
    );
    addTearDown(controller.dispose);
    await controller.send(asset);
    uid = 'second';
    expect(controller.asset, isNull);
    await controller.retry();
    expect(calls, 1);
  });

  test(
    'malformed acknowledgement preserves the original retry intent',
    () async {
      final controller = GifMessageController(
        callable: 'sendRoomMessage',
        target: {'roomId': 'room'},
        currentUserId: () => 'me',
        invoke: (_, _) async => {'roomId': 'other', 'messageId': 'm'},
      );
      addTearDown(controller.dispose);
      await controller.send(asset);
      expect(controller.canRetry, isTrue);
      expect(controller.asset, asset);
    },
  );

  test(
    'message parser rejects remote beacons, traversals and invalid dimensions',
    () {
      for (final changed in <Map<String, Object?>>[
        {'url': 'https://tracking.example/pixel'},
        {'url': '${asset.url}?tracking=1'},
        {'id': '../x'},
        {'provider': 'unknown'},
        {'width': -1},
        {'height': 0},
      ]) {
        expect(GifAsset.fromMessage({...asset.toWire(), ...changed}), isNull);
      }
      expect(GifAsset.fromMessage(asset.toWire()), asset);
    },
  );

  test('all three parsers hide GIF metadata in legacy tombstones', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('fixtures').doc('message');
    await ref.set({
      'type': 'gif',
      'gif': asset.toWire(),
      'isDeleted': true,
      'senderId': 'sender',
      'content': 'GIF: Happy cat',
      'text': 'GIF: Happy cat',
    });
    final snapshot = await ref.get();
    expect(Message.fromFirestore(snapshot).gif, isNull);
    expect(RoomMessage.fromFirestore(snapshot).gif, isNull);
    expect(
      ClubMessage.fromFirestore(
        clubId: 'club',
        channelId: 'general',
        document: snapshot,
      ).gif,
      isNull,
    );
  });
}
