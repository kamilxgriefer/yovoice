// Developer-only visual capture for the friend-request consent item: every
// incoming-request surface with its labelled Accept / Decline, at phone and
// desktop widths, Dark and Pearl, English and Polish, including a long name
// and a stale row.
//
// Technique of `test/nb_confirm_upload_capture.dart`: real widgets, fixtures
// through the screens' own constructor seams, an exact viewport and the real
// product fonts (Inter + Material Icons).
//
// It is NOT a test and deliberately does not end in `_test.dart`, so the
// regular suite never writes artifacts. Run it explicitly:
//
//   flutter test test/nb_friend_request_capture.dart
//
// PNGs land OUTSIDE git, in the evidence folder named below, or in the
// directory given by the NB_FRAMES_DIR environment variable.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/call_tone_service.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_request_decision.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/friend_request_banner_decision.dart';
import 'package:yovoice/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';

const String _me = 'me-uid';
const String _defaultOut =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-25/friend-request/frames';

final _captureKey = GlobalKey();

String _outDir() {
  final configured = Platform.environment['NB_FRAMES_DIR'];
  return configured == null || configured.trim().isEmpty
      ? _defaultOut
      : configured.trim();
}

String _resolveMaterialFontRoot() {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null) {
    final configured = '$configuredRoot/bin/cache/artifacts/material_fonts';
    if (File('$configured/MaterialIcons-Regular.otf').existsSync()) {
      return configured;
    }
  }
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = '${directory.path}/bin/cache/artifacts/material_fonts';
    if (File('$candidate/MaterialIcons-Regular.otf').existsSync()) {
      return candidate;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

Future<ByteData> _read(String path) async {
  final bytes = Uint8List.fromList(File(path).readAsBytesSync());
  return ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(_read('assets/fonts/InterVariable.ttf'))
    ..addFont(_read('assets/fonts/InterVariable-Italic.ttf'));
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(_read('${_resolveMaterialFontRoot()}/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> _capturePng(WidgetTester tester, String filename) async {
  await tester.runAsync(() async {
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final warmup = await boundary.toImage(pixelRatio: 1);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${_outDir()}/$filename.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _EmptyGraph implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCalls implements DirectCallGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietVoice extends VoiceCallService {
  _QuietVoice() : super.forTesting();
}

class _NoServers implements ServerRepository {
  @override
  Stream<List<Server>> watchMyServers() => Stream.value(const <Server>[]);

  @override
  Stream<ServerMemberRole?> watchMyRole(String serverId) => Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _frame({
  required Widget home,
  required bool pearl,
  required bool polish,
  YoTopNotificationController? banner,
}) => RepaintBoundary(
  key: _captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: polish ? const Locale('pl') : const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: banner == null
        ? null
        : (context, child) =>
              YoTopNotificationHost(controller: banner, child: child!),
    home: home,
  ),
);

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _me, email: 'me@yovoice.app'),
    );
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
    debugCallToneServiceOverride = CallToneService(enabled: () => false);
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
    debugCallToneServiceOverride = null;
    FriendService.clearSharedReadCaches();
  });

  FriendService friends() => FriendService(
    firestore: db,
    auth: auth,
    mutationInvoker: (name, data) async => <String, dynamic>{
      'outcome': 'accepted',
    },
  );

  Future<void> seedInbox() async {
    Future<void> request(String uid, String name) => db
        .collection('users')
        .doc(_me)
        .collection('friendRequests')
        .doc(uid)
        .set(<String, dynamic>{
          'senderId': uid,
          'senderName': name,
          'senderPhotoUrl': null,
          'createdAt': Timestamp.now(),
        });
    Future<void> row(String id, String uid, String name, int minutes) => db
        .collection('users')
        .doc(_me)
        .collection('notifications')
        .doc(id)
        .set(<String, dynamic>{
          'type': 'friendRequest',
          'actorId': uid,
          'actorName': name,
          'actorPhotoUrl': null,
          'targetId': null,
          'targetLabel': null,
          'isRead': false,
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(Duration(minutes: minutes)),
          ),
          'dedupeKey': id,
          'bellSuppressed': false,
        });
    await request('ola', 'Ola Nowak');
    await request(
      'long',
      'Aleksandra Wiśniewska-Kowalczyk z bardzo długim nazwiskiem',
    );
    await row('friendRequest_ola_1', 'ola', 'Ola Nowak', 2);
    await row('friendRequest_gone_1', 'gone', 'Kuba', 90);
  }

  for (final (width, height) in const [
    (320.0, 700.0),
    (390.0, 844.0),
    (1280.0, 900.0),
  ]) {
    for (final pearl in const [false, true]) {
      for (final polish in const [false, true]) {
        if (polish && width > 400 && pearl) continue;
        if (width < 390 && (pearl || !polish)) continue;
        final name =
            'inbox-${width.toInt()}-${pearl ? 'pearl' : 'dark'}-'
            '${polish ? 'pl' : 'en'}';
        testWidgets(name, (tester) async {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await seedInbox();
          final notifications = NotificationService(firestore: db, auth: auth);
          final messages = MessageService(
            firestore: db,
            auth: auth,
            notificationService: notifications,
          );
          addTearDown(messages.dispose);
          await tester.pumpWidget(
            _frame(
              pearl: pearl,
              polish: polish,
              home: NotificationsScreen(
                isRootTab: true,
                acknowledgeOnVisible: false,
                friendService: friends(),
                messageService: messages,
                notificationService: notifications,
                currentUserId: _me,
                firestore: db,
                auth: auth,
                openNotification: (_) async {},
              ),
            ),
          );
          await _settle(tester);
          await _capturePng(tester, name);
        });
      }
    }
  }

  for (final pearl in const [false, true]) {
    testWidgets('banner-390-${pearl ? 'pearl' : 'dark'}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final banner = YoTopNotificationController();
      addTearDown(banner.dispose);
      await tester.pumpWidget(
        _frame(
          pearl: pearl,
          polish: false,
          banner: banner,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      await tester.pump();
      banner.show(
        YoTopNotification(
          title: 'Ola Nowak sent you a friend request',
          type: NotificationType.friendRequest,
          onOpen: () {},
          decision: friendRequestBannerDecision(
            type: NotificationType.friendRequest,
            senderId: 'ola',
            senderName: 'Ola Nowak',
            friendService: friends,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _capturePng(tester, 'banner-390-${pearl ? 'pearl' : 'dark'}');
      if (!pearl) {
        // The banner's pair arms 500 ms after its entrance (arrival guard).
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(
          find.byKey(const ValueKey('yo-top-notification-accept')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await _capturePng(tester, 'banner-390-dark-accepted');
      }
      banner.clear();
      await tester.pump(const Duration(seconds: 6));
    });
  }

  for (final (width, pearl) in const [(390.0, false), (1280.0, true)]) {
    testWidgets('prompt-${width.toInt()}-${pearl ? 'pearl' : 'dark'}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _frame(
          pearl: pearl,
          polish: true,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => unawaited(
                    showFriendRequestPrompt(
                      context,
                      senderId: 'ola',
                      senderName: 'Ola Nowak',
                      friendService: friends(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      await _capturePng(tester, 'prompt-${width.toInt()}-pl');
    });
  }

  for (final (width, pearl) in const [
    (390.0, false),
    (390.0, true),
    (1280.0, false),
  ]) {
    testWidgets('profile-${width.toInt()}-${pearl ? 'pearl' : 'dark'}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await db.collection('publicProfiles').doc('ola').set({
        'uid': 'ola',
        'displayName': 'Ola Nowak',
        'username': 'ola',
      });
      final notifications = NotificationService(firestore: db, auth: auth);
      final messages = MessageService(
        firestore: db,
        auth: auth,
        notificationService: notifications,
      );
      addTearDown(messages.dispose);
      await tester.pumpWidget(
        _frame(
          pearl: pearl,
          polish: false,
          home: FriendProfileScreen(
            friend: const FriendUser(
              id: 'ola',
              displayName: 'Ola Nowak',
              email: '',
              photoUrl: null,
              isOnline: false,
              lastSeen: null,
            ),
            firestore: db,
            auth: auth,
            friendService: friends(),
            messageService: messages,
            profileService: ProfileService(firestore: db, auth: auth),
            followService: FollowService(firestore: db, auth: auth),
            socialGraphService: _EmptyGraph(),
            creatorPinnedPostService: CreatorPinnedPostService(
              firestore: db,
              auth: auth,
            ),
            isFriend: false,
            relationshipStatusResolver: (_) async =>
                FriendRelationshipStatus.requestReceived,
            directCallService: _NoCalls(),
            voiceCallService: _QuietVoice(),
            serverRepository: _NoServers(),
          ),
        ),
      );
      await _settle(tester);
      await _capturePng(
        tester,
        'profile-${width.toInt()}-${pearl ? 'pearl' : 'dark'}',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final (width, pearl) in const [(390.0, false), (1280.0, true)]) {
    testWidgets('preview-${width.toInt()}-${pearl ? 'pearl' : 'dark'}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await db.collection('users').doc(_me).set({'uid': _me});
      await db.collection('publicProfiles').doc('ola').set({
        'uid': 'ola',
        'displayName': 'Ola Nowak',
        'username': 'ola',
      });
      await db
          .collection('users')
          .doc(_me)
          .collection('friendRequests')
          .doc('ola')
          .set(<String, dynamic>{
            'senderId': 'ola',
            'senderName': 'Ola Nowak',
            'createdAt': Timestamp.now(),
          });
      await tester.pumpWidget(
        _frame(
          pearl: pearl,
          polish: false,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => unawaited(
                    showProfilePreview(
                      context,
                      userId: 'ola',
                      displayName: 'Ola Nowak',
                      firestore: db,
                      auth: auth,
                      friendService: friends(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      await _capturePng(
        tester,
        'preview-${width.toInt()}-${pearl ? 'pearl' : 'dark'}',
      );
    });
  }
}
