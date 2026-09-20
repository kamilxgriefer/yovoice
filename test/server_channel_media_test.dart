import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_message.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_media_upload_source.dart';
// The browser implementation, reached directly: the conditional import picks
// the io one under `flutter test`, and the web path still has to be proven.
import 'package:yovoice/features/clubs/data/services/club_media_upload_source_web.dart'
    as web_source;
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_text_channel_scene.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/media/yo_media_send_review.dart';

import 'support/fake_gif_transport.dart';

/// A pick that cannot be read into memory at all, and knows its own size.
///
/// Every byte-shaped read throws, so any code path that still needs the whole
/// photo or video resident fails loudly instead of quietly costing the heap it
/// used to cost. It also lets a 64 MiB bound be exercised without allocating
/// 64 MiB.
class _UnreadableXFile extends XFile {
  _UnreadableXFile(super.path, {required int declaredLength, super.mimeType})
    : _declaredLength = declaredLength;

  final int _declaredLength;

  @override
  Future<int> length() async => _declaredLength;

  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('the pick must not be read into memory');

  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      throw StateError('the pick must not be read into memory');
}

/// A real file on disk, because `putFile` streams a real file.
Future<File> _tempFile(String name, int length) async {
  final directory = await Directory.systemTemp.createTemp('yo_server_media');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(Uint8List(length), flush: true);
  return file;
}

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
    MockFirebaseStorage? uploadInto,
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
          required ClubMediaUploadSource source,
          required String contentType,
          required Map<String, String> customMetadata,
          void Function(double progress)? onProgress,
        }) async {
          uploads.add({
            'storagePath': storagePath,
            // What the reservation declares, measured without reading the pick.
            'size': source.length,
            'contentType': contentType,
            'metadata': customMetadata,
          });
          onProgress?.call(0.5);
          if (uploadInto != null) {
            // The real platform source against a fake Storage: this is where
            // `putFile` versus `putData` is actually decided.
            await source.start(
              uploadInto.ref(storagePath),
              SettableMetadata(
                contentType: contentType,
                customMetadata: customMetadata,
              ),
            );
          }
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
    YoMediaPreviewControllerFactory? videoPreview,
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
            videoPreviewControllerFactory: videoPreview,
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

  /// Confirms the confirm-before-send review a library pick now opens
  /// (ADR-211). A pick the backstop refused never gets that far, so the tap is
  /// conditional — the review's presence is asserted where it is the subject.
  Future<void> confirmReview(WidgetTester tester) async {
    final send = find.byKey(const ValueKey('yo-media-review-send'));
    if (send.evaluate().isEmpty) return;
    await tester.tap(send);
    await tester.pumpAndSettle();
  }

  /// Picks one item through the sheet and waits for the whole send to finish.
  Future<void> sendPick(
    WidgetTester tester, {
    ClubChatService? chatService,
    XFile? photo,
    XFile? video,
    Duration videoDuration = const Duration(seconds: 7),
  }) async {
    calls.clear();
    uploads.clear();
    await pump(
      tester,
      chatService ?? service(),
      photo: photo,
      video: video,
      videoDuration: videoDuration,
    );
    // A snackbar left by an earlier attempt in the same test sits over the
    // composer and would take the tap meant for the attach button.
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-attach')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(photo != null ? 'Photo library' : 'Video library'),
    );
    await tester.pumpAndSettle();
    await confirmReview(tester);
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
      await confirmReview(tester);
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
      await confirmReview(tester);
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
    'a pick whose bytes cannot be read is still sent, measured not read',
    (tester) async {
      // Every byte-shaped read on this pick throws. A send that still
      // completes is the proof that the scene no longer holds the photo — or a
      // 64 MiB video — in the heap just to measure it.
      final photo = _UnreadableXFile(
        'holiday.jpg',
        declaredLength: 4096,
        mimeType: 'image/jpeg',
      );

      await sendPick(tester, photo: photo);

      expect(tester.takeException(), isNull);
      expect(calls.map((call) => call.$1), [
        'reserveServerChannelMessageMediaV1',
        'finalizeServerChannelMessageMediaV1',
      ]);
      expect(calls.first.$2['size'], 4096);
      expect(uploads.single['size'], 4096);
      expect(
        find.text('Your photo could not be sent. Try again.'),
        findsNothing,
      );
    },
  );

  test(
    'the service uploads from the picked file, never from its bytes',
    () async {
      final storage = MockFirebaseStorage();
      final file = await _tempFile('holiday.jpg', 4096);
      // Real bytes on disk, unreadable through the picker handle: the only way
      // this upload can succeed is by streaming the file itself.
      final photo = _UnreadableXFile(
        file.path,
        declaredLength: 4096,
        mimeType: 'image/jpeg',
      );

      final messageId = await service(uploadInto: storage)
          .sendServerMediaMessage(
            serverId: 'club',
            channelId: 'general',
            type: 'image',
            contentType: 'image/jpeg',
            source: ClubMediaUploadSource.pickedFile(photo, length: 4096),
          );

      expect(messageId, mediaId);
      expect(calls.first.$2['size'], 4096);
      expect(
        storage.storedDataMap.get(mediaPath),
        isA<File>(),
        reason:
            'putFile streams from the picked path; putData would need the '
            'whole pick resident again.',
      );
    },
  );

  test('the web path still hands Storage the bytes', () async {
    final storage = MockFirebaseStorage();
    final picked = XFile.fromData(
      Uint8List.fromList(List<int>.filled(4096, 7)),
      name: 'holiday.jpg',
      mimeType: 'image/jpeg',
    );

    final source = web_source.createClubMediaUploadSource(picked, length: 4096);
    await source.start(
      storage.ref(mediaPath),
      SettableMetadata(contentType: 'image/jpeg'),
    );

    expect(source.length, 4096);
    final stored = storage.storedDataMap.get(mediaPath);
    expect(
      stored,
      isA<Uint8List>(),
      reason:
          'A browser pick is a Blob, not a file: putData stays the browser '
          'transport and the byte caps bound it.',
    );
    expect(stored as Uint8List, hasLength(4096));
  });

  test(
    'the io source streams the file and refuses one that moved or vanished',
    () async {
      final storage = MockFirebaseStorage();
      final file = await _tempFile('clip.mp4', 8192);
      final metadata = SettableMetadata(contentType: 'video/mp4');
      final source = ClubMediaUploadSource.pickedFile(
        XFile(file.path),
        length: 8192,
      );

      await source.start(storage.ref(videoPath), metadata);
      expect(storage.storedDataMap.get(videoPath), isA<File>());

      // The reservation already declared 8192 bytes, so a file that is no
      // longer that long could only be refused at finalize.
      await file.writeAsBytes(Uint8List(4096), flush: true);
      await expectLater(
        source.start(storage.ref(videoPath), metadata),
        throwsStateError,
      );

      // The picker's temporary file evicted between pick and send: the one new
      // failure mode of streaming instead of copying into memory.
      await file.delete();
      await expectLater(
        source.start(storage.ref(videoPath), metadata),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'the size bounds are unchanged and decided from the declared length',
    (tester) async {
      XFile pick(String kind, int length) => _UnreadableXFile(
        kind == 'image' ? 'pick.jpg' : 'pick.mp4',
        declaredLength: length,
        mimeType: kind == 'image' ? 'image/jpeg' : 'video/mp4',
      );
      Future<void> attempt(String kind, int length) => sendPick(
        tester,
        photo: kind == 'image' ? pick(kind, length) : null,
        video: kind == 'image' ? null : pick(kind, length),
      );

      // Exactly the numbers the reservation and `storage.rules` enforce:
      // 128 B .. 8 MiB for a photo, 1 KiB .. 64 MiB for a video. Nothing here
      // widens or narrows what may be sent — and none of it is read, so the
      // 64 MiB edge costs no heap.
      await attempt('image', 127);
      expect(calls, isEmpty);
      await attempt('image', 128);
      expect(calls.first.$2['size'], 128);
      await attempt('image', 8 * 1024 * 1024);
      expect(calls.first.$2['size'], 8 * 1024 * 1024);
      await attempt('image', 8 * 1024 * 1024 + 1);
      expect(calls, isEmpty);

      await attempt('video', 1023);
      expect(calls, isEmpty);
      await attempt('video', 1024);
      expect(calls.first.$2['size'], 1024);
      await attempt('video', 64 * 1024 * 1024);
      expect(calls.first.$2['size'], 64 * 1024 * 1024);
      await attempt('video', 64 * 1024 * 1024 + 1);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the 60-second video cap is unchanged', (tester) async {
    final video = _UnreadableXFile(
      'clip.mp4',
      declaredLength: 4096,
      mimeType: 'video/mp4',
    );

    await sendPick(
      tester,
      video: video,
      videoDuration: const Duration(seconds: 61),
    );
    expect(calls, isEmpty);
    expect(
      find.text(
        'Your video could not be sent. Choose a video up to 60 seconds and '
        'try again.',
      ),
      findsOneWidget,
    );

    await sendPick(
      tester,
      video: video,
      videoDuration: const Duration(milliseconds: 500),
    );
    expect(calls.first.$2['durationSeconds'], 1);

    await sendPick(
      tester,
      video: video,
      videoDuration: const Duration(seconds: 60),
    );
    expect(calls.first.$2['durationSeconds'], 60);

    await sendPick(tester, video: video, videoDuration: Duration.zero);
    expect(calls, isEmpty);
  });

  // ------------------------------------------- confirm before it is uploaded

  /// Opens the media sheet and takes one of its four entries.
  Future<void> attach(WidgetTester tester, String entry) async {
    await tester.tap(find.byKey(const ValueKey('server-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(entry));
    await tester.pumpAndSettle();
  }

  testWidgets('a library photo is reviewed and uploads only after Send', (
    tester,
  ) async {
    final photo = _UnreadableXFile(
      'holiday.jpg',
      declaredLength: 4096,
      mimeType: 'image/jpeg',
    );
    await pump(tester, service(), photo: photo);
    await attach(tester, 'Photo library');

    expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);
    expect(find.text('Send this photo?'), findsWidgets);
    // The review names the channel the media is going to.
    expect(find.text('To #General'), findsOneWidget);
    expect(find.text('4 KB'), findsOneWidget);
    // Nothing is reserved, uploaded or finalized while the review is open.
    expect(calls, isEmpty);
    expect(uploads, isEmpty);

    await tester.tap(find.byKey(const ValueKey('yo-media-review-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yo-media-review')), findsNothing);
    expect(calls.map((call) => call.$1), [
      'reserveServerChannelMessageMediaV1',
      'finalizeServerChannelMessageMediaV1',
    ]);
    expect(calls.first.$2['size'], 4096);
    expect(uploads, hasLength(1));
    // The preview could not read this pick, and the send happened anyway: the
    // review shows what it can, it never becomes a reason to read the bytes.
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the review uploads nothing', (tester) async {
    final video = _UnreadableXFile(
      'clip.mp4',
      declaredLength: 8192,
      mimeType: 'video/mp4',
    );
    await pump(
      tester,
      service(),
      video: video,
      videoPreview: (_) => _FakePreviewController(const Duration(seconds: 7)),
    );
    await attach(tester, 'Video library');
    expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);
    expect(find.text('Send this video?'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('yo-media-review-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yo-media-review')), findsNothing);
    expect(calls, isEmpty);
    expect(uploads, isEmpty);
    // A cancel is not a failure: nothing is said, nothing is queued.
    expect(
      find.text(
        'Your video could not be sent. Choose a video up to 60 seconds and '
        'try again.',
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('server-media-upload')), findsNothing);
  });

  testWidgets('a camera capture shows no review and uploads directly', (
    tester,
  ) async {
    final photo = _UnreadableXFile(
      'shot.jpg',
      declaredLength: 4096,
      mimeType: 'image/jpeg',
    );
    await pump(tester, service(), photo: photo);
    await attach(tester, 'Take photo');

    expect(find.byKey(const ValueKey('yo-media-review')), findsNothing);
    expect(calls.map((call) => call.$1), [
      'reserveServerChannelMessageMediaV1',
      'finalizeServerChannelMessageMediaV1',
    ]);

    calls.clear();
    uploads.clear();
    final video = _UnreadableXFile(
      'shot.mp4',
      declaredLength: 8192,
      mimeType: 'video/mp4',
    );
    await pump(tester, service(), video: video);
    await attach(tester, 'Record video');

    expect(find.byKey(const ValueKey('yo-media-review')), findsNothing);
    expect(calls.first.$1, 'reserveServerChannelMessageMediaV1');
    expect(calls.first.$2['durationSeconds'], 7);
    expect(uploads, hasLength(1));
  });

  testWidgets(
    'a clip the review measures over the cap is refused there, not mid-send',
    (tester) async {
      final video = _UnreadableXFile(
        'long.mp4',
        declaredLength: 8192,
        mimeType: 'video/mp4',
      );
      // The cheap probe under-reported; the review's own player is the one
      // that sees the real 90 seconds, and it sees them before Send can run.
      await pump(
        tester,
        service(),
        video: video,
        videoPreview: (_) => _FakePreviewController(const Duration(seconds: 90)),
      );
      await attach(tester, 'Video library');

      expect(
        find.text('This video is 1:30. Videos can be up to 60 seconds.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.descendant(
                of: find.byKey(const ValueKey('yo-media-review-send')),
                matching: find.byType(ElevatedButton),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('yo-media-review-send')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(uploads, isEmpty);
      expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);
    },
  );

  testWidgets('a failed upload stays in the review with Send still armed', (
    tester,
  ) async {
    final photo = _UnreadableXFile(
      'holiday.jpg',
      declaredLength: 4096,
      mimeType: 'image/jpeg',
    );
    await pump(tester, service(failWith: StateError('nope')), photo: photo);
    await attach(tester, 'Photo library');
    await tester.tap(find.byKey(const ValueKey('yo-media-review-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('yo-media-review-send-error')),
      findsOneWidget,
    );
    expect(
      find.text('Your photo could not be sent. Try again.'),
      findsOneWidget,
    );

    // Still armed: a second Send is a second real attempt.
    await tester.tap(find.byKey(const ValueKey('yo-media-review-send')));
    await tester.pumpAndSettle();
    expect(
      calls.where((call) => call.$1 == 'reserveServerChannelMessageMediaV1'),
      hasLength(2),
    );
  });

  testWidgets('the review adapts: a sheet on a phone, a dialog on desktop', (
    tester,
  ) async {
    final photo = _UnreadableXFile(
      'holiday.jpg',
      declaredLength: 4096,
      mimeType: 'image/jpeg',
    );
    for (final (width, isDialog) in const [
      (390.0, false),
      (900.0, false),
      (1440.0, true),
    ]) {
      await pump(tester, service(), size: Size(width, 900), photo: photo);
      await attach(tester, 'Photo library');
      expect(
        find.byType(Dialog),
        isDialog ? findsOneWidget : findsNothing,
        reason: 'at $width',
      );
      expect(
        find.byType(BottomSheet),
        isDialog ? findsNothing : findsOneWidget,
        reason: 'at $width',
      );
      expect(find.text('To #General'), findsOneWidget, reason: 'at $width');
      await tester.tap(find.byKey(const ValueKey('yo-media-review-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at $width');
    }
    expect(calls, isEmpty);
  });

  testWidgets('a different account closes the review and sends nothing', (
    tester,
  ) async {
    final photo = _UnreadableXFile(
      'holiday.jpg',
      declaredLength: 4096,
      mimeType: 'image/jpeg',
    );
    await pump(tester, service(), photo: photo);
    await attach(tester, 'Photo library');
    expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);

    auth.mockUser = MockUser(uid: 'someone-else', isEmailVerified: true);
    await auth.signInWithCredential(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yo-media-review')), findsNothing);
    expect(calls, isEmpty);
    expect(uploads, isEmpty);
  });

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
      await confirmReview(tester);
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

/// A preview player for the review that reports a duration without a platform
/// (and without reading the pick), so the clip the review measures can differ
/// from the one the cheap probe reported.
class _FakePreviewController implements VideoPlayerController {
  _FakePreviewController(Duration duration)
    : _state = ValueNotifier(VideoPlayerValue(duration: duration));

  final ValueNotifier<VideoPlayerValue> _state;
  bool disposed = false;

  @override
  VideoPlayerValue get value => _state.value;

  @override
  set value(VideoPlayerValue value) => _state.value = value;

  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;

  @override
  Future<void> initialize() async {
    value = value.copyWith(isInitialized: true, size: const Size(1920, 1080));
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async {
    if (disposed) return;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async =>
      value = value.copyWith(position: position);

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
