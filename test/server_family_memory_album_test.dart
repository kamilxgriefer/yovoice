import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/servers/data/models/server_family_memory.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_family_memory_service.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_family_memory_album.dart';

import 'voice_moment_test_doubles.dart';

class MemoryRepository implements ServerFamilyMemoryRepository {
  MemoryRepository(this.stream);

  final Stream<List<ServerFamilyMemory>> stream;
  final deletes = <Map<String, Object?>>[];
  ServerFamilyMemoryPublishAttempt? attempt;
  int publishCalls = 0;
  int requestCount = 0;

  @override
  Stream<List<ServerFamilyMemory>> watchFamilyMemories(
    String serverId,
    String channelId,
  ) => stream;

  @override
  String newFamilyMemoryRequestId() => 'family_request_${++requestCount}';

  @override
  ServerFamilyMemoryPublishAttempt newFamilyMemoryPublishAttempt({
    required String serverId,
    required String channelId,
    required String caption,
    required Uint8List photoBytes,
    required String photoContentType,
    required RecordedAudio voice,
    required int voiceDurationMs,
  }) {
    return attempt = ServerFamilyMemoryPublishAttempt(
      serverId: serverId,
      channelId: channelId,
      caption: caption.trim(),
      photoBytes: photoBytes,
      photoContentType: photoContentType,
      voice: voice,
      voiceDurationMs: voiceDurationMs,
      reserveRequestId: newFamilyMemoryRequestId(),
      finalizeRequestId: newFamilyMemoryRequestId(),
    );
  }

  @override
  Future<String> publishFamilyMemory(
    ServerFamilyMemoryPublishAttempt attempt,
  ) async {
    publishCalls += 1;
    return 'fm_memory_001';
  }

  @override
  Future<ServerFamilyMemoryMediaAccess> getFamilyMemoryMediaAccess({
    required String serverId,
    required String channelId,
    required String memoryId,
  }) async => ServerFamilyMemoryMediaAccess(
    serverId: serverId,
    channelId: channelId,
    memoryId: memoryId,
    expiresAt: DateTime.now().add(const Duration(seconds: 90)),
    photo: ServerFamilyMemoryMediaAsset(
      url: Uri.parse('https://media.example/$memoryId.jpg?signature=photo'),
      generation: '1700000000000001',
      contentType: 'image/jpeg',
      size: 2048,
    ),
    voice: ServerFamilyMemoryMediaAsset(
      url: Uri.parse('https://media.example/$memoryId.m4a?signature=voice'),
      generation: '1700000000000002',
      contentType: 'audio/mp4',
      size: 4096,
      durationMs: 4200,
    ),
  );

  @override
  Future<void> deleteFamilyMemory({
    required String serverId,
    required String channelId,
    required String memoryId,
    required int expectedRevision,
    required String requestId,
  }) async {
    deletes.add({
      'serverId': serverId,
      'channelId': channelId,
      'memoryId': memoryId,
      'expectedRevision': expectedRevision,
      'requestId': requestId,
    });
  }
}

class PickerStub extends ImagePicker {
  PickerStub(this.file);

  final XFile? file;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => file;
}

ServerFamilyMemory memory() => ServerFamilyMemory(
  id: 'fm_memory_001',
  serverId: 'family_server',
  channelId: 'memories',
  authorId: 'parent_1',
  authorDisplayName: 'Mama',
  caption: 'Niedziela razem',
  photo: const ServerFamilyMemoryAsset(
    storagePath:
        'family_moments/family_server/parent_1/fm_memory_001_photo.jpg',
    generation: '1700000000000001',
    contentType: 'image/jpeg',
    size: 2048,
  ),
  voice: const ServerFamilyMemoryAsset(
    storagePath:
        'family_moments/family_server/parent_1/fm_memory_001_voice.m4a',
    generation: '1700000000000002',
    contentType: 'audio/mp4',
    size: 4096,
    durationMs: 4200,
  ),
  revision: 1,
  createdAt: DateTime(2026, 9, 13),
);

Future<void> pumpAlbum(
  WidgetTester tester,
  MemoryRepository repository, {
  String currentUserId = 'parent_1',
  ImagePicker? picker,
  VoiceMomentRecorder Function()? recorderFactory,
  AudioPlayer Function()? playerFactory,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('pl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: ServerFamilyMemoryAlbum(
          serverId: 'family_server',
          channelId: 'memories',
          repository: repository,
          currentUserId: currentUserId,
          role: ServerMemberRole.member,
          colors: ServerIdentity.of(ServerType.family).resolve(Brightness.dark),
          compact: true,
          imagePicker: picker,
          recorderFactory: recorderFactory,
          playerFactory: playerFactory,
          photoBuilder: (_, _) => const ColoredBox(color: Colors.orange),
        ),
      ),
    ),
  );
}

Uint8List validPng() {
  final encoded = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+'
    'A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  return Uint8List.fromList([...encoded, ...List<int>.filled(128, 0)]);
}

void main() {
  testWidgets('album has honest loading and empty states', (tester) async {
    final controller = StreamController<List<ServerFamilyMemory>>();
    addTearDown(controller.close);
    await pumpAlbum(tester, MemoryRepository(controller.stream));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.add(const []);
    await tester.pump();

    expect(find.text('Nie ma jeszcze rodzinnych wspomnień'), findsOneWidget);
    expect(find.textContaining('Dodaj zdjęcie'), findsOneWidget);
  });

  testWidgets('signed photo, voice playback and author deletion are live', (
    tester,
  ) async {
    final players = <FakePreviewAudioPlayer>[];
    final repository = MemoryRepository(Stream.value([memory()]));
    await pumpAlbum(
      tester,
      repository,
      playerFactory: () {
        final player = FakePreviewAudioPlayer();
        players.add(player);
        return player;
      },
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('server-family-memory-fm_memory_001')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('server-family-memory-play-fm_memory_001')),
    );
    await tester.pump();
    expect(players.single.playCalls, 1);
    expect(players.single.lastSource, isA<UrlSource>());

    await tester.tap(
      find.byKey(const ValueKey('server-family-memory-delete-fm_memory_001')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('server-family-memory-delete-confirm')),
    );
    await tester.pumpAndSettle();

    expect(repository.deletes.single, {
      'serverId': 'family_server',
      'channelId': 'memories',
      'memoryId': 'fm_memory_001',
      'expectedRevision': 1,
      'requestId': 'family_request_1',
    });
  });

  testWidgets('member can pick, record and publish both private assets', (
    tester,
  ) async {
    final stopwatch = FakeStopwatch();
    final audio = FakeRecordedAudio();
    final capture = FakeAudioCapture()..result = audio;
    final repository = MemoryRepository(Stream.value(const []));
    await pumpAlbum(
      tester,
      repository,
      picker: PickerStub(
        XFile.fromData(validPng(), mimeType: 'image/png', name: 'family.png'),
      ),
      recorderFactory: () => VoiceMomentRecorder(
        backend: FakeRecorderBackend(),
        capture: capture,
        clock: stopwatch,
      ),
      playerFactory: FakePreviewAudioPlayer.new,
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('server-family-memory-add')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('server-family-memory-pick-photo')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('server-family-memory-record')));
    await tester.pump();
    stopwatch.value = const Duration(milliseconds: 4200);
    await tester.tap(find.byKey(const ValueKey('server-family-memory-record')));
    await tester.pump();

    final caption = find.byKey(const ValueKey('server-family-memory-caption'));
    await tester.ensureVisible(caption);
    await tester.enterText(caption, ' Niedziela razem ');
    final publish = find.byKey(const ValueKey('server-family-memory-publish'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(repository.publishCalls, 1);
    expect(repository.attempt?.caption, 'Niedziela razem');
    expect(repository.attempt?.photoContentType, 'image/png');
    expect(repository.attempt?.voiceDurationMs, 4200);
    expect(audio.discarded, isTrue);
    expect(
      find.byKey(const ValueKey('server-family-memory-feedback-success')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a voice note that reaches 0:30 counts down, stops itself and is kept',
    (tester) async {
      final haptics = <Object?>[];
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
      final stopwatch = FakeStopwatch();
      final audio = FakeRecordedAudio();
      final repository = MemoryRepository(Stream.value(const []));
      await pumpAlbum(
        tester,
        repository,
        picker: PickerStub(
          XFile.fromData(validPng(), mimeType: 'image/png', name: 'family.png'),
        ),
        recorderFactory: () => VoiceMomentRecorder(
          backend: FakeRecorderBackend(),
          capture: FakeAudioCapture()..result = audio,
          clock: stopwatch,
        ),
        playerFactory: FakePreviewAudioPlayer.new,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('server-family-memory-add')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('server-family-memory-pick-photo')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('server-family-memory-record')),
      );
      await tester.pump();

      final countdown = find.byKey(const ValueKey('yo-recording-countdown'));
      Future<void> tick(int ms) async {
        stopwatch.value = Duration(milliseconds: ms);
        await tester.pump(const Duration(milliseconds: 200));
      }

      await tick(19_900);
      expect(countdown, findsNothing);
      expect(haptics, isEmpty);
      await tick(20_000);
      expect(
        find.descendant(of: countdown, matching: find.text('Zostało 10 s')),
        findsOneWidget,
      );
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      await tick(27_500);
      expect(
        find.descendant(of: countdown, matching: find.text('Zostało 3 s')),
        findsOneWidget,
      );
      expect(haptics, hasLength(1));

      // Past the cap the composer stops itself and keeps the note.
      await tick(30_300);
      await tester.pump();
      expect(countdown, findsNothing);
      expect(find.text('Głos gotowy'), findsOneWidget);
      expect(
        find.text('Zatrzymano na limicie 0:30. Głos jest gotowy do zapisania.'),
        findsOneWidget,
      );
      expect(find.text('0:30 / 0:30'), findsOneWidget);
      expect(haptics, hasLength(2));
      expect(audio.discarded, isFalse);

      final publish = find.byKey(
        const ValueKey('server-family-memory-publish'),
      );
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(repository.publishCalls, 1);
      expect(repository.attempt?.voiceDurationMs, 30000);
    },
  );
}
