import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_text_channel_scene.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/fake_gif_transport.dart';

/// Photos and videos in a server text channel: the attach affordance, the
/// reserve -> upload -> finalize pipeline, the grant-backed bubbles and the
/// author's own retraction. No real Storage, no real callable: the service's
/// seams stand in, so what is asserted is this surface's own behaviour.
void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late PublicIdentityRepository identities;
  late GifCatalogService catalog;
  late List<(String, Map<String, Object?>)> calls;
  late List<Map<String, Object?>> uploads;

  const mediaId = 'cm_0123456789abcdef0123456789abcdef01234567';
  const mediaPath = 'server_message_media/club/general/me/$mediaId.jpg';
  const videoId = 'cm_fedcba9876543210fedcba9876543210fedcba98';
  const videoPath = 'server_message_media/club/general/other/$videoId.mp4';

  Map<String, Object?> mediaMessage({
    required String messageId,
    required String senderId,
    required String type,
    required String path,
    int? durationSeconds,
  }) => {
    'clubId': 'club',
    'channelId': 'general',
    'senderId': senderId,
    'senderName': senderId == 'me' ? 'Ja' : 'Ola',
    'content': type == 'image' ? 'Photo' : 'Video',
    'sentAt': Timestamp.fromDate(DateTime(2026, 9, 19, 20, 5)),
    'editedAt': null,
    'isDeleted': false,
    'type': type,
    'mediaUrl': 'gs://demo-bucket/$path',
    'media': {
      'schemaVersion': 1,
      'storagePath': path,
      'generation': '301',
      'contentType': type == 'image' ? 'image/jpeg' : 'video/mp4',
      'size': 4096,
      'durationSeconds': durationSeconds,
    },
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', isEmailVerified: true),
    );
    identities = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'uid': uid, 'staffRole': 'user', 'isVip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
    catalog = GifCatalogService(transport: FakeGifTransport());
    calls = [];
    uploads = [];
    await db.doc('clubs/club').set({'ownerId': 'owner', 'name': 'Club'});
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'member',
    });
  });

  tearDown(() {
    PublicIdentityRepository.instance = identities;
    catalog.dispose();
  });

  ClubChatService service({
    Object? failWith,
    List<String> unavailable = const <String>[],
    Future<void> Function()? beforeUpload,
    Future<Map<Object?, Object?>> Function(Map<String, Object?>)? moderation,
  }) => ClubChatService(
    firestore: db,
    auth: auth,
    requestIdFactory: () => 'media-request-1',
    moderationInvoker:
        moderation ??
        (_) async => <Object?, Object?>{
          'outcome': 'redacted',
          'redacted': true,
        },
    serverMessageInvoker: (name, request) async {
      calls.add((name, request));
      if (failWith != null) throw failWith;
      switch (name) {
        case 'reserveServerChannelMessageMediaV1':
          return <Object?, Object?>{
            'schemaVersion': 1,
            'serverId': 'club',
            'channelId': 'general',
            'messageId': mediaId,
            'expiresAtMillis': DateTime.now()
                .add(const Duration(minutes: 15))
                .millisecondsSinceEpoch,
            'media': {
              'storagePath': mediaPath,
              'type': request['type'],
              'contentType': request['contentType'],
              'size': request['size'],
              'durationSeconds': request['durationSeconds'],
              'uploadMetadata': {
                'yovoiceServerId': 'club',
                'yovoiceChannelId': 'general',
                'yovoiceOwnerUid': 'me',
                'yovoiceMessageId': mediaId,
                'yovoiceMessagePath':
                    'clubs/club/channels/general/messages/$mediaId',
                'yovoiceMediaType': request['type'],
              },
            },
          };
        case 'getServerChannelMessageMediaAccessV1':
          final ids = (request['messageIds']! as List).cast<String>();
          return <Object?, Object?>{
            'schemaVersion': 1,
            'serverId': 'club',
            'channelId': 'general',
            'expiresAtMillis': DateTime.now()
                .add(const Duration(seconds: 90))
                .millisecondsSinceEpoch,
            'grants': [
              for (final id in ids)
                if (!unavailable.contains(id))
                  {
                    'messageId': id,
                    'url':
                        'https://storage.googleapis.com/demo-bucket/$id?generation=301',
                    'type': id == videoId ? 'video' : 'image',
                    'contentType': id == videoId ? 'video/mp4' : 'image/jpeg',
                    'size': 4096,
                    'durationSeconds': id == videoId ? 7 : null,
                    'generation': '301',
                  },
            ],
            'unavailable': unavailable,
          };
        default:
          return <Object?, Object?>{'ok': true};
      }
    },
    mediaUploader:
        ({
          required String storagePath,
          required Uint8List bytes,
          required String contentType,
          required Map<String, String> customMetadata,
          void Function(double progress)? onProgress,
        }) async {
          uploads.add({
            'storagePath': storagePath,
            'size': bytes.lengthInBytes,
            'contentType': contentType,
            'metadata': customMetadata,
          });
          onProgress?.call(0.5);
          if (beforeUpload != null) await beforeUpload();
          return '301';
        },
  );

  Future<void> pump(
    WidgetTester tester,
    ClubChatService chatService, {
    Size size = const Size(390, 844),
    XFile? photo,
    XFile? video,
    Duration videoDuration = const Duration(seconds: 7),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ServerTextChannelScene(
            server: const Server(
              id: 'club',
              name: 'Friends server',
              description: '',
              ownerId: 'owner',
              type: ServerType.friends,
              privacy: ServerPrivacy.inviteOnly,
              defaultChannelId: 'general',
              schemaVersion: 1,
              activationState: 'active',
            ),
            channel: const ServerChannel(
              id: 'general',
              serverId: 'club',
              name: 'General',
              kind: ServerChannelKind.text,
              schemaVersion: 1,
            ),
            currentUserId: 'me',
            chatService: chatService,
            gifService: catalog,
            photoPicker: (_) async => photo,
            videoPicker: (_) async => video,
            videoInspector: (_) async => videoDuration,
            mediaImageBuilder: (context, url) => ColoredBox(
              key: ValueKey('server-media-image-$url'),
              color: const Color(0xFF123456),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('a media descriptor parses only when it is exactly right', () {
    ClubMessageMedia? parse(Map<String, Object?> overrides) =>
        ClubMessageMedia.fromMessage({
          ...mediaMessage(
            messageId: mediaId,
            senderId: 'me',
            type: 'image',
            path: mediaPath,
          ),
          ...overrides,
        });
    expect(parse(const {})!.type, 'image');
    expect(parse(const {})!.generation, '301');
    expect(parse(const {})!.durationSeconds, isNull);
    expect(parse(const {'isDeleted': true}), isNull);
    expect(parse(const {'type': 'gif'}), isNull);
    expect(parse(const {'media': 'nope'}), isNull);
    expect(
      parse(const {
        'media': {
          'schemaVersion': 1,
          'storagePath': 'users/victim/profile/avatar.jpg',
          'generation': '1',
          'contentType': 'image/jpeg',
          'size': 10,
          'durationSeconds': null,
        },
      }),
      isNull,
    );
    final video = ClubMessageMedia.fromMessage(
      mediaMessage(
        messageId: videoId,
        senderId: 'other',
        type: 'video',
        path: videoPath,
        durationSeconds: 7,
      ),
    );
    expect(video!.isVideo, isTrue);
    expect(video.durationSeconds, 7);
    expect(
      ClubMessageMedia.fromMessage(
        mediaMessage(
          messageId: videoId,
          senderId: 'other',
          type: 'video',
          path: videoPath,
          durationSeconds: 61,
        ),
      ),
      isNull,
    );
  });

  testWidgets(
    'the attach button rides in the composer and disappears with it',
    (tester) async {
      await pump(tester, service());
      expect(find.byKey(const ValueKey('server-attach')), findsOneWidget);
      await db.doc('clubs/club/members/me').set({
        'userId': 'me',
        'role': 'guest',
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-attach')), findsNothing);
    },
  );

  testWidgets(
    'picking a photo reserves, uploads the exact object and finalizes',
    (tester) async {
      final photo = XFile.fromData(
        Uint8List.fromList(List<int>.filled(4096, 7)),
        name: 'holiday.jpg',
        mimeType: 'image/jpeg',
      );
      await pump(tester, service(), photo: photo);
      await tester.tap(find.byKey(const ValueKey('server-attach')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-media-picker')), findsOneWidget);
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.$1), [
        'reserveServerChannelMessageMediaV1',
        'finalizeServerChannelMessageMediaV1',
      ]);
      expect(calls.first.$2, {
        'serverId': 'club',
        'channelId': 'general',
        'type': 'image',
        'contentType': 'image/jpeg',
        'size': 4096,
        'durationSeconds': null,
        'requestId': 'media-request-1',
      });
      expect(uploads.single['storagePath'], mediaPath);
      expect(uploads.single['contentType'], 'image/jpeg');
      expect(
        (uploads.single['metadata']! as Map)['yovoiceMessagePath'],
        'clubs/club/channels/general/messages/$mediaId',
      );
      expect(calls.last.$2['objectGeneration'], '301');
      expect(calls.last.$2['messageId'], mediaId);
    },
  );

  testWidgets(
    'a video pick carries its probed duration; an oversize photo never leaves the device',
    (tester) async {
      final video = XFile.fromData(
        Uint8List.fromList(List<int>.filled(8192, 3)),
        name: 'clip.mp4',
        mimeType: 'video/mp4',
      );
      await pump(tester, service(), video: video);
      await tester.tap(find.byKey(const ValueKey('server-attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Video library'));
      await tester.pumpAndSettle();
      expect(calls.first.$2['type'], 'video');
      expect(calls.first.$2['durationSeconds'], 7);

      calls.clear();
      uploads.clear();
      final huge = XFile.fromData(
        Uint8List(8 * 1024 * 1024 + 1),
        name: 'huge.jpg',
        mimeType: 'image/jpeg',
      );
      await pump(tester, service(), photo: huge);
      await tester.tap(find.byKey(const ValueKey('server-attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(uploads, isEmpty);
      expect(
        find.text('Your photo could not be sent. Try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a failed upload says so and shows the sending row while it runs',
    (tester) async {
      final photo = XFile.fromData(
        Uint8List.fromList(List<int>.filled(4096, 7)),
        name: 'holiday.jpg',
        mimeType: 'image/jpeg',
      );
      await pump(tester, service(failWith: StateError('nope')), photo: photo);
      await tester.tap(find.byKey(const ValueKey('server-attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your photo could not be sent. Try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-media-upload')), findsNothing);
    },
  );

  testWidgets('an image bubble renders from its grant and asks only once', (
    tester,
  ) async {
    await db
        .doc('clubs/club/channels/general/messages/$mediaId')
        .set(
          mediaMessage(
            messageId: mediaId,
            senderId: 'other',
            type: 'image',
            path: mediaPath,
          ),
        );
    await pump(tester, service());
    expect(
      find.byKey(const ValueKey('server-message-media-$mediaId')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'server-media-image-https://storage.googleapis.com/demo-bucket/$mediaId?generation=301',
        ),
      ),
      findsOneWidget,
    );
    expect(
      calls.where((call) => call.$1 == 'getServerChannelMessageMediaAccessV1'),
      hasLength(1),
    );
    final grantCall = calls.firstWhere(
      (call) => call.$1 == 'getServerChannelMessageMediaAccessV1',
    );
    expect(grantCall.$2['messageIds'], [mediaId]);
  });

  testWidgets('a video bubble shows a poster with its duration', (
    tester,
  ) async {
    await db
        .doc('clubs/club/channels/general/messages/$videoId')
        .set(
          mediaMessage(
            messageId: videoId,
            senderId: 'other',
            type: 'video',
            path: videoPath,
            durationSeconds: 7,
          ),
        );
    await pump(tester, service());
    expect(find.byKey(const ValueKey('server-media-play')), findsOneWidget);
    expect(find.text('0:07'), findsOneWidget);
  });

  testWidgets(
    'an unavailable object falls back to the Photo line, never an error',
    (tester) async {
      await db
          .doc('clubs/club/channels/general/messages/$mediaId')
          .set(
            mediaMessage(
              messageId: mediaId,
              senderId: 'other',
              type: 'image',
              path: mediaPath,
            ),
          );
      await pump(tester, service(unavailable: const [mediaId]));
      expect(find.text('Photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the author deletes their own media message through the callable',
    (tester) async {
      await db
          .doc('clubs/club/channels/general/messages/$mediaId')
          .set(
            mediaMessage(
              messageId: mediaId,
              senderId: 'me',
              type: 'image',
              path: mediaPath,
            ),
          );
      await pump(tester, service());
      await tester.longPress(
        find.byKey(const ValueKey('server-message-media-$mediaId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-message-delete')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('server-message-remove-confirm')),
      );
      await tester.pumpAndSettle();
      final deletes = calls.where(
        (call) => call.$1 == 'deleteServerChannelMessageV1',
      );
      expect(deletes, hasLength(1));
      expect(deletes.single.$2, {
        'serverId': 'club',
        'channelId': 'general',
        'messageId': mediaId,
        'requestId': 'media-request-1',
      });
    },
  );

  testWidgets(
    'a moderator removes somebody else\'s message through moderateClubMessage',
    (tester) async {
      await db.doc('clubs/club/members/me').set({
        'userId': 'me',
        'role': 'moderator',
      });
      final moderations = <Map<String, Object?>>[];
      await db
          .doc('clubs/club/channels/general/messages/$mediaId')
          .set(
            mediaMessage(
              messageId: mediaId,
              senderId: 'other',
              type: 'image',
              path: mediaPath,
            ),
          );
      await pump(
        tester,
        service(
          moderation: (request) async {
            moderations.add(request);
            return <Object?, Object?>{'outcome': 'redacted', 'redacted': true};
          },
        ),
      );
      await tester.longPress(
        find.byKey(const ValueKey('server-message-media-$mediaId')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-message-delete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('server-message-remove')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('server-message-remove-confirm')),
      );
      await tester.pumpAndSettle();
      expect(moderations, [
        {'clubId': 'club', 'channelId': 'general', 'messageId': mediaId},
      ]);
      expect(
        calls.where((call) => call.$1 == 'deleteServerChannelMessageV1'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'the media bubble keeps a readable measure at phone, tablet and desktop widths',
    (tester) async {
      await db
          .doc('clubs/club/channels/general/messages/$mediaId')
          .set(
            mediaMessage(
              messageId: mediaId,
              senderId: 'other',
              type: 'image',
              path: mediaPath,
            ),
          );
      for (final (width, expected) in const [
        (390.0, 280.0),
        (768.0, 360.0),
        (1440.0, 420.0),
      ]) {
        await pump(tester, service(), size: Size(width, 900));
        final box = tester.getSize(
          find.byKey(const ValueKey('server-message-media-$mediaId')),
        );
        expect(box.width, lessThanOrEqualTo(expected), reason: 'at $width');
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
    },
  );
}
