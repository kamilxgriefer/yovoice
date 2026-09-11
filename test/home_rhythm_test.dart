import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/recent_chats.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';

import 'voice_moment_test_doubles.dart';

/// THE rhythm regression for Home.
///
/// Everything here is expressed in [AppRhythm] steps, never in literals: a
/// hard-coded gap that happens to equal a step today fails the moment the
/// scale moves, and a gap that is not a step fails immediately. That is the
/// point — the eleven measured values Home used to ship
/// ({2, 4, 10, 14, 16, 20, 21.5, 30.9, 37.5, 40, 132}) all read as
/// deliberate in the source.
///
/// The load-bearing invariant is [HomeSectionHeader]'s: its LAYOUT box is
/// `AppRhythm.section + titleInk + AppRhythm.title`, whatever the title's
/// height turns out to be and whether or not it carries a "View all". Every
/// section gap on Home is that one number.
void main() {
  const uid = 'me-uid';

  /// The six steps, and nothing else, may appear as a vertical gap. Named,
  /// not numeric: a literal that happens to match today would still fail
  /// the day the scale moves.
  final scale = <double>[
    AppRhythm.hairline,
    AppRhythm.tight,
    AppRhythm.item,
    AppRhythm.title,
    AppRhythm.section,
    AppRhythm.page,
  ];

  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

  Future<void> seedRoom(String id, String name, {bool live = true}) =>
      db.collection('rooms').doc(id).set({
        'hostId': 'host-$id',
        'hostName': 'Host',
        'name': name,
        'description': 'Real conversations, real people',
        'category': 'community',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 8,
        'memberCount': 0,
        'isLive': live,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': Timestamp.now(),
      });

  Future<void> seedFriend(String id, String name) async {
    await db.collection('publicProfiles').doc(id).set({
      'uid': id,
      'displayName': name,
      'username': name.toLowerCase(),
    });
    await db.collection('users').doc(id).set({
      'uid': id,
      'displayName': name,
      'username': name.toLowerCase(),
      'isOnline': true,
      'availability': 'available',
    });
    await db.collection('users').doc(uid).collection('friends').doc(id).set({
      'friendId': id,
      'createdAt': Timestamp.now(),
    });
  }

  Future<void> seedFollowedMoment(String id, String name) async {
    await db.collection('publicProfiles').doc(id).set({
      'uid': id,
      'displayName': name,
      'username': name.toLowerCase(),
    });
    await db.collection('users').doc(uid).collection('following').doc(id).set({
      'uid': id,
      'followedAt': Timestamp.now(),
    });
    final createdAt = DateTime.now().subtract(const Duration(minutes: 4));
    await db.collection('voiceMoments').doc('moment-$id').set({
      'authorId': id,
      'authorName': name,
      'mediaGeneration': '1700000000000001',
      'mediaContentType': 'audio/mp4',
      'mediaSize': 4096,
      'durationSeconds': 8,
      'likeCount': 0,
      'commentCount': 0,
      'isPublished': true,
      'schemaVersion': 2,
      'status': 'published',
      'isDeleted': false,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(hours: 24))),
    });
  }

  Future<void> seedConversation(String id, String otherName) =>
      db.collection('conversations').doc(id).set({
        'participantIds': [uid, 'friend-$id'],
        'participantNames': {uid: 'Kamil', 'friend-$id': otherName},
        'participantEmails': {
          uid: 'me@yovoice.app',
          'friend-$id': '$id@yovoice.app',
        },
        'participantPhotoUrls': <String, String>{},
        'unreadCounts': {uid: 0, 'friend-$id': 0},
        'lastMessage': 'See you there',
        'lastMessageType': 'text',
        'lastMessageSenderId': 'friend-$id',
        'updatedAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
        'archivedBy': <String>[],
        'mutedBy': <String>[],
      });

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
      'availability': 'available',
    });
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  Widget app(
    Widget home, {
    required Size size,
    required double textScale,
    required Locale locale,
    EdgeInsets padding = const EdgeInsets.only(top: 47),
  }) => MaterialApp(
    theme: AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: padding,
        viewPadding: padding,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: home),
    ),
  );

  MobileHome mobileHome({ProfileService? profileService}) {
    final firebaseAuth = authFor();
    return MobileHome(
      onOpenRoom: (_) {},
      onOpenDiscover: () {},
      onOpenFriends: () {},
      onOpenNotifications: () {},
      onOpenProfile: () {},
      onCreateMoment: () {},
      onCreateRoom: () {},
      onOpenMoment: (_) {},
      onOpenComments: (_) {},
      onOpenConversation: (_) {},
      onSeeAllChats: () {},
      onSeeAllMoments: () {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService: FollowService(firestore: db, auth: firebaseAuth),
      profileService:
          profileService ?? ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(
        firestore: db,
        auth: firebaseAuth,
        voiceMomentReadService: VoiceMomentReadService(
          feedInvoker: fakeVoiceMomentFeedInvoker(firestore: db),
        ),
      ),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      capabilityService: _NoCapabilities(),
      currentUserId: uid,
    );
  }

  DesktopHome desktopHome() {
    final firebaseAuth = authFor();
    return DesktopHome(
      currentUserId: uid,
      onOpenRoom: (_) {},
      onSeeAllRooms: () {},
      onViewAllFriends: () {},
      onStartRoom: () {},
      onOpenMoment: (_) {},
      onCreateMoment: () {},
      onSeeAllMoments: () {},
      onOpenConversation: (_) {},
      onOpenClub: (_) {},
      onSeeAllChats: () {},
      onOpenClubs: () {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService: FollowService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(
        firestore: db,
        auth: firebaseAuth,
        voiceMomentReadService: VoiceMomentReadService(
          feedInvoker: fakeVoiceMomentFeedInvoker(firestore: db),
        ),
      ),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      clubService: ClubService(
        firestore: db,
        auth: firebaseAuth,
        storage: MockFirebaseStorage(),
      ),
      clubChatService: ClubChatService(firestore: db, auth: firebaseAuth),
      capabilityService: _NoCapabilities(),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  // ------------------------------------------------------- the component

  group('HomeSectionHeader owns the rhythm', () {
    for (final headerScale in HomeSectionHeaderScale.values) {
      for (final width in const [320.0, 390.0, 430.0, 768.0, 1440.0]) {
        for (final textScale in const [1.0, 2.0]) {
          for (final locale in const [Locale('en'), Locale('pl')]) {
            testWidgets('${headerScale.name} ${width.toInt()} x$textScale '
                '${locale.languageCode}: the box is section + title ink + '
                'title, with and without View all', (tester) async {
              tester.view.physicalSize = Size(width, 1400);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);

              for (final withAction in const [true, false]) {
                await tester.pumpWidget(
                  app(
                    Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: HomeSectionHeader(
                          // The longest heading Home ships, in both
                          // locales — the one that actually wraps at 320.
                          title: locale.languageCode == 'pl'
                              ? 'Od osób, które obserwujesz'
                              : 'From people you follow',
                          scale: headerScale,
                          onSeeAll: withAction ? () {} : null,
                        ),
                      ),
                    ),
                    size: Size(width, 1400),
                    textScale: textScale,
                    locale: locale,
                    padding: EdgeInsets.zero,
                  ),
                );
                await tester.pump();

                final element = find
                    .byType(HomeSectionHeader)
                    .evaluate()
                    .single;
                final render = element.renderObject! as RenderBox;
                final box = render.localToGlobal(Offset.zero) & render.size;
                final ink = _inkBounds(element)!;
                final title = tester.getRect(
                  find.descendant(
                    of: find.byType(HomeSectionHeader),
                    matching: find.byType(Text).first,
                  ),
                );
                // The title's ink is always exactly one section step down
                // from the layout box — that IS the mechanism.
                expect(
                  title.top - box.top,
                  closeTo(AppRhythm.section, 0.5),
                  reason: 'gap above the title (View all: $withAction)',
                );
                expect(
                  ink.top - box.top,
                  closeTo(AppRhythm.section, 0.5),
                  reason: 'heading ink starts at the section step',
                );
                // And the heading's own ink ends exactly one title step
                // above it, whether the action rides the title's line or
                // (at enlarged text) sits under it and owns the ink
                // bottom itself.
                expect(
                  box.bottom - ink.bottom,
                  closeTo(AppRhythm.title, 0.5),
                  reason: 'gap below the heading (View all: $withAction)',
                );
                if (withAction) {
                  final button = tester.getSize(find.byType(TextButton));
                  expect(
                    button.height,
                    greaterThanOrEqualTo(AppSizing.minimumTouchTarget),
                  );
                  expect(
                    button.width,
                    greaterThanOrEqualTo(AppSizing.minimumTouchTarget),
                  );
                }
                expect(tester.takeException(), isNull);
              }
            });
          }
        }
      }
    }

    // The action shares the title's line unless it would cost more than a
    // third of the row. That is a question about WIDTH, not about the
    // reader's text preference: a phone at 200 % stacks (it always has),
    // and a slate or a desktop at the same scale keeps the action on its
    // heading's line instead of pushing it a full row away from the words
    // it belongs to. It answers the same for every heading on a page,
    // because they all carry the same "View all" — a page never mixes the
    // two arrangements.
    for (final (label, width, scale, expectStacked) in const [
      ('a 320 phone at 200 %', 320.0, 2.0, true),
      ('a 390 phone at 200 %', 390.0, 2.0, true),
      ('a 430 phone at 200 %', 430.0, 2.0, true),
      ('a 768 slate at 200 %', 768.0, 2.0, false),
      ('a 1440 desktop at 200 %', 1440.0, 2.0, false),
      ('a 320 phone at 100 %', 320.0, 1.0, false),
      ('a 1440 desktop at 100 %', 1440.0, 1.0, false),
    ]) {
      testWidgets('$label ${expectStacked ? 'stacks' : 'keeps'} View all '
          '${expectStacked ? 'under' : 'on'} the title', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          app(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: HomeSectionHeader(
                  title: 'From people you follow',
                  scale: width >= 1100
                      ? HomeSectionHeaderScale.expanded
                      : HomeSectionHeaderScale.compact,
                  onSeeAll: () {},
                ),
              ),
            ),
            size: Size(width, 800),
            textScale: scale,
            locale: const Locale('en'),
            padding: EdgeInsets.zero,
          ),
        );
        await tester.pump();
        final title = tester.getRect(
          find
              .descendant(
                of: find.byType(HomeSectionHeader),
                matching: find.byType(Text),
              )
              .first,
        );
        final button = tester.getRect(find.byType(TextButton));
        // Stacked means the action's box begins below the title's ink;
        // beside means the two share a horizontal band.
        expect(
          button.top >= title.bottom - 0.5,
          expectStacked,
          reason: 'title $title, action $button at ${width.toInt()} x$scale',
        );
        // Either way the rhythm is the same two numbers.
        final header = find.byType(HomeSectionHeader).evaluate().single;
        final box =
            (header.renderObject! as RenderBox).localToGlobal(Offset.zero) &
            (header.renderObject! as RenderBox).size;
        final ink = _inkBounds(header)!;
        expect(ink.top - box.top, closeTo(AppRhythm.section, 0.5));
        expect(box.bottom - ink.bottom, closeTo(AppRhythm.title, 0.5));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the box height does not change when View all appears', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final heights = <double>[];
      for (final withAction in const [true, false]) {
        await tester.pumpWidget(
          app(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 390,
                child: HomeSectionHeader(
                  title: 'Your people',
                  onSeeAll: withAction ? () {} : null,
                ),
              ),
            ),
            size: const Size(390, 800),
            textScale: 1,
            locale: const Locale('en'),
            padding: EdgeInsets.zero,
          ),
        );
        await tester.pump();
        heights.add(tester.getSize(find.byType(HomeSectionHeader)).height);
      }
      // The defect this replaces: the same widget was 76 px tall with the
      // button and 53 px without, so half of Home's sections sat on a
      // different rhythm from the other half.
      expect(heights.first, closeTo(heights.last, 0.01));
    });
  });

  // ----------------------------------------------------- the composition

  for (final width in const [320.0, 390.0, 430.0, 768.0]) {
    for (final textScale in const [1.0, 2.0]) {
      for (final locale in const [Locale('en'), Locale('pl')]) {
        for (final populated in const [false, true]) {
          testWidgets('mobile Home ${width.toInt()} x$textScale '
              '${locale.languageCode} ${populated ? 'populated' : 'empty'}: '
              'every vertical gap is a named step', (tester) async {
            final size = Size(width, 2600);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            if (populated) {
              await seedRoom('r1', 'Evening Talks');
              await seedRoom('r2', 'Night Shift');
              await seedFriend('friend-a', 'Ada');
              await seedFriend('friend-b', 'Marek');
              await seedFollowedMoment('creator-a', 'Ola');
              await seedConversation('c1', 'Ada');
            }
            await tester.pumpWidget(
              app(
                mobileHome(),
                size: size,
                textScale: textScale,
                locale: locale,
              ),
            );
            await settle(tester);

            final children = _sliverChildren(tester);
            expect(children, isNotEmpty);
            // The whole table, so a failure names the boundary instead of
            // leaving the next reader to re-derive it.
            for (final child in children) {
              final ink = child.ink;
              final rect =
                  child.render.localToGlobal(Offset.zero) & child.render.size;
              printOnFailure(
                '${child.label} | layout $rect | ink $ink | '
                'rail ${child.isRail} | heading ${child.startsWithHeading}',
              );
            }

            // A1 / A2: only the named steps, and every gap that follows a
            // heading is the title step while every gap that precedes one
            // is the section step.
            double? previousBottom;
            var previousLabel = '';
            var sawSection = false;
            var sawTitle = false;
            for (final child in children) {
              final ink = child.ink;
              if (ink == null) continue;
              final rect =
                  child.render.localToGlobal(Offset.zero) & child.render.size;
              // The principle this whole change rests on: a page child's
              // layout box IS its ink box, so nothing invisible can be
              // hiding above it. Only a section heading is allowed air,
              // and exactly the declared amount.
              expect(
                ink.top - rect.top,
                closeTo(child.startsWithHeading ? AppRhythm.section : 0, 0.5),
                reason: '${child.label} carries invisible air above its ink',
              );
              expect(
                ink.bottom,
                lessThanOrEqualTo(rect.bottom + 0.5),
                reason: '${child.label} paints below its own box',
              );
              if (previousBottom != null) {
                final gap = ink.top - previousBottom;
                expect(
                  scale.any((step) => (gap - step).abs() <= 0.5),
                  isTrue,
                  reason:
                      'gap ${gap.toStringAsFixed(2)} between $previousLabel '
                      'and ${child.label} ($ink) is not one of $scale',
                );
                if (child.startsWithHeading) {
                  expect(
                    gap,
                    closeTo(AppRhythm.section, 0.5),
                    reason: 'content -> ${child.label} heading',
                  );
                  sawSection = true;
                }
              }
              // A heading's own ink bottom is the perceived bottom (its
              // trailing button reaches into the declared gap on purpose).
              // Every other child's box is what the reader sees: a rail's
              // tiles reserve a fixed, scale-proof name slot inside it,
              // which is worth at most two invisible pixels and must not
              // be mistaken for a spacing decision.
              previousBottom = child.endsWithHeading ? ink.bottom : rect.bottom;
              previousLabel = child.label;
            }
            expect(sawSection, isTrue, reason: 'no section boundary seen');

            // A2, the other half: every heading on the page is followed
            // by its content exactly AppRhythm.title below its ink.
            for (final header in find.byType(HomeSectionHeader).evaluate()) {
              final box = header.renderObject! as RenderBox;
              final ink = _inkBounds(header)!;
              final rect = box.localToGlobal(Offset.zero) & box.size;
              expect(
                rect.bottom - ink.bottom,
                closeTo(AppRhythm.title, 0.5),
                reason: 'heading ink -> its own content',
              );
              expect(
                ink.top - rect.top,
                closeTo(AppRhythm.section, 0.5),
                reason: 'previous content -> heading ink',
              );
              sawTitle = true;
            }
            expect(sawTitle, isTrue);

            // A4: nothing paints outside the page margin except the
            // rails, which clip at the frame and scroll under its edge.
            final margin = _marginFor(width);
            for (final child in children) {
              if (child.isRail) continue;
              final ink = child.ink;
              if (ink == null) continue;
              expect(
                ink.left,
                greaterThanOrEqualTo(margin - 0.5),
                reason: '${child.label} paints left of the margin',
              );
              expect(
                ink.right,
                lessThanOrEqualTo(width - margin + 0.5),
                reason: '${child.label} paints right of the margin',
              );
            }

            // The page's own top band and end-of-scroll step.
            final list = tester.widget<ListView>(find.byType(ListView).first);
            final padding = list.padding! as EdgeInsets;
            expect(padding.top, 47 + AppRhythm.title);
            expect(padding.bottom, AppRhythm.page);
            expect(padding.left, 0);
            expect(padding.right, 0);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

  // ----------------------------------------------------------- the header

  testWidgets('the header control row is one centre line, and its height '
      'does not jump when the profile lands', (tester) async {
    const size = Size(390, 1400);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Cold start: the profile has not arrived, so there is no chip yet.
    await tester.pumpWidget(
      app(
        mobileHome(
          profileService: _PendingProfile(firestore: db, auth: authFor()),
        ),
        size: size,
        textScale: 1,
        locale: const Locale('en'),
      ),
    );
    await settle(tester);
    expect(find.byType(AvailabilityChip), findsNothing);
    final coldTop = tester.getTopLeft(find.byType(HomePeopleStrip)).dy;

    // A fresh tree, so MobileHome resolves its real profile stream rather
    // than keeping the pending one from the first mount.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      app(mobileHome(), size: size, textScale: 1, locale: const Locale('en')),
    );
    await settle(tester);
    expect(find.byType(AvailabilityChip), findsOneWidget);
    // A6: the discs set the control row's height, so the header is exactly
    // as tall before the chip arrives as after it. It used to grow ~50 px
    // the moment `watchCurrentProfile` emitted, jolting the whole page.
    expect(tester.getTopLeft(find.byType(HomePeopleStrip)).dy, coldTop);

    // A5: one centre line, three real targets.
    final chip = tester.getRect(find.byType(AvailabilityChip));
    final bell = tester.getRect(find.byTooltip('Notifications'));
    final avatar = tester.getRect(find.byTooltip('Profile'));
    expect(chip.center.dy, closeTo(bell.center.dy, 0.5));
    expect(bell.center.dy, closeTo(avatar.center.dy, 0.5));
    for (final target in [chip, bell, avatar]) {
      expect(target.height, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
      expect(target.width, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
    }
    // Reading order: greeting, name, availability, notifications, profile.
    expect(tester.getTopLeft(find.text('Kamil')).dy, lessThan(chip.top));
    expect(chip.left, lessThan(bell.left));
    expect(bell.left, lessThan(avatar.left));
  });

  testWidgets('with no followed Moments there is no heading and exactly one '
      'record control', (tester) async {
    const size = Size(390, 1400);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(mobileHome(), size: size, textScale: 1, locale: const Locale('en')),
    );
    await settle(tester);

    // A8.
    expect(find.text('From people you follow'), findsNothing);
    final record = find.byKey(const ValueKey('home-record-moment'));
    expect(record, findsOneWidget);
    final size1 = tester.getSize(record);
    expect(size1.height, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
    expect(size1.width, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
    expect(find.byType(MobileMomentsStrip), findsOneWidget);
    // It sits with the other real routes, not under a heading of its own.
    expect(
      tester.getTopLeft(record).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('home-quick-friends'))).dy,
      ),
    );
  });

  // ---------------------------------------------------------- the desktop

  testWidgets('desktop Home reports the same steps at the expanded scale', (
    tester,
  ) async {
    const size = Size(1440, 2600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seedRoom('r1', 'Evening Talks');
    await seedFriend('friend-a', 'Ada');
    await seedConversation('c1', 'Ada');
    await tester.pumpWidget(
      app(
        desktopHome(),
        size: size,
        textScale: 1,
        locale: const Locale('en'),
        padding: EdgeInsets.zero,
      ),
    );
    await settle(tester);

    final headers = find.byType(HomeSectionHeader).evaluate().toList();
    expect(headers, isNotEmpty);
    for (final header in headers) {
      final widget = header.widget as HomeSectionHeader;
      expect(
        widget.scale,
        HomeSectionHeaderScale.expanded,
        reason: 'desktop headings use the expanded ramp',
      );
      final box = header.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final ink = _inkBounds(header)!;
      expect(ink.top - rect.top, closeTo(AppRhythm.section, 0.5));
      expect(rect.bottom - ink.bottom, closeTo(AppRhythm.title, 0.5));
    }

    final list = tester.widget<ListView>(find.byType(ListView).first);
    final padding = list.padding! as EdgeInsets;
    expect(padding.left, AppSpacing.xl);
    expect(padding.right, AppSpacing.xl);
    expect(padding.top, AppRhythm.title);
    expect(padding.bottom, AppRhythm.page);
    expect(tester.takeException(), isNull);
  });
}

/// A profile stream that never emits — the cold-start frame.
class _PendingProfile extends ProfileService {
  _PendingProfile({required super.firestore, required super.auth});

  @override
  Stream<UserProfile> watchCurrentProfile() =>
      const Stream<UserProfile>.empty();
}

class _NoCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

double _marginFor(double width) {
  final gutter = width >= 600 ? AppRhythm.section : AppRhythm.title;
  final frame = width <= 880 ? 0.0 : (width - 880) / 2;
  return gutter + frame;
}

class _Child {
  _Child({
    required this.render,
    required this.ink,
    required this.label,
    required this.isRail,
    required this.startsWithHeading,
    required this.endsWithHeading,
  });

  final RenderBox render;

  /// What this child actually paints, as opposed to the box it occupies.
  final Rect? ink;
  final String label;

  /// The horizontal scrollers. They deliberately paint a peek of the next
  /// tile past the page margin (the people and Moments rails clip at the
  /// frame; the chat and owned-room rails keep their established
  /// `Clip.none` peek), so the margin assertion skips them.
  final bool isRail;

  /// This child opens with a section heading, so the gap above it is the
  /// section step rather than the item step.
  final bool startsWithHeading;

  /// This child IS a bare section heading, so the gap under it is measured
  /// from its ink rather than from its box.
  final bool endsWithHeading;
}

final _railTypes = <Type>[
  HomePeopleStrip,
  MobileMomentsStrip,
  RecentChats,
  HomeActiveRooms,
];

List<_Child> _sliverChildren(WidgetTester tester) {
  final sliver = tester.renderObject<RenderSliverList>(find.byType(SliverList));
  final children = <_Child>[];
  RenderBox? child = sliver.firstChild;
  while (child != null) {
    final element = _elementFor(tester, child);
    children.add(
      _Child(
        render: child,
        ink: element == null ? null : _inkBounds(element),
        label: element == null ? '?' : _describe(element),
        isRail: element != null && _subtreeHasAny(element, _railTypes),
        startsWithHeading: element != null && _opensWithHeading(element, child),
        endsWithHeading:
            element != null && _subtreeHasAny(element, [HomeSectionHeader]),
      ),
    );
    child = sliver.childAfter(child);
  }
  return children;
}

String _describe(Element root) {
  final names = <String>[];
  void visit(Element element) {
    if (names.length >= 3) return;
    final name = element.widget.runtimeType.toString();
    if (!name.startsWith('_Selection') &&
        !name.startsWith('NotificationListener') &&
        !const {
          'KeyedSubtree',
          'RepaintBoundary',
          'IndexedSemantics',
          'AutomaticKeepAlive',
          'KeepAlive',
          'Padding',
          'Builder',
          'MediaQuery',
        }.contains(name)) {
      names.add(name);
    }
    element.visitChildren(visit);
  }

  visit(root);
  return names.join(' > ');
}

bool _subtreeHasAny(Element root, List<Type> types) {
  var hit = false;
  void visit(Element element) {
    if (hit) return;
    if (types.contains(element.widget.runtimeType)) {
      hit = true;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return hit;
}

/// True when the first thing this child paints is a section heading — the
/// heading's own ink then owns the gap above the child.
bool _opensWithHeading(Element root, RenderBox child) {
  RenderBox? header;
  void visit(Element element) {
    if (header != null) return;
    if (element.widget is HomeSectionHeader) {
      header = element.renderObject as RenderBox?;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  final found = header;
  if (found == null || !found.hasSize) return false;
  return (found.localToGlobal(Offset.zero).dy -
              child.localToGlobal(Offset.zero).dy)
          .abs() <
      0.5;
}

Element? _elementFor(WidgetTester tester, RenderObject target) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.renderObject == target) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  return found;
}

bool _decorationPaints(Decoration? decoration) {
  if (decoration == null) return false;
  if (decoration is BoxDecoration) {
    final color = decoration.color;
    if (color != null && color.a > 0) return true;
    if (decoration.gradient != null) return true;
    if (decoration.image != null) return true;
    if (decoration.boxShadow?.isNotEmpty ?? false) return true;
    final border = decoration.border;
    if (border is Border) {
      for (final side in [
        border.top,
        border.bottom,
        border.left,
        border.right,
      ]) {
        if (side.style != BorderStyle.none && side.color.a > 0) return true;
      }
    }
    return false;
  }
  if (decoration is ShapeDecoration) {
    final color = decoration.color;
    return (color != null && color.a > 0) || decoration.gradient != null;
  }
  return true;
}

bool _paintsInk(RenderBox box) {
  if (box is RenderParagraph) {
    return box.text
        .toPlainText(includeSemanticsLabels: false)
        .trim()
        .isNotEmpty;
  }
  if (box is RenderImage) return box.image != null;
  if (box is RenderDecoratedBox) return _decorationPaints(box.decoration);
  if (box is RenderPhysicalShape) return box.color.a > 0;
  if (box is RenderPhysicalModel) return box.color.a > 0;
  return false;
}

/// A Material paints when it has a fill or a visible outline. Its outline is
/// drawn by a private CustomPaint over the whole control, which no render
/// object exposes — an OutlinedButton's visible box would otherwise measure
/// as nothing but its label.
bool _materialPaints(Material material) {
  final color = material.color;
  if (color != null && color.a > 0) return true;
  final shape = material.shape;
  if (shape is OutlinedBorder) {
    final side = shape.side;
    return side.style != BorderStyle.none && side.color.a > 0 && side.width > 0;
  }
  return false;
}

/// The bounding box of everything that actually paints inside [root] — the
/// visual box a reader perceives, as opposed to the layout box that carries
/// the widget's own padding.
Rect? _inkBounds(Element root) {
  Rect? accumulated;
  void add(RenderObject? object, Rect? clip) {
    if (object is! RenderBox || !object.attached || !object.hasSize) return;
    final size = object.size;
    if (size.width <= 0 || size.height <= 0) return;
    if (!size.width.isFinite || !size.height.isFinite) return;
    final origin = object.localToGlobal(Offset.zero);
    if (!origin.dx.isFinite || !origin.dy.isFinite) return;
    var rect = origin & size;
    if (clip != null) {
      if (!rect.overlaps(clip)) return;
      rect = rect.intersect(clip);
    }
    accumulated = accumulated == null
        ? rect
        : accumulated!.expandToInclude(rect);
  }

  // Clip-aware: a rail's tag chips or story tiles deliberately lay out
  // past their box and are clipped, and clipped pixels are not ink.
  void visit(Element element, Rect? clip) {
    final object = element.renderObject;
    var inherited = clip;
    if (object is RenderBox && object.attached && object.hasSize) {
      if (object is RenderClipRect ||
          object is RenderClipRRect ||
          object is RenderClipPath ||
          object is RenderClipOval) {
        final origin = object.localToGlobal(Offset.zero);
        if (origin.dx.isFinite && origin.dy.isFinite) {
          final box = origin & object.size;
          inherited = clip == null ? box : clip.intersect(box);
        }
      }
    }
    final widget = element.widget;
    if (widget is Material && _materialPaints(widget)) {
      add(element.renderObject, inherited);
    }
    if (object is RenderBox && _paintsInk(object)) add(object, inherited);
    element.visitChildren((child) => visit(child, inherited));
  }

  visit(root, null);
  return accumulated;
}
