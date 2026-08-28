import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/room_cover_editor.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';

String _managedRoomCoverUrl(String roomId, {int revision = 100}) =>
    'https://firebasestorage.googleapis.com/v0/b/'
    'yovoice-ec54a.firebasestorage.app/o/'
    'room_images%2F$roomId%2Fcover_$revision.jpg?alt=media';

const _oldRoomCoverUrl =
    'https://firebasestorage.googleapis.com/v0/b/'
    'yovoice-ec54a.firebasestorage.app/o/'
    'room_images%2Froom-1%2Fcover_99.jpg?alt=media';

class _RecordingImageService implements RoomImageService {
  _RecordingImageService({this.uploadFails = false});

  final bool uploadFails;
  int uploadCalls = 0;
  String? uploadedRoomId;
  Uint8List? uploadedBytes;
  final List<String?> deletedUrls = <String?>[];

  @override
  Future<String> uploadRoomCover({
    required String roomId,
    required Uint8List bytes,
  }) async {
    uploadCalls++;
    uploadedRoomId = roomId;
    uploadedBytes = bytes;
    if (uploadFails) throw StateError('Storage rejected the upload.');
    return _managedRoomCoverUrl(roomId);
  }

  @override
  Future<void> deleteManagedRoomCover({
    required String roomId,
    required String? url,
  }) async {
    deletedUrls.add(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedImageService extends _RecordingImageService {
  final Completer<String> uploadGate = Completer<String>();

  @override
  Future<String> uploadRoomCover({
    required String roomId,
    required Uint8List bytes,
  }) {
    uploadCalls++;
    uploadedRoomId = roomId;
    uploadedBytes = bytes;
    return uploadGate.future;
  }
}

class _LostAckRoomService extends RoomService {
  _LostAckRoomService({
    required this.firestore,
    required MockFirebaseAuth auth,
    required this.commitBeforeThrow,
    this.serverReadFails = false,
  }) : super(firestore: firestore, auth: auth);

  final FakeFirebaseFirestore firestore;
  final bool commitBeforeThrow;
  final bool serverReadFails;
  int updateCalls = 0;
  int serverReadCalls = 0;

  @override
  Future<void> updateImageUrl({
    required String roomId,
    required String imageUrl,
  }) async {
    updateCalls++;
    if (commitBeforeThrow) {
      await super.updateImageUrl(roomId: roomId, imageUrl: imageUrl);
    }
    throw StateError('The write acknowledgement was lost.');
  }

  @override
  Future<VoiceRoom> getRoomFromServer(String roomId) async {
    serverReadCalls++;
    if (serverReadFails) {
      throw StateError('The authoritative read is unavailable.');
    }
    final data = (await firestore.collection('rooms').doc(roomId).get()).data();
    return VoiceRoom(
      id: _room.id,
      hostId: _room.hostId,
      hostName: _room.hostName,
      hostPhotoUrl: _room.hostPhotoUrl,
      name: _room.name,
      description: _room.description,
      category: _room.category,
      visibility: _room.visibility,
      language: _room.language,
      maxParticipants: _room.maxParticipants,
      participantCount: _room.participantCount,
      memberCount: _room.memberCount,
      isLive: _room.isLive,
      roomType: _room.roomType,
      status: _room.status,
      imageUrl: data?['imageUrl'] as String?,
      approvalRequired: _room.approvalRequired,
      slowModeSeconds: _room.slowModeSeconds,
      autoMuteNewUsers: _room.autoMuteNewUsers,
      membersCanStartVoice: _room.membersCanStartVoice,
      createdAt: _room.createdAt,
      updatedAt: _room.updatedAt,
    );
  }
}

const _room = VoiceRoom(
  id: 'room-1',
  hostId: 'host',
  hostName: 'Host',
  hostPhotoUrl: null,
  name: 'Community room',
  description: 'Room description',
  category: 'talk',
  visibility: 'public',
  language: 'English',
  maxParticipants: 25,
  participantCount: 1,
  memberCount: 1,
  isLive: false,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: _oldRoomCoverUrl,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
);

VoiceRoom _roomWithStatus(RoomStatus status) => VoiceRoom(
  id: _room.id,
  hostId: _room.hostId,
  hostName: _room.hostName,
  hostPhotoUrl: _room.hostPhotoUrl,
  name: _room.name,
  description: _room.description,
  category: _room.category,
  visibility: _room.visibility,
  language: _room.language,
  maxParticipants: _room.maxParticipants,
  participantCount: _room.participantCount,
  memberCount: _room.memberCount,
  isLive: _room.isLive,
  roomType: _room.roomType,
  status: status,
  imageUrl: _room.imageUrl,
  approvalRequired: _room.approvalRequired,
  slowModeSeconds: _room.slowModeSeconds,
  autoMuteNewUsers: _room.autoMuteNewUsers,
  membersCanStartVoice: _room.membersCanStartVoice,
  createdAt: _room.createdAt,
  updatedAt: _room.updatedAt,
);

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _RecordingImageService images;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'host', email: 'host@yovoice.app'),
    );
    images = _RecordingImageService();
    await firestore.collection('rooms').doc(_room.id).set({
      'hostId': _room.hostId,
      'imageUrl': _room.imageUrl,
    });
  });

  Widget screen(
    RoomCoverEditorCallback editor, {
    RoomService? roomService,
    RoomImageService? imageService,
    VoiceRoom room = _room,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: RoomSettingsScreen(
        room: room,
        roomService:
            roomService ?? RoomService(firestore: firestore, auth: auth),
        roomImageService: imageService ?? images,
        coverEditor: editor,
      ),
    );
  }

  testWidgets(
    'cancel preserves the old cover and rapid double tap opens once',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Completer<PickedRoomCover?>();
      var editorCalls = 0;

      await tester.pumpWidget(
        screen((context, imageService) {
          editorCalls++;
          return gate.future;
        }),
      );
      await tester.pump();

      await tester.tap(find.text('Change cover'));
      await tester.tap(find.text('Change cover'));
      await tester.pump();
      expect(editorCalls, 1);
      expect(find.text('Updating cover…'), findsOneWidget);

      gate.complete(null);
      await tester.pumpAndSettle();

      expect(images.uploadCalls, 0);
      expect(images.deletedUrls, isEmpty);
      expect(find.text('Change cover'), findsOneWidget);
      expect(
        (await firestore.collection('rooms').doc(_room.id).get())
            .data()?['imageUrl'],
        _room.imageUrl,
      );
    },
  );

  testWidgets(
    'confirmation uploads only canonical cropped JPEG and flips URL',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final croppedBytes = Uint8List.fromList(
        List<int>.generate(128, (i) => i),
      );

      await tester.pumpWidget(
        screen((context, imageService) async {
          return PickedRoomCover(bytes: croppedBytes);
        }),
      );
      await tester.pump();
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();

      expect(images.uploadCalls, 1);
      expect(images.uploadedRoomId, _room.id);
      expect(images.uploadedBytes, croppedBytes);
      expect(images.deletedUrls, [_room.imageUrl]);
      final data = (await firestore.collection('rooms').doc(_room.id).get())
          .data();
      expect(data?['imageUrl'], _managedRoomCoverUrl(_room.id));
      expect(find.text('Change cover'), findsOneWidget);
    },
  );

  testWidgets('upload failure preserves the old cover and deletes nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final failingImages = _RecordingImageService(uploadFails: true);

    await tester.pumpWidget(
      screen(
        (context, imageService) async =>
            PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 5))),
        imageService: failingImages,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Change cover'));
    await tester.pumpAndSettle();

    expect(failingImages.uploadCalls, 1);
    expect(failingImages.deletedUrls, isEmpty);
    expect(
      (await firestore.collection('rooms').doc(_room.id).get())
          .data()?['imageUrl'],
      _room.imageUrl,
    );
    expect(find.text('Storage rejected the upload.'), findsOneWidget);
  });

  testWidgets(
    'lost acknowledgement with committed pointer keeps the new cover',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _LostAckRoomService(
        firestore: firestore,
        auth: auth,
        commitBeforeThrow: true,
      );

      await tester.pumpWidget(
        screen(
          (context, imageService) async =>
              PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 6))),
          roomService: service,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();

      final newUrl = _managedRoomCoverUrl(_room.id);
      expect(
        (await firestore.collection('rooms').doc(_room.id).get())
            .data()?['imageUrl'],
        newUrl,
      );
      expect(images.deletedUrls, [_room.imageUrl]);
      expect(service.updateCalls, 1);
      expect(service.serverReadCalls, 1);
      expect(find.textContaining('acknowledgement'), findsNothing);
    },
  );

  testWidgets(
    'lost acknowledgement with confirmed mismatch deletes only the new cover',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _LostAckRoomService(
        firestore: firestore,
        auth: auth,
        commitBeforeThrow: false,
      );

      await tester.pumpWidget(
        screen(
          (context, imageService) async =>
              PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 7))),
          roomService: service,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();

      final newUrl = _managedRoomCoverUrl(_room.id);
      expect(images.deletedUrls, [newUrl]);
      expect(service.updateCalls, 1);
      expect(service.serverReadCalls, 1);
      expect(
        (await firestore.collection('rooms').doc(_room.id).get())
            .data()?['imageUrl'],
        _room.imageUrl,
      );
      expect(find.text('The write acknowledgement was lost.'), findsOneWidget);
    },
  );

  testWidgets(
    'ambiguous lost acknowledgement preserves the uploaded cover for recovery',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = _LostAckRoomService(
        firestore: firestore,
        auth: auth,
        commitBeforeThrow: false,
        serverReadFails: true,
      );

      await tester.pumpWidget(
        screen(
          (context, imageService) async =>
              PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 8))),
          roomService: service,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();

      expect(images.deletedUrls, isEmpty);
      expect(service.updateCalls, 1);
      expect(service.serverReadCalls, 1);
      expect(
        (await firestore.collection('rooms').doc(_room.id).get())
            .data()?['imageUrl'],
        _room.imageUrl,
      );
      expect(find.text('The write acknowledgement was lost.'), findsOneWidget);
    },
  );

  testWidgets(
    'leaving during upload still cleans the superseded cover after commit',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gatedImages = _GatedImageService();

      await tester.pumpWidget(
        screen(
          (context, imageService) async =>
              PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 9))),
          imageService: gatedImages,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Change cover'));
      await tester.pump();
      expect(find.text('Updating cover…'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gatedImages.uploadGate.complete(_managedRoomCoverUrl(_room.id));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );

      expect(
        (await firestore.collection('rooms').doc(_room.id).get())
            .data()?['imageUrl'],
        _managedRoomCoverUrl(_room.id),
      );
      expect(gatedImages.deletedUrls, [_room.imageUrl]);
    },
  );

  testWidgets('status and delete actions disable while cover upload runs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gatedImages = _GatedImageService();

    await tester.pumpWidget(
      screen(
        (context, imageService) async =>
            PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 10))),
        imageService: gatedImages,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Change cover'));
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pump();
    for (final label in ['Close room', 'Archive room', 'Delete room']) {
      final labelFinder = find.text(label).last;
      final tile = tester.widget<ListTile>(
        find.ancestor(of: labelFinder, matching: find.byType(ListTile)),
      );
      expect(tile.onTap, isNull, reason: '$label raced the cover upload');
    }

    gatedImages.uploadGate.complete(_managedRoomCoverUrl(_room.id));
    await tester.pumpAndSettle();
  });

  testWidgets('closed room offers a nearby reopen action before cover edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      screen(
        (context, imageService) async =>
            PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 11))),
        room: _roomWithStatus(RoomStatus.closed),
      ),
    );
    await tester.pump();

    expect(find.text('Reopen this room to edit its cover.'), findsOneWidget);
    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reopen room'),
    );
    expect(action.onPressed, isNotNull);
    await tester.tap(find.text('Reopen room'));
    await tester.pumpAndSettle();
    expect(find.text('Open room?'), findsOneWidget);
    expect(images.uploadCalls, 0);
  });

  testWidgets('suspended room exposes no host status or cover escape hatch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      screen(
        (context, imageService) async =>
            PickedRoomCover(bytes: Uint8List.fromList(List.filled(96, 12))),
        room: _roomWithStatus(RoomStatus.suspended),
      ),
    );
    await tester.pump();

    expect(find.textContaining('suspended by moderation'), findsOneWidget);
    expect(find.text('Reopen room'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -1800));
    await tester.pump();
    expect(find.text('Open room'), findsNothing);
    expect(find.text('Close room'), findsNothing);
    expect(find.text('Archive room'), findsNothing);
    expect(images.uploadCalls, 0);
  });
}
