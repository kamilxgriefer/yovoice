import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_card.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';

VoiceMoment _moment(String id) {
  final createdAt = DateTime.now().subtract(const Duration(hours: 1));
  return VoiceMoment(
    id: id,
    authorId: 'author',
    authorName: 'Nadia Rutkowska',
    authorPhotoUrl: null,
    caption: 'A clear voice note for the main Moments feed.',
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 28,
    likeCount: 4,
    commentCount: 2,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
  );
}

class _StaticDiscovery implements MomentDiscoveryService {
  const _StaticDiscovery(this.moments);

  final List<VoiceMoment> moments;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 1,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ThemeData _theme(Brightness brightness) =>
    brightness == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme;

AppPalette _palette(Brightness brightness) =>
    brightness == Brightness.light ? AppPalette.light : AppPalette.dark;

Widget _host({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: _theme(brightness),
    builder: (context, built) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: built!,
    ),
    home: child,
  );
}

void _useNarrowRetinaView(WidgetTester tester) {
  tester.view.physicalSize = const Size(640, 1280);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  for (final brightness in Brightness.values) {
    final label = brightness.name;

    testWidgets('MomentCard uses semantic $label surfaces at 320px/200%', (
      tester,
    ) async {
      _useNarrowRetinaView(tester);
      final moment = _moment('card-$label');

      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: Scaffold(
            body: SingleChildScrollView(
              child: MomentCard(moment: moment, onComments: () {}),
            ),
          ),
        ),
      );
      await tester.pump();

      final card = tester.widget<Container>(
        find.byKey(ValueKey('moment-card-${moment.id}')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, _palette(brightness).surface);
      final author = tester.widget<Text>(find.text(moment.authorName));
      expect(author.style?.color, _palette(brightness).textPrimary);
      expect(tester.takeException(), isNull);
    });

    testWidgets('main feed uses semantic $label canvas at 320px/200%', (
      tester,
    ) async {
      _useNarrowRetinaView(tester);
      final moment = _moment('feed-$label');

      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: Scaffold(
            body: MomentsFeedView(
              onRecord: () {},
              discoveryService: _StaticDiscovery([moment]),
            ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final feed = tester.widget<Container>(
        find.byKey(const ValueKey('moments-feed-view')),
      );
      expect(feed.color, _palette(brightness).background);
      expect(
        find.byKey(ValueKey('moment-featured-${moment.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail and comments use semantic $label canvases', (
      tester,
    ) async {
      _useNarrowRetinaView(tester);
      final moment = _moment('detail-$label');

      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: MomentDetailScreen(moment: moment),
        ),
      );
      await tester.pump();

      final detail = tester.widget<Scaffold>(
        find.byKey(const ValueKey('moment-detail-screen')),
      );
      expect(detail.backgroundColor, _palette(brightness).background);
      expect(tester.takeException(), isNull);

      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          child: MomentCommentsScreen(
            moment: moment,
            firestore: firestore,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: 'viewer'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final comments = tester.widget<Scaffold>(
        find.byKey(const ValueKey('moment-comments-screen')),
      );
      expect(comments.backgroundColor, _palette(brightness).background);
      expect(find.text('Be the first to comment.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
