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
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/shared_media_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/message_bubble.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_picked_video_inspector.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';

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
    DirectMessageVoiceRecorderPresenter? voiceRecorderPresenter,
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
      voiceRecorderPresenter: voiceRecorderPresenter,
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

  testWidgets('account switch during photo picker cannot enqueue into B', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    final pickerStarted = Completer<void>();
    final picked = Completer<XFile?>();
    await tester.pumpWidget(
      host(
        service,
        photoPicker: (_) {
          pickerStarted.complete();
          return picked.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add photo or video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo library'));
    await tester.pump();
    expect(pickerStarted.isCompleted, isTrue);

    auth.mockUser = MockUser(uid: 'account-b');
    await auth.signInWithCredential(null);
    picked.complete(
      XFile.fromData(
        Uint8List(256),
        mimeType: 'image/jpeg',
        name: 'account-a-photo.jpg',
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.sentImages, isEmpty);
    expect(service.sentVideos, isEmpty);
  });

  testWidgets('account switch during video inspection cannot enqueue into B', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    final inspectionStarted = Completer<void>();
    final inspection = Completer<Duration>();
    await tester.pumpWidget(
      host(
        service,
        videoPicker: (_) async => XFile.fromData(
          Uint8List(2048),
          mimeType: 'video/mp4',
          name: 'account-a-video.mp4',
        ),
        videoInspector: (_) {
          inspectionStarted.complete();
          return inspection.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add photo or video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video library'));
    await tester.pump();
    await tester.pump();
    expect(inspectionStarted.isCompleted, isTrue);

    auth.mockUser = MockUser(uid: 'account-b');
    await auth.signInWithCredential(null);
    inspection.complete(const Duration(seconds: 12));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(service.sentVideos, isEmpty);
  });

  testWidgets('account switch rejects and discards recorder callback audio', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    final presenterOpened = Completer<void>();
    final presenterClosed = Completer<void>();
    late Future<void> Function(RecordedAudio, int) sendVoice;
    await tester.pumpWidget(
      host(
        service,
        voiceRecorderPresenter: (onSend) {
          sendVoice = onSend;
          presenterOpened.complete();
          return presenterClosed.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pump();
    expect(presenterOpened.isCompleted, isTrue);

    auth.mockUser = MockUser(uid: 'account-b');
    await auth.signInWithCredential(null);
    final audio = _TestRecordedAudio();
    await expectLater(sendVoice(audio, 7), throwsStateError);

    expect(service.sentVoices, isEmpty);
    expect(audio.discardCalls, 1);
    presenterClosed.complete();
    await tester.pump();
  });

  testWidgets('live recorder sheet closes when its account changes', (
    tester,
  ) async {
    final service = _ActionMessageService(firestore, auth);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pumpAndSettle();
    expect(find.text('Record a voice message'), findsOneWidget);

    auth.mockUser = MockUser(uid: 'account-b');
    await auth.signInWithCredential(null);
    await tester.pumpAndSettle();

    expect(find.text('Record a voice message'), findsNothing);
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

  testWidgets('Edit is offered on your own text message and on nothing else', (
    tester,
  ) async {
    // `mutateMessage` refuses anything but text with `failed-precondition`
    // "Only text messages can be edited." — production shows
    // editdirectmessage answering 400 — so Edit on a photo or a voice
    // message was a control that could only fail.
    Message own(String id, MessageType type) => Message(
      id: id,
      conversationId: 'conversation',
      senderId: currentUserId,
      type: type,
      content: type == MessageType.text ? 'hello' : '',
      mediaUrl: type == MessageType.text ? null : 'fixture://$id',
      sentAt: DateTime.utc(2026, 9, 16, 12),
      readBy: const <String>[],
      reactions: const <String, String>{},
      durationSeconds: type == MessageType.voice ? 4 : null,
    );

    for (final testCase in <({MessageType type, bool editable})>[
      (type: MessageType.text, editable: true),
      (type: MessageType.voice, editable: false),
      (type: MessageType.image, editable: false),
      (type: MessageType.video, editable: false),
    ]) {
      final service = _ActionMessageService(
        firestore,
        auth,
        messageStream: Stream<List<Message>>.value(<Message>[
          own('m-${testCase.type.name}', testCase.type),
        ]),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      // Invoke the bubble's own context action rather than aiming a gesture
      // at it: an outgoing bubble is right-aligned inside a full-width
      // Align, so the finder's centre lands in its padding.
      tester
          .widget<AccessibleContextAction>(
            find
                .descendant(
                  of: find.byType(MessageBubble),
                  matching: find.byType(AccessibleContextAction),
                )
                .first,
          )
          .onOpen!();
      await tester.pumpAndSettle();

      expect(
        find.text('Delete'),
        findsOneWidget,
        reason: 'the sheet for ${testCase.type.name} did open',
      );
      expect(
        find.text('Edit'),
        testCase.editable ? findsOneWidget : findsNothing,
        reason: 'Edit must match what mutateMessage accepts',
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

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
  final List<({RecordedAudio audio, int durationSeconds})> sentVoices = [];
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
  Future<String> enqueueImageMessage({
    required String conversationId,
    required XFile image,
  }) async {
    sentImages.add(image);
    return 'queued-image-${sentImages.length}';
  }

  @override
  Future<void> sendVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    sentVideos.add((video: video, durationSeconds: durationSeconds));
  }

  @override
  Future<String> enqueueVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    sentVideos.add((video: video, durationSeconds: durationSeconds));
    return 'queued-video-${sentVideos.length}';
  }

  @override
  Future<String> enqueueVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) async {
    sentVoices.add((audio: audio, durationSeconds: durationSeconds));
    return 'queued-voice-${sentVoices.length}';
  }
}

class _TestRecordedAudio extends RecordedAudio {
  int discardCalls = 0;

  @override
  int get byteLength => 2048;

  @override
  String get contentType => 'audio/mp4';

  @override
  Future<void> discard() async => discardCalls += 1;

  @override
  Future<String> uploadTo(Reference reference, SettableMetadata metadata) =>
      throw UnsupportedError('The owner-switch test never uploads audio.');
}

class _TestPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> payloads = {};

  String _key(String namespace, String id) => '$namespace:$id';

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
  Future<void> adopt(
    String namespace,
    String id,
    DirectAttachmentPayloadSource source,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      builder.add(chunk);
    }
    payloads['$namespace:$id'] = builder.takeBytes();
  }

  @override
  Future<String> upload(
    String namespace,
    String id,
    Reference reference,
    SettableMetadata metadata, {
    void Function(double progress)? onProgress,
  }) => throw UnsupportedError('The widget test never uploads media.');
}
