// Shared, controlled fixtures for the YO Moments overview (board 06) widget
// tests. Nothing here is a real account, a real recording or a real
// relationship — every list is explicit so each test states exactly what
// the screen was handed.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const viewerUid = 'viewer';

VoiceMoment overviewMoment(
  String id, {
  required String author,
  String? authorName,
  String caption = 'A caption',
  int seconds = 45,
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 2),
  bool liked = false,
  bool permanent = false,
}) {
  final createdAt = DateTime.now().subtract(age);
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: authorName ?? author,
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: seconds,
    likeCount: likes,
    commentCount: comments,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: permanent ? null : createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
    callerLiked: liked,
  );
}

/// Four authors, six live Moments, one 280-character caption.
List<VoiceMoment> populatedPool() => <VoiceMoment>[
  overviewMoment(
    'm1',
    author: 'maja',
    authorName: 'Maja',
    caption: 'Zanim obudzi się miasto.',
    likes: 24,
    comments: 6,
    age: const Duration(hours: 2),
  ),
  overviewMoment(
    'm2',
    author: 'kamil',
    authorName: 'Kamil',
    caption: 'Mała rzecz, dobry dzień.',
    seconds: 28,
    likes: 11,
    comments: 2,
    age: const Duration(hours: 5),
  ),
  overviewMoment(
    'm3',
    author: 'ola',
    authorName: 'Ola',
    caption: List<String>.filled(28, 'dziesięć z').join(' '),
    seconds: 60,
    likes: 58,
    comments: 9,
    age: const Duration(hours: 7),
  ),
  overviewMoment(
    'm4',
    author: 'bartek',
    authorName: 'Bartek',
    caption: '',
    seconds: 12,
    likes: 3,
    age: const Duration(minutes: 40),
  ),
  overviewMoment(
    'm5',
    author: 'maja',
    authorName: 'Maja',
    caption: 'Druga część.',
    seconds: 39,
    likes: 8,
    comments: 1,
    age: const Duration(hours: 1),
  ),
  overviewMoment(
    'm6',
    author: 'kamil',
    authorName: 'Kamil',
    caption: 'Krótka notatka po spacerze.',
    seconds: 19,
    likes: 2,
    age: const Duration(hours: 9),
    liked: true,
  ),
];

class StaticDiscovery implements MomentDiscoveryService {
  StaticDiscovery(this.moments, {this.gate, this.failAfterLoads});

  final List<VoiceMoment> moments;

  /// Holds the first load open (the loading state).
  final Completer<void>? gate;

  /// When set, every load past this count throws — the refresh-failure
  /// case, where content already on screen must survive.
  final int? failAfterLoads;

  int loadCalls = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loadCalls += 1;
    if (gate != null) await gate!.future;
    final limit = failAfterLoads;
    if (limit != null && loadCalls > limit) {
      throw StateError('unavailable');
    }
    return MomentDiscoveryFeed(
      moments: moments,
      fetchedCount: moments.length,
      drops: const <String, MomentDropReason>{},
      seed: seed ?? 0,
      poolExhausted: false,
    );
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThrowingDiscovery implements MomentDiscoveryService {
  int loadCalls = 0;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    loadCalls += 1;
    throw StateError('unavailable');
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      const <VoiceMoment>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StaticViews implements MomentViewsService {
  StaticViews(this.viewed);

  final Set<String> viewed;
  final List<String> marked = <String>[];

  @override
  Stream<Set<String>> watchViewedMomentIds() => Stream.value(viewed);

  @override
  Future<void> markViewed(String momentId) async => marked.add(momentId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuietFeed extends HomeFeedService {
  QuietFeed({super.firestore, super.auth, this.social = const []});

  final List<VoiceMoment> social;
  final List<String> likeWrites = <String>[];

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(social);

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    likeWrites.add('$momentId:$liked');
  }
}

class StaticFriends extends FriendService {
  StaticFriends({required super.firestore, required super.auth, this.friends});

  final List<FriendUser>? friends;

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream.value(friends ?? const <FriendUser>[]);
}

FriendUser friend(String id, {String? name, String username = ''}) => FriendUser(
  id: id,
  displayName: name ?? id,
  username: username,
  email: '',
  photoUrl: null,
  isOnline: false,
  lastSeen: null,
);

class SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

MockFirebaseAuth authAs([String uid = viewerUid]) =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));

/// Identity badges resolve through the shared singleton; point it at a
/// scripted fetcher so no Firebase app is needed. Returns the restorer.
VoidCallback installIdentityStub() {
  final original = PublicIdentityRepository.instance;
  PublicIdentityRepository.instance = PublicIdentityRepository(
    auth: authAs(),
    fetchOverride: (uids) async => <String, dynamic>{
      for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
    },
    flushDelay: const Duration(milliseconds: 1),
  );
  return () => PublicIdentityRepository.instance = original;
}

/// A MaterialApp with the app's theme, localization and route observer.
Widget overviewHost(
  Widget child, {
  Locale locale = const Locale('en'),
  bool light = false,
  bool rtl = false,
  double textScale = 1,
  Size? size,
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  debugShowCheckedModeBanner: false,
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  navigatorObservers: <NavigatorObserver>[appRouteObserver],
  builder: (context, child) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        size: size ?? media.size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    );
  },
  home: child,
);

void useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The first page resolves inside a few frames; identity badges flush on
/// a one-millisecond timer. Neither is an animation, so pumpAndSettle is
/// not needed and the loading pulse could not be settled anyway.
Future<void> settleOverview(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FakeFirebaseFirestore fakeFirestore() => FakeFirebaseFirestore();

/// The default test font draws every glyph one em wide; every width claim
/// (one-row action rows, three visible capsules) is only meaningful in the
/// typeface the app ships.
Future<void> loadInterFont() async {
  final loader = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
  await loader.load();
}
