// The one-minute limit of a direct voice message, end to end on the client:
// the live recorder sheet (through its injectable recorder seam) stops itself
// at 1:00 and keeps the take ready to send, counts down only in the final ten
// seconds with one haptic warning, and a manual stop before the cap is
// unchanged. Also pins the shared cap/grace helpers and the camera-video
// boundary they fix (a clip the camera itself capped at 60 s).
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_picked_video_inspector.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/media/yo_recording_countdown.dart';

import 'voice_moment_test_doubles.dart';

void main() {
  group('shared limits', () {
    test('the cap and grace mirror the server contract', () {
      expect(directMediaMaxSeconds, 60);
      expect(directVoiceMaxSeconds, 60);
      expect(directVideoMaxSeconds, 60);
      expect(directMediaDurationGraceMs, 2000);
    });

    test('a capped take declares the cap only inside the grace', () {
      int seconds(int ms) =>
          directCappedTakeSeconds(Duration(milliseconds: ms));
      expect(seconds(1), 1);
      expect(seconds(12_300), 13);
      expect(seconds(59_001), 60);
      expect(seconds(60_000), 60);
      expect(seconds(60_400), 60);
      expect(seconds(61_900), 60);
      expect(seconds(62_000), 60);
      // Past the grace the real length is kept, so 1..60 checks refuse it.
      expect(seconds(62_001), 63);
      expect(seconds(62_100), 63);
    });

    test('the countdown covers only the final ten seconds', () {
      int? left(int ms) => recordingSecondsLeft(
        Duration(milliseconds: ms),
        const Duration(seconds: 60),
      );
      expect(left(0), isNull);
      expect(left(49_999), isNull);
      expect(left(50_000), 10);
      expect(left(50_001), 10);
      expect(left(55_200), 5);
      expect(left(59_999), 1);
      expect(left(60_000), isNull);
      expect(left(60_300), isNull);
      expect(
        recordingSecondsLeft(
          const Duration(milliseconds: 20_000),
          const Duration(seconds: 30),
        ),
        10,
      );
    });

    test('a take that ran past 60 s still declares 60', () async {
      final clock = FakeStopwatch();
      final recorder = VoiceMomentRecorder(
        backend: FakeRecorderBackend(),
        capture: FakeAudioCapture(),
        clock: clock,
      );
      await recorder.start();
      clock.value = const Duration(milliseconds: 60_300);
      expect(recorder.durationSeconds, 60);
      await recorder.stop();
      await recorder.dispose();
    });
  });

  group('voice message sheet', () {
    late MockFirebaseAuth auth;
    late FakeFirebaseFirestore firestore;
    late PublicIdentityRepository originalIdentityRepository;
    late List<Object?> haptics;

    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
      firestore = FakeFirebaseFirestore();
      originalIdentityRepository = PublicIdentityRepository.instance;
      PublicIdentityRepository.instance = PublicIdentityRepository(
        auth: auth,
        fetchOverride: (uids) async => {
          for (final uid in uids)
            uid: {'uid': uid, 'role': 'user', 'vip': false},
        },
        flushDelay: const Duration(milliseconds: 1),
      );
      haptics = [];
    });

    tearDown(() {
      PublicIdentityRepository.instance = originalIdentityRepository;
    });

    void recordHaptics(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    Widget host(
      _VoiceMessageService service, {
      DirectMessageVoiceRecorderFactory? recorderFactory,
      DirectMessageVideoPicker? videoPicker,
      DirectMessageVideoInspector? videoInspector,
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
        otherUserId: 'them',
        otherDisplayName: 'Them',
        otherEmail: '',
        otherPhotoUrl: '',
        messageService: service,
        auth: auth,
        profileService: ProfileService(firestore: firestore, auth: auth),
        voiceRecorderFactory: recorderFactory,
        videoPicker: videoPicker,
        videoInspector: videoInspector,
      ),
    );

    Finder labelled(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    final countdown = find.byKey(const ValueKey('yo-recording-countdown'));
    final stoppedAtLimit = find.byKey(
      const ValueKey('voice-message-stopped-at-limit'),
    );

    /// Opens the sheet and starts a take on a recorder the test drives.
    Future<({FakeStopwatch clock, FakeRecordedAudio audio})> startTake(
      WidgetTester tester,
      _VoiceMessageService service, {
      FakeRecorderBackend? backend,
    }) async {
      final clock = FakeStopwatch();
      final audio = FakeRecordedAudio();
      await tester.pumpWidget(
        host(
          service,
          recorderFactory: () => VoiceMomentRecorder(
            backend: backend ?? FakeRecorderBackend(),
            capture: FakeAudioCapture()..result = audio,
            clock: clock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pumpAndSettle();
      expect(find.text('Record a voice message'), findsOneWidget);
      await tester.tap(labelled('Start recording'));
      await tester.pump();
      expect(find.text('Recording voice message…'), findsOneWidget);
      return (clock: clock, audio: audio);
    }

    Future<void> tick(WidgetTester tester, FakeStopwatch clock, int ms) async {
      clock.value = Duration(milliseconds: ms);
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('the automatic stop at 1:00 leaves a take ready to send', (
      tester,
    ) async {
      recordHaptics(tester);
      final service = _VoiceMessageService(firestore, auth);
      final take = await startTake(tester, service);

      await tick(tester, take.clock, 59_900);
      expect(find.text('Recording voice message…'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.lightImpact']);

      // The recorder's stopwatch passes the cap: the sheet stops itself.
      await tick(tester, take.clock, 60_300);
      await tester.pump();
      expect(find.text('Voice message ready'), findsOneWidget);
      expect(find.text('1:00 / 1:00'), findsOneWidget);
      expect(stoppedAtLimit, findsOneWidget);
      expect(countdown, findsNothing);
      // One light haptic at ten seconds left, one at the automatic stop.
      expect(haptics, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.lightImpact',
      ]);
      expect(take.audio.discarded, isFalse);

      // Nothing moves on by itself: the take waits for Send.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Voice message ready'), findsOneWidget);
      expect(service.sentVoices, isEmpty);

      await tester.tap(find.text('Send voice message'));
      await tester.pumpAndSettle();
      expect(service.sentVoices, hasLength(1));
      expect(service.sentVoices.single.durationSeconds, 60);
      expect(identical(service.sentVoices.single.audio, take.audio), isTrue);
      expect(take.audio.discarded, isFalse);
      expect(find.text('Voice message ready'), findsNothing);
    });

    testWidgets('the countdown shows only in the last ten seconds', (
      tester,
    ) async {
      recordHaptics(tester);
      final service = _VoiceMessageService(firestore, auth);
      final take = await startTake(tester, service);

      await tick(tester, take.clock, 12_000);
      expect(countdown, findsNothing);
      await tick(tester, take.clock, 49_900);
      expect(countdown, findsNothing);
      expect(haptics, isEmpty);

      await tick(tester, take.clock, 50_000);
      expect(countdown, findsOneWidget);
      expect(
        find.descendant(of: countdown, matching: find.text('10 s left')),
        findsOneWidget,
      );
      expect(haptics, hasLength(1));

      await tick(tester, take.clock, 55_200);
      expect(
        find.descendant(of: countdown, matching: find.text('5 s left')),
        findsOneWidget,
      );
      await tick(tester, take.clock, 59_999);
      expect(
        find.descendant(of: countdown, matching: find.text('1 s left')),
        findsOneWidget,
      );
      // The warning is given once per take, not every tick.
      expect(haptics, hasLength(1));

      // A manual stop in the final seconds is still a manual stop.
      await tester.tap(labelled('Stop recording'));
      await tester.pump();
      expect(find.text('Voice message ready'), findsOneWidget);
      expect(countdown, findsNothing);
      expect(stoppedAtLimit, findsNothing);
      expect(haptics, hasLength(1));
    });

    testWidgets('a manual stop before the cap still works unchanged', (
      tester,
    ) async {
      recordHaptics(tester);
      final service = _VoiceMessageService(firestore, auth);
      final take = await startTake(tester, service);

      await tick(tester, take.clock, 42_600);
      expect(find.text('0:42 / 1:00'), findsOneWidget);
      await tester.tap(labelled('Stop recording'));
      await tester.pump();

      expect(find.text('Voice message ready'), findsOneWidget);
      expect(stoppedAtLimit, findsNothing);
      expect(countdown, findsNothing);
      expect(haptics, isEmpty);

      await tester.tap(find.text('Send voice message'));
      await tester.pumpAndSettle();
      expect(service.sentVoices.single.durationSeconds, 42);
    });

    testWidgets('a Stop tap during the automatic stop does not stop twice', (
      tester,
    ) async {
      final backend = _GatedStopBackend();
      final service = _VoiceMessageService(firestore, auth);
      final take = await startTake(tester, service, backend: backend);

      await tick(tester, take.clock, 60_100);
      expect(backend.stopCalls, 1);
      // The native stop is still in flight when the person taps Stop.
      await tester.tap(labelled('Stop recording'));
      await tester.pump();
      expect(backend.stopCalls, 1);

      backend.gate.complete('handle');
      await tester.pump();
      expect(find.text('Voice message ready'), findsOneWidget);
      expect(stoppedAtLimit, findsOneWidget);
      expect(backend.stopCalls, 1);
      expect(take.audio.discarded, isFalse);
    });

    testWidgets('a camera clip the camera capped at 60 s is sent as 60 s', (
      tester,
    ) async {
      final service = _VoiceMessageService(firestore, auth);
      var measured = const Duration(milliseconds: 60_400);
      await tester.pumpWidget(
        host(
          service,
          videoPicker: (source) async => XFile.fromData(
            Uint8List(2048),
            mimeType: 'video/mp4',
            name: '${source.name}.mp4',
          ),
          videoInspector: (_) async => measured,
        ),
      );
      await tester.pumpAndSettle();

      Future<void> recordVideo() async {
        await tester.tap(find.byTooltip('Add photo or video'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record video'));
        await tester.pumpAndSettle();
      }

      await recordVideo();
      expect(service.sentVideos.single.durationSeconds, 60);

      // Past the grace it is a longer video, and it is still refused.
      measured = const Duration(milliseconds: 62_500);
      await recordVideo();
      expect(service.sentVideos, hasLength(1));
    });
  });
}

/// A native stop that stays in flight until the test completes [gate].
class _GatedStopBackend extends FakeRecorderBackend {
  final Completer<String?> gate = Completer<String?>();
  int stopCalls = 0;

  @override
  Future<String?> stop() {
    stopCalls += 1;
    return gate.future;
  }
}

class _VoiceMessageService extends MessageService {
  _VoiceMessageService(FakeFirebaseFirestore firestore, MockFirebaseAuth auth)
    : super(firestore: firestore, auth: auth);

  final List<({RecordedAudio audio, int durationSeconds})> sentVoices = [];
  final List<({XFile video, int durationSeconds})> sentVideos = [];

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value(const <Message>[]);

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
  Future<String> enqueueVoiceMessage({
    required String conversationId,
    required RecordedAudio audio,
    required int durationSeconds,
  }) async {
    sentVoices.add((audio: audio, durationSeconds: durationSeconds));
    return 'queued-voice-${sentVoices.length}';
  }

  @override
  Future<String> enqueueVideoMessage({
    required String conversationId,
    required XFile video,
    required int durationSeconds,
  }) async {
    // The production queue's own 1..60 check, which a clip past the grace
    // must still fail.
    if (durationSeconds < 1 || durationSeconds > directVideoMaxSeconds) {
      throw StateError('Videos must be between 1 and 60 seconds.');
    }
    sentVideos.add((video: video, durationSeconds: durationSeconds));
    return 'queued-video-${sentVideos.length}';
  }
}
