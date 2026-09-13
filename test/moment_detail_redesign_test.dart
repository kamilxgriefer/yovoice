// Board 07, the expanded Voice Moment: what the page is made of, and how
// it re-lays itself out by the slot it is given — never by a device label.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_progress_ring.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_transport_controls.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'moment_listen_test_support.dart';

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: listenViewerUid),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  testWidgets('the page is titled as ONE Moment and carries no format '
      'switch', (tester) async {
    await pumpListenDetail(tester, moment: listenMoment('m1'));

    expect(find.byKey(const ValueKey('moment-detail-back')), findsOneWidget);
    expect(find.text('Voice Moment'), findsWidgets);
    // A pushed detail cannot switch the destination's format.
    expect(find.text('Reels'), findsNothing);
    expect(find.text('Voice'), findsNothing);
    // And no search field exists anywhere in Moments.
    expect(find.textContaining('Search'), findsNothing);
    expect(find.textContaining('Szukaj'), findsNothing);
  });

  testWidgets('the hero is ring + eyebrow + caption + author, with no cover '
      'placeholder', (tester) async {
    await pumpListenDetail(tester, moment: listenMoment('m1'));

    expect(find.byType(MomentListeningProgress), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-detail-eyebrow')), findsOneWidget);
    expect(find.text('VOICE MOMENT'), findsOneWidget);
    expect(find.text('Before the city wakes up'), findsOneWidget);
    expect(find.text('Nadia Rutkowska'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('cover'), findsNothing);
  });

  testWidgets('an empty caption falls back to the format name, never to an '
      'invented title', (tester) async {
    await pumpListenDetail(tester, moment: listenMoment('m1', caption: ''));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('moment-detail-caption')))
          .data,
      'Voice Moment',
    );
  });

  testWidgets('below 600 the hero stacks and the reply CTA takes the width '
      'at 58', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(390, 844),
    );

    final ring = tester.getRect(find.byType(MomentProgressRing));
    final caption = tester.getRect(
      find.byKey(const ValueKey('moment-detail-caption')),
    );
    expect(
      caption.top,
      greaterThan(ring.bottom),
      reason: 'the phone hero is a column: ring, then the text',
    );
    expect(
      tester.getSize(find.byType(MomentProgressRing)).width,
      MomentProgressRing.compactAvatar + 20,
    );

    final cta = tester.getSize(
      find.byKey(const ValueKey('moment-detail-reply-voice')),
    );
    expect(cta.height, AppSizing.primaryControlHeight);
    expect(cta.width, greaterThan(300));

    final transport = tester.widget<MomentTransportControls>(
      find.byType(MomentTransportControls),
    );
    expect(transport.compact, isTrue);
    expect(transport.discSize, AppSizing.audioControlCompact);
  });

  testWidgets('from 600 up the hero is side by side and the CTA sits inline '
      'at 48', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(900, 900),
    );

    final ring = tester.getRect(find.byType(MomentProgressRing));
    final caption = tester.getRect(
      find.byKey(const ValueKey('moment-detail-caption')),
    );
    expect(caption.left, greaterThan(ring.right - 1));
    expect(
      tester.getSize(find.byType(MomentProgressRing)).width,
      MomentProgressRing.expandedAvatar + 20,
    );

    final cta = tester.getSize(
      find.byKey(const ValueKey('moment-detail-reply-voice')),
    );
    expect(cta.height, AppSizing.standardControlHeight);

    final transport = tester.widget<MomentTransportControls>(
      find.byType(MomentTransportControls),
    );
    expect(transport.compact, isFalse);
    expect(transport.discSize, AppSizing.audioControl);
  });

  testWidgets('a short landscape slot keeps the transport above the fold by '
      'taking the side-by-side hero', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(740, 380),
    );

    final ring = tester.getRect(find.byType(MomentProgressRing));
    final caption = tester.getRect(
      find.byKey(const ValueKey('moment-detail-caption')),
    );
    expect(caption.left, greaterThan(ring.right - 1));
  });

  testWidgets('the thread is inline below 1100 and a docked panel above it', (
    tester,
  ) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(900, 900),
    );
    expect(
      find.byKey(const ValueKey('moment-detail-thread-scroll')),
      findsNothing,
    );
    expect(find.byType(MomentConversationThread), findsOneWidget);

    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(1150, 900),
    );
    expect(
      find.byKey(const ValueKey('moment-detail-thread-scroll')),
      findsOneWidget,
    );
    // Exactly one composer, wherever it is docked.
    expect(
      find.byKey(const ValueKey('moment-detail-comment-field')),
      findsOneWidget,
    );
    // No hand-off list yet at wide-2.
    expect(find.byType(MomentsQueueList), findsNothing);
  });

  testWidgets('Pearl renders the same page through the light palette', (
    tester,
  ) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      theme: AppTheme.lightTheme,
      size: const Size(900, 900),
    );

    expect(find.byType(MomentListeningProgress), findsOneWidget);
    expect(find.byKey(const ValueKey('moment-detail-play')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 200 % text nothing is clipped and the CTA keeps its own '
      'height', (tester) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1'),
      size: const Size(390, 844),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('moment-detail-reply-voice')))
          .height,
      greaterThanOrEqualTo(AppSizing.primaryControlHeight),
    );
  });

  testWidgets('every engagement control the page had is still here', (
    tester,
  ) async {
    await pumpListenDetail(
      tester,
      moment: listenMoment('m1', likes: 3, comments: 1),
    );

    expect(find.byKey(const ValueKey('moment-detail-like')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('moment-detail-comments')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('moment-detail-share')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('moment-detail-report-m1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('moment-detail-share-top')),
      findsOneWidget,
    );
  });
}
