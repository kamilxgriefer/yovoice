import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_company_file.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_company_file_service.dart';
import 'package:yovoice/features/servers/data/services/server_session_controller.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_channel_scene.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_company_files_board.dart';

import 'server_test_support.dart';

const companyFileId = 'cf_0000000000000000000000000000000000000000';

Server companyFilesServer() => const Server(
  id: 's',
  name: 'Studio North',
  description: 'Zespół',
  ownerId: 'owner',
  type: ServerType.company,
  privacy: ServerPrivacy.inviteOnly,
  defaultChannelId: 'files',
  schemaVersion: 1,
  templateVersion: 1,
  revision: 1,
  activationState: 'active',
);

ServerChannel companyFilesChannel() => const ServerChannel(
  id: 'files',
  serverId: 's',
  name: 'Pliki',
  kind: ServerChannelKind.files,
  position: 1,
  access: ServerChannelAccess.members,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

ServerChannel companyMeetingChannel() => const ServerChannel(
  id: 'meeting',
  serverId: 's',
  name: 'Spotkanie',
  kind: ServerChannelKind.meeting,
  position: 0,
  access: ServerChannelAccess.members,
  roomId: 'room-meeting',
  experience: RoomExperience.community,
  mediaMode: ServerMediaMode.meeting,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

ServerCompanyFile companyFile({String ownerId = 'owner'}) => ServerCompanyFile(
  id: companyFileId,
  serverId: 's',
  channelId: 'files',
  ownerId: ownerId,
  ownerDisplayName: ownerId == 'owner' ? 'Kamil' : 'Ola',
  displayName: 'Plan kwartalny.pdf',
  file: ServerCompanyFileDescriptor(
    storagePath: 'server_company_files/s/files/$ownerId/$companyFileId.pdf',
    generation: '1700000000000001',
    contentType: 'application/pdf',
    size: 2048,
  ),
  revision: 1,
  createdAt: DateTime.utc(2026, 9, 13, 10),
  updatedAt: DateTime.utc(2026, 9, 13, 10),
);

Map<String, Object?> companyFileData() => {
  'schemaVersion': 1,
  'fileKind': 'companyFile',
  'serverId': 's',
  'clubId': 's',
  'channelId': 'files',
  'fileId': companyFileId,
  'ownerId': 'owner',
  'ownerDisplayName': 'Kamil',
  'ownerPhotoUrl': null,
  'displayName': 'Plan kwartalny.pdf',
  'status': 'published',
  'file': {
    'storagePath': 'server_company_files/s/files/owner/$companyFileId.pdf',
    'generation': '1700000000000001',
    'contentType': 'application/pdf',
    'size': 2048,
  },
  'revision': 1,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 10)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 10)),
};

Map<Object?, Object?> reservation(DateTime now) => {
  'schemaVersion': 1,
  'serverId': 's',
  'channelId': 'files',
  'fileId': companyFileId,
  'displayName': 'notes.txt',
  'expiresAtMillis': now
      .add(const Duration(minutes: 10))
      .millisecondsSinceEpoch,
  'file': {
    'storagePath': 'server_company_files/s/files/owner/$companyFileId.txt',
    'contentType': 'text/plain',
    'size': 12,
    'uploadMetadata': {
      'yovoiceServerId': 's',
      'yovoiceChannelId': 'files',
      'yovoiceOwnerUid': 'owner',
      'yovoiceFileId': companyFileId,
      'yovoiceAssetKind': 'companyFile',
    },
  },
};

void main() {
  test(
    'Company File descriptor is scoped to its canonical private object',
    () async {
      final firestore = FakeFirebaseFirestore();
      final reference = firestore
          .collection('clubs')
          .doc('s')
          .collection('channels')
          .doc('files')
          .collection('files')
          .doc(companyFileId);
      await reference.set(companyFileData());

      final file = ServerCompanyFile.fromFirestore(
        await reference.get(),
        serverId: 's',
        channelId: 'files',
      );
      expect(file.displayName, 'Plan kwartalny.pdf');
      expect(file.file.generation, '1700000000000001');

      await reference.update({
        'file.storagePath':
            'server_company_files/s/files/other/$companyFileId.pdf',
      });
      final changed = await reference.get();
      expect(
        () => ServerCompanyFile.fromFirestore(
          changed,
          serverId: 's',
          channelId: 'files',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'upload retries finalization without a second reserve or upload',
    () async {
      final now = DateTime.utc(2026, 9, 13, 12);
      final bytes = Uint8List.fromList(utf8.encode('hello team!!'));
      final calls = <(String, Map<String, Object?>)>[];
      final ids = ['reserve-request-1', 'finalize-request-1'];
      var uploads = 0;
      var finalizeAttempts = 0;
      final service = ServerCompanyFileService(
        clock: () => now,
        requestIdFactory: () => ids.removeAt(0),
        uploader: (data, target) async {
          uploads += 1;
          expect(data, bytes);
          expect(target.uploadMetadata['yovoiceAssetKind'], 'companyFile');
          return '1700000000000001';
        },
        callOverride: (callable, payload) async {
          calls.add((callable, Map<String, Object?>.from(payload)));
          if (callable == 'reserveServerCompanyFileV1') return reservation(now);
          finalizeAttempts += 1;
          if (finalizeAttempts == 1) throw StateError('connection closed');
          return const {
            'schemaVersion': 1,
            'serverId': 's',
            'channelId': 'files',
            'fileId': companyFileId,
            'revision': 1,
            'status': 'published',
          };
        },
      );
      final attempt = service.newCompanyFileUploadAttempt(
        serverId: 's',
        channelId: 'files',
        selection: ServerCompanyFileSelection(
          displayName: 'notes.txt',
          contentType: 'text/plain',
          bytes: bytes,
        ),
      );

      await expectLater(service.publishCompanyFile(attempt), throwsStateError);
      expect(await service.publishCompanyFile(attempt), companyFileId);
      expect(uploads, 1);
      expect(calls.map((call) => call.$1), [
        'reserveServerCompanyFileV1',
        'finalizeServerCompanyFileV1',
        'finalizeServerCompanyFileV1',
      ]);
      expect(calls.first.$2, {
        'serverId': 's',
        'channelId': 'files',
        'requestId': 'reserve-request-1',
        'displayName': 'notes.txt',
        'contentType': 'text/plain',
        'size': 12,
      });
      expect(calls[1].$2, calls[2].$2);
      expect(calls[1].$2, {
        'serverId': 's',
        'channelId': 'files',
        'fileId': companyFileId,
        'generation': '1700000000000001',
        'requestId': 'finalize-request-1',
      });
    },
  );

  test('signed access accepts only the backend storage host', () {
    final payload = <Object?, Object?>{
      'schemaVersion': 1,
      'serverId': 's',
      'channelId': 'files',
      'fileId': companyFileId,
      'displayName': 'Plan kwartalny.pdf',
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
      'file': const <Object?, Object?>{
        'url':
            'https://storage.googleapis.com/private/plan.pdf?X-Goog-Signature=ok',
        'generation': '1700000000000001',
        'contentType': 'application/pdf',
        'size': 2048,
      },
    };
    expect(
      ServerCompanyFileAccess.fromMap(payload).url.host,
      'storage.googleapis.com',
    );
    final unsafe = Map<Object?, Object?>.from(payload)
      ..['file'] = {
        ...(payload['file']! as Map<Object?, Object?>),
        'url': 'https://storage.googleapis.com.evil.test/private/plan.pdf',
      };
    expect(
      () => ServerCompanyFileAccess.fromMap(unsafe),
      throwsFormatException,
    );
  });

  testWidgets('workspace routes Files to the persistent board', (tester) async {
    final repository = TestServerRepository()
      ..servers = [companyFilesServer()]
      ..channels = [companyFilesChannel()]
      ..companyFiles = [companyFile()];
    await pumpServers(
      tester,
      ServerWorkspaceScreen(
        serverId: 's',
        repository: repository,
        initialChannelId: 'files',
        isRootTab: true,
      ),
      size: const Size(1100, 820),
    );
    expect(
      find.byKey(const ValueKey('server-company-files-board')),
      findsOneWidget,
    );
    expect(find.text('Wkrótce'), findsNothing);
    expect(find.text('Plan kwartalny.pdf'), findsOneWidget);
  });

  testWidgets('member uploads, opens and deletes their own file', (
    tester,
  ) async {
    final repository = TestServerRepository()
      ..myRole = ServerMemberRole.member
      ..companyFiles = [companyFile()];
    Uri? opened;
    await pumpServers(
      tester,
      ServerCompanyFilesBoard(
        server: companyFilesServer(),
        channel: companyFilesChannel(),
        repository: repository,
        role: ServerMemberRole.member,
        online: Stream.value(true),
        openFile: (url) async {
          opened = url;
          return true;
        },
      ),
      size: const Size(390, 844),
    );
    await tester.tap(
      find.byKey(ValueKey('server-company-file-open-$companyFileId')),
    );
    await tester.pumpAndSettle();
    expect(opened?.host, 'storage.googleapis.com');

    await tester.tap(
      find.byKey(ValueKey('server-company-file-delete-$companyFileId')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Usunąć ten plik?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Usuń'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1, 'deleteServerCompanyFileV1');
    expect(repository.calls.last.$2['expectedRevision'], 1);
  });

  testWidgets('empty member can pick and publish a supported file', (
    tester,
  ) async {
    final repository = TestServerRepository()..myRole = ServerMemberRole.member;
    await pumpServers(
      tester,
      ServerCompanyFilesBoard(
        server: companyFilesServer(),
        channel: companyFilesChannel(),
        repository: repository,
        role: ServerMemberRole.member,
        online: Stream.value(true),
        pickFile: () async => ServerCompanyFileSelection(
          displayName: 'notes.txt',
          contentType: 'text/plain',
          bytes: Uint8List.fromList(utf8.encode('hello team!!')),
        ),
      ),
      size: const Size(390, 844),
    );
    await tester.tap(find.text('Dodaj plik'));
    await tester.pumpAndSettle();
    // The picked file is confirmed in the media review first (ADR-210).
    await tester.tap(find.byKey(const ValueKey('yo-media-review-send')));
    await tester.pumpAndSettle();
    expect(repository.companyFileUploads, 1);
    expect(repository.calls.map((call) => call.$1), [
      'reserveServerCompanyFileV1',
      'finalizeServerCompanyFileV1',
    ]);
  });

  testWidgets('picked file is reviewed before upload; Cancel publishes none', (
    tester,
  ) async {
    final repository = TestServerRepository()..myRole = ServerMemberRole.member;
    await pumpServers(
      tester,
      ServerCompanyFilesBoard(
        server: companyFilesServer(),
        channel: companyFilesChannel(),
        repository: repository,
        role: ServerMemberRole.member,
        online: Stream.value(true),
        pickFile: () async => ServerCompanyFileSelection(
          displayName: 'Plan kwartalny.pdf',
          contentType: 'application/pdf',
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.7 plan')),
        ),
      ),
      size: const Size(390, 844),
    );
    await tester.tap(find.text('Dodaj plik'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('yo-media-review')), findsOneWidget);
    expect(find.text('Plan kwartalny.pdf'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(repository.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('yo-media-review-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('yo-media-review')), findsNothing);
    expect(repository.companyFileUploads, 0);
    expect(repository.calls, isEmpty);
  });

  testWidgets('a picked image is previewed as a photo before upload', (
    tester,
  ) async {
    final repository = TestServerRepository()..myRole = ServerMemberRole.member;
    await pumpServers(
      tester,
      ServerCompanyFilesBoard(
        server: companyFilesServer(),
        channel: companyFilesChannel(),
        repository: repository,
        role: ServerMemberRole.member,
        online: Stream.value(true),
        pickFile: () async => ServerCompanyFileSelection(
          displayName: 'tablica.png',
          contentType: 'image/png',
          bytes: Uint8List(2048),
        ),
      ),
      size: const Size(390, 844),
    );
    await tester.tap(find.text('Dodaj plik'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Zdjęcie, 2 KB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('yo-media-review-send')));
    await tester.pumpAndSettle();
    expect(repository.companyFileUploads, 1);
  });

  testWidgets('guest and offline states fail closed', (tester) async {
    final repository = TestServerRepository()..myRole = ServerMemberRole.guest;
    await pumpServers(
      tester,
      ServerCompanyFilesBoard(
        server: companyFilesServer(),
        channel: companyFilesChannel(),
        repository: repository,
        role: ServerMemberRole.guest,
        online: Stream.value(false),
      ),
      size: const Size(320, 760),
      textScale: 2,
    );
    expect(
      find.byKey(const ValueKey('server-company-files-offline')),
      findsOneWidget,
    );
    expect(find.text('Dodaj plik'), findsNothing);
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prejoin video capabilities no longer say Coming soon', (
    tester,
  ) async {
    final repository = TestServerRepository()
      ..servers = [companyFilesServer()]
      ..channels = [companyMeetingChannel()];
    final session = ServerSessionController(
      repository: repository,
      connector: FakeServerMediaConnector(),
    );
    addTearDown(session.dispose);
    await pumpServers(
      tester,
      Scaffold(
        body: ServerChannelScene(
          server: companyFilesServer(),
          channel: companyMeetingChannel(),
          session: session,
          currentUserId: 'owner',
          role: ServerMemberRole.owner,
        ),
      ),
      size: const Size(390, 844),
    );
    expect(find.text('Kamera · Dostępne po dołączeniu'), findsOneWidget);
    expect(
      find.text('Udostępnij ekran · Dostępne po dołączeniu'),
      findsOneWidget,
    );
    expect(find.textContaining('Wkrótce'), findsNothing);
  });
}
