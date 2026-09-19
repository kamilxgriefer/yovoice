// Next build, Task 3: friend profile quick actions — frame harness.
//
// Renders the REAL FriendProfileScreen with fixture data through its
// constructor seams (no Firebase app, no network, no callable) in three
// relationship variants: a friend, a non-friend (calls unavailable) and a
// person the viewer blocked. Widths 390 and 1440, Dark and Pearl, locale pl,
// 100 % text, plus the friend at 390 / 200 % text and the Więcej sheet.
//
// No `_test` suffix, so the ordinary suite skips it. Run explicitly:
//
//   flutter test test/nb_friend_actions_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/friend-actions

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/nb-friend-actions',
);

final _capture = GlobalKey();

/// The Material fonts of whichever Flutter SDK runs the test: walked up from
/// the tester binary, with the Mac install paths as fallbacks.
String get _fontRoot {
  final candidates = <String>[];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add('${dir.path}/bin/cache/artifacts/material_fonts');
    candidates.add('${dir.path}/material_fonts');
    dir = dir.parent;
  }
  candidates.addAll(const <String>[
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ]);
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
  final inter = FontLoader('Inter');
  inter.addFont(
    Future.value(
      ByteData.view(
        Uint8List.fromList(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ).buffer,
      ),
    ),
  );
  await inter.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void _recordException(WidgetTester tester, String name) {
  final error = tester.takeException();
  if (error != null) {
    // ignore: avoid_print
    print('EXCEPTION $name :: $error');
  }
}

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', isEmailVerified: true),
);

ProfileMediaService _media(MockFirebaseAuth auth) => ProfileMediaService(
  auth: auth,
  invoker: (_, _) async => {
    'schemaVersion': 1,
    'available': false,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
  },
);

PublicIdentityRepository _identity() => PublicIdentityRepository(
  auth: _auth(),
  fetchOverride: (uids) async => {
    for (final uid in uids) uid: const {'role': 'user'},
  },
  flushDelay: const Duration(milliseconds: 1),
);

class _MutualGraph implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary(
        count: 6,
        sample: [
          for (final (uid, name) in const [
            ('ola', 'Ola'),
            ('kuba', 'Kuba'),
            ('zuzia', 'Zuzia'),
          ])
            SuggestedFriend(
              uid: uid,
              displayName: name,
              photoUrl: null,
              mutualCount: 1,
            ),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({
  required GlobalKey<NavigatorState> navigatorKey,
  required bool pearl,
  required Size size,
  double textScale = 1,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox.expand()),
  ),
);

typedef _Variant = ({
  String name,
  bool isFriend,
  FriendRelationshipStatus status,
});

const _variants = <_Variant>[
  (name: 'friend', isFriend: true, status: FriendRelationshipStatus.friends),
  (name: 'nonfriend', isFriend: false, status: FriendRelationshipStatus.none),
  (name: 'blocked', isFriend: false, status: FriendRelationshipStatus.blocked),
];

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = _identity();
    ProfileMediaService.clearAllMediaAccessCaches();
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpFriend(
    WidgetTester tester, {
    required _Variant variant,
    required bool pearl,
    required Size size,
    double textScale = 1,
  }) async {
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    const friendId = 'friend-ola';
    await tester.runAsync(() async {
      await db.collection('users').doc('me').set({
        'uid': 'me',
        'displayName': 'Maja Kowalska',
        'email': 'me@yovoice.app',
      });
      await db.collection('publicProfiles').doc(friendId).set({
        'uid': friendId,
        'displayName': 'Ola Nowak',
        'username': 'ola.codziennie',
        'statusMessage': 'Poranne spacery i dobre podcasty',
        'bio':
            'Robię Momenty o dźwiękach miasta. Wieczorami prowadzę serwer '
            'o książkach.',
        'nativeLanguage': 'polski',
        'spokenLanguages': ['angielski'],
        'friendCount': 312,
        'followerCount': 4210,
        'followingCount': 188,
        'accountType': 'creator',
        'premiumIdentity': true,
        'creatorAudienceVisible': true,
      });
    });
    final notifications = NotificationService(firestore: db, auth: auth);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(
        navigatorKey: navigatorKey,
        pearl: pearl,
        size: size,
        textScale: textScale,
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(
          friend: const FriendUser(
            id: friendId,
            displayName: 'Ola Nowak',
            email: '',
            photoUrl: null,
            isOnline: true,
            lastSeen: null,
          ),
          firestore: db,
          auth: auth,
          friendService: FriendService(
            firestore: db,
            auth: auth,
            notificationService: notifications,
          ),
          messageService: MessageService(
            firestore: db,
            auth: auth,
            notificationService: notifications,
          ),
          profileService: ProfileService(firestore: db, auth: auth),
          followService: FollowService(firestore: db, auth: auth),
          socialGraphService: _MutualGraph(),
          profileMediaService: _media(auth),
          creatorPinnedPostService: CreatorPinnedPostService(
            firestore: db,
            auth: auth,
          ),
          isFriend: variant.isFriend,
          relationshipStatusResolver: (_) async => variant.status,
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await settle(tester);
  }

  Future<void> run(
    WidgetTester tester,
    String name, {
    required _Variant variant,
    required bool pearl,
    required Size size,
    double textScale = 1,
    bool openMore = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpFriend(
      tester,
      variant: variant,
      pearl: pearl,
      size: size,
      textScale: textScale,
    );
    if (openMore) {
      await tester.tap(
        find.byKey(const ValueKey('friend-profile-more-button')),
      );
      await settle(tester);
    }
    await _shoot(tester, name);
    _recordException(tester, name);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  for (final variant in _variants) {
    for (final pearl in const [false, true]) {
      for (final (width, height) in const [(390.0, 844.0), (1440.0, 900.0)]) {
        final theme = pearl ? 'pearl' : 'dark';
        final name =
            'friend-profile-${variant.name}_${width.toInt()}_${theme}_pl_100';
        testWidgets(name, (tester) async {
          await run(
            tester,
            name,
            variant: variant,
            pearl: pearl,
            size: Size(width, height),
          );
        });
      }
    }
  }

  for (final pearl in const [false, true]) {
    final theme = pearl ? 'pearl' : 'dark';
    testWidgets('friend-profile-friend_390_${theme}_pl_200', (tester) async {
      await run(
        tester,
        'friend-profile-friend_390_${theme}_pl_200-full',
        variant: _variants.first,
        pearl: pearl,
        size: const Size(390, 1800),
        textScale: 2,
      );
    });
    testWidgets('friend-profile-friend_more-sheet_$theme', (tester) async {
      await run(
        tester,
        'friend-profile-friend_390_${theme}_pl_100_more-sheet',
        variant: _variants.first,
        pearl: pearl,
        size: const Size(390, 844),
        openMore: true,
      );
    });
  }
  testWidgets('friend-profile-friend_768_dark_pl_100', (tester) async {
    await run(
      tester,
      'friend-profile-friend_768_dark_pl_100',
      variant: _variants.first,
      pearl: false,
      size: const Size(768, 1024),
    );
  });
}
