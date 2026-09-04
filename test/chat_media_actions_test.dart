import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/shared_media_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_picked_video_inspector.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

void main() {
  const currentUserId = 'me';
  const otherUserId = 'them';
  late PublicIdentityRepository originalIdentityRepository;
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: currentUserId),
    );
    firestore = FakeFirebaseFirestore();
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => {
        for (final uid in uids) uid: {'uid': uid, 'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  Widget host(
    _ActionMessageService service, {
    DirectMessagePhotoPicker? photoPicker,
    DirectMessageVideoPicker? videoPicker,
    DirectMessageVideoInspector? videoInspector,
    Future<void> Function()? profilePreviewAction,
  }) => MaterialApp(
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ChatScreen(
      conversationId: 'conversation',
      otherUserId: otherUserId,
      otherDisplayName: 'Them',
      otherEmail: '',
      otherPhotoUrl: '',
      messageService: service,
      auth: auth,
      profileService: ProfileService(firestore: firestore, auth: auth),
      photoPicker: photoPicker,
      videoPicker: videoPicker,
      videoInspector: videoInspector,
      profilePreviewAction: profilePreviewAction,
    ),
  );

  testWidgets('camera action offers camera and library through one pipeline', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(320, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _ActionMessageService(firestore, auth);
    final sources = <ImageSource>[];
    await tester.pumpWidget(
      host(
        service,
        photoPicker: (source) async {
          sources.add(source);
          return XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/jpeg',
            name: '${source.name}.jpg',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add photo or video'));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Photo library'), findsOneWidget);
    expect(tester.getSize(find.text('Take photo')).height, greaterThan(0));
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();

    expect(sources, [ImageSource.camera]);
    expect(service.sentImages, hasLength(1));

    await tester.tap(find.byTooltip('Add photo or video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo library'));
    await tester.pumpAndSettle();

    expect(sources, [ImageSource.camera, ImageSource.gallery]);
    expect(service.sentImages, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera action records or selects a short video safely', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    final sources = <ImageSource>[];
    await tester.pumpWidget(
      host(
        service,
        videoPicker: (source) async {
          sources.add(source);
          return XFile.fromData(
            Uint8List(1024),
            mimeType: 'video/mp4',
            name: '${source.name}.mp4',
          );
        },
        videoInspector: (_) async => const Duration(seconds: 12),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add photo or video'));
    await tester.pumpAndSettle();
    expect(find.text('Record video'), findsOneWidget);
    expect(find.text('Video library'), findsOneWidget);
    await tester.tap(find.text('Record video'));
    await tester.pumpAndSettle();

    expect(sources, [ImageSource.camera]);
    expect(service.sentVideos.single.durationSeconds, 12);

    await tester.tap(find.byTooltip('Add photo or video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video library'));
    await tester.pumpAndSettle();

    expect(sources, [ImageSource.camera, ImageSource.gallery]);
    expect(service.sentVideos, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile preview is single-flight across rapid repeated taps', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    var calls = 0;
    var pending = Completer<void>();
    await tester.pumpWidget(
      host(
        service,
        profilePreviewAction: () {
          calls++;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    final profile = find.text('Them').first;
    await tester.tap(profile);
    await tester.tap(profile);
    await tester.tap(profile);
    await tester.pump();
    expect(calls, 1);

    pending.complete();
    await tester.pump();
    pending = Completer<void>();
    await tester.tap(profile);
    await tester.pump();
    expect(calls, 2);
    pending.complete();
    await tester.pump();
  });

  testWidgets(
    'a canonical media message clears a max-attempt durable outbox card',
    (tester) async {
      const messageId = 'm_0123456789abcdef0123456789abcdef01234567';
      final messages = StreamController<List<Message>>();
      addTearDown(messages.close);
      final payloadStore = _TestPayloadStore();
      final mediaOutbox = DirectAttachmentOutbox(
        ownerId: currentUserId,
        preferences: await SharedPreferences.getInstance(),
        payloadStore: payloadStore,
        maxAttempts: 1,
      );
      final pending = await mediaOutbox.enqueue(
        fingerprint: 'a' * 64,
        conversationId: 'conversation',
        type: MessageType.image,
        contentType: 'image/jpeg',
        durationSeconds: null,
        bytes: Uint8List(128),
        reserveRequestId: 'reserve-request',
        finalizeRequestId: 'finalize-request',
      );
      await mediaOutbox.setReservation(
        pending.id,
        DirectAttachmentReservationRecord(
          conversationId: 'conversation',
          messageId: messageId,
          storagePath:
              'message_attachments/$currentUserId/conversation/$messageId.jpg',
          type: MessageType.image,
          expiresAt: DateTime.utc(2030),
          clientExpiresAt: DateTime.utc(2030),
        ),
      );
      await mediaOutbox.markRetry(
        pending.id,
        StateError('The finalize acknowledgement was lost.'),
      );
      expect(
        mediaOutbox.entries.single.status,
        DirectAttachmentOutboxStatus.failed,
      );
      expect(payloadStore.payloads, isNotEmpty);
      final service = _ActionMessageService(
        firestore,
        auth,
        attachmentOutbox: mediaOutbox,
        messageStream: messages.stream,
      );

      await tester.pumpWidget(host(service));
      await tester.pump();
      expect(
        find.byKey(ValueKey('queued-media-${pending.id}')),
        findsOneWidget,
      );

      messages.add([
        Message(
          id: messageId,
          conversationId: 'conversation',
          senderId: currentUserId,
          type: MessageType.image,
          content: 'Photo',
          sentAt: DateTime.utc(2026, 9, 4),
          readBy: const [currentUserId],
          reactions: const {},
          mediaUrl: 'gs://private/committed-image.jpg',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(ValueKey('queued-media-${pending.id}')), findsNothing);
      expect(mediaOutbox.entries, isEmpty);
      expect(payloadStore.payloads, isEmpty);
    },
  );

  for (final scenario in const [
    (
      label: 'wrong sender',
      conversationId: 'conversation',
      senderId: otherUserId,
      type: MessageType.image,
    ),
    (
      label: 'wrong media type',
      conversationId: 'conversation',
      senderId: currentUserId,
      type: MessageType.voice,
    ),
    (
      label: 'wrong conversation',
      conversationId: 'another-conversation',
      senderId: currentUserId,
      type: MessageType.image,
    ),
  ]) {
    testWidgets(
      'canonical id with ${scenario.label} keeps the durable media card',
      (tester) async {
        const messageId = 'm_0123456789abcdef0123456789abcdef01234567';
        final messages = StreamController<List<Message>>();
        addTearDown(messages.close);
        final payloadStore = _TestPayloadStore();
        final mediaOutbox = DirectAttachmentOutbox(
          ownerId: currentUserId,
          preferences: await SharedPreferences.getInstance(),
          payloadStore: payloadStore,
          maxAttempts: 1,
        );
        final pending = await mediaOutbox.enqueue(
          fingerprint: 'b' * 64,
          conversationId: 'conversation',
          type: MessageType.image,
          contentType: 'image/jpeg',
          durationSeconds: null,
          bytes: Uint8List(128),
          reserveRequestId: 'reserve-request',
          finalizeRequestId: 'finalize-request',
        );
        await mediaOutbox.setReservation(
          pending.id,
          DirectAttachmentReservationRecord(
            conversationId: 'conversation',
            messageId: messageId,
            storagePath:
                'message_attachments/$currentUserId/conversation/$messageId.jpg',
            type: MessageType.image,
            expiresAt: DateTime.utc(2030),
            clientExpiresAt: DateTime.utc(2030),
          ),
        );
        await mediaOutbox.markRetry(pending.id, StateError('lost ACK'));
        final service = _ActionMessageService(
          firestore,
          auth,
          attachmentOutbox: mediaOutbox,
          messageStream: messages.stream,
        );

        await tester.pumpWidget(host(service));
        await tester.pump();
        messages.add([
          Message(
            id: messageId,
            conversationId: scenario.conversationId,
            senderId: scenario.senderId,
            type: scenario.type,
            content: scenario.type == MessageType.voice
                ? 'Voice message'
                : 'Photo',
            sentAt: DateTime.utc(2026, 9, 4),
            readBy: const [currentUserId],
            reactions: const {},
            mediaUrl: 'gs://private/not-the-reserved-media',
          ),
        ]);
        await tester.pumpAndSettle();

        expect(
          find.byKey(ValueKey('queued-media-${pending.id}')),
          findsOneWidget,
        );
        expect(mediaOutbox.entries, hasLength(1));
        expect(
          await payloadStore.exists(mediaOutbox.accountNamespace, pending.id),
          isTrue,
        );
      },
    );
  }

  testWidgets('top overflow opens Shared media beside mute and archive', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    expect(find.text('Shared media'), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    await tester.tap(find.text('Shared media'));
    await tester.pumpAndSettle();
    expect(find.byType(SharedMediaScreen), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
  });
}

class _ActionMessageService extends MessageService {
  _ActionMessageService(
    FakeFirebaseFirestore firestore,
    MockFirebaseAuth auth, {
    DirectAttachmentOutbox? attachmentOutbox,
    Stream<List<Message>>? messageStream,
  }) : _messageStream = messageStream ?? Stream.value(const <Message>[]),
       super(
         firestore: firestore,
         auth: auth,
         attachmentOutbox: attachmentOutbox,
       );

  final List<XFile> sentImages = [];
  final List<({XFile video, int durationSeconds})> sentVideos = [];
  final Stream<List<Message>> _messageStream;

  @override
  Stream<List<Message>> watchMessages(String conversationId) => _messageStream;

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream.value(const ChatPresence(isOnline: false, lastSeen: null));

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required XFile image,
  }) async {
    sentImages.add(image);
  }

  @override
  Future<void> sendVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    sentVideos.add((video: video, durationSeconds: durationSeconds));
  }
}

class _TestPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> payloads = {};

  String _key(String namespace, String id) => '$namespace:$id';

  @override
  Future<void> write(String namespace, String id, Uint8List bytes) async {
    payloads[_key(namespace, id)] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String namespace, String id) async =>
      payloads.containsKey(_key(namespace, id));

  @override
  Future<Set<String>> keys(String namespace) async {
    final prefix = '$namespace:';
    return payloads.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toSet();
  }

  @override
  Future<void> delete(String namespace, String id) async {
    payloads.remove(_key(namespace, id));
  }

  @override
  Future<void> clear(String namespace) async {
    final prefix = '$namespace:';
    payloads.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<String> upload(
    String namespace,
    String id,
    Reference reference,
    SettableMetadata metadata,
  ) => throw UnsupportedError('The widget test never uploads media.');
}
