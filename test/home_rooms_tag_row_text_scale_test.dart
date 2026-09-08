import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

/// The category/language chips on a `Rooms for you` banner, at the largest
/// text size a reader can ask for.
///
/// `_TagRow` clips deliberately — a chip that runs past the right edge is
/// how the banner says "there is more" without spending a second row on it.
/// The clip box was a flat `SizedBox(height: 26)` though, so the same
/// rectangle that trimmed the row horizontally also sliced every pill
/// through the middle of its letters once the labels grew: at 200 % text
/// only a sliver of `talk` and `English` painted, on phone and on desktop
/// alike.
///
/// These tests measure the label rather than eyeballing it: a chip's
/// paragraph must be laid out at the height that text actually needs, and
/// must sit inside the clip it is drawn into. The horizontal affordance is
/// asserted too, so a future fix cannot "solve" the clipping by wrapping the
/// row.
void main() {
  const longFacet = 'International philosophy and debate';
  const room = VoiceRoom(
    id: 'room-tags',
    hostId: 'host',
    hostName: 'Host',
    hostPhotoUrl: null,
    name: 'Design review',
    description: 'A focused conversation.',
    category: 'talk',
    visibility: 'public',
    language: 'English',
    maxParticipants: null,
    participantCount: 3,
    memberCount: 3,
    isLive: true,
    roomType: RoomType.community,
    status: RoomStatus.active,
    imageUrl: null,
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: false,
    membersCanStartVoice: true,
    createdAt: null,
    updatedAt: null,
  );
  const wordyRoom = VoiceRoom(
    id: 'room-tags-long',
    hostId: 'host',
    hostName: 'Host',
    hostPhotoUrl: null,
    name: 'Design review',
    description: 'A focused conversation.',
    category: longFacet,
    visibility: 'public',
    language: 'English',
    maxParticipants: null,
    participantCount: 3,
    memberCount: 3,
    isLive: true,
    roomType: RoomType.community,
    status: RoomStatus.active,
    imageUrl: null,
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: false,
    membersCanStartVoice: true,
    createdAt: null,
    updatedAt: null,
  );

  Future<void> pumpBanner(
    WidgetTester tester, {
    required Size size,
    required bool compact,
    required TextScaler textScaler,
    VoiceRoom banner = room,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              HomeRoomBanner(room: banner, compact: compact, onJoin: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The clip rectangle `_TagRow` draws its chips into.
  Finder tagClip(Finder label) =>
      find.ancestor(of: label, matching: find.byType(ClipRect)).first;

  void expectLabelFullyPainted(WidgetTester tester, String label) {
    final text = find.text(label);
    expect(text, findsOneWidget, reason: 'chip "$label" should be rendered');

    // What the paragraph got, versus what this text needs for its one line.
    // The old fixed 26 px box left roughly 14 px for a ~23 px line, so the
    // glyphs painted outside their own layout box and the ClipRect ate the
    // rest.
    final paragraph = tester.renderObject<RenderBox>(text);
    final needed = paragraph.getMaxIntrinsicHeight(double.infinity);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(needed - 0.01),
      reason:
          'chip "$label" is laid out ${paragraph.size.height} px tall but its '
          'label needs $needed px — the label is being cut off',
    );

    // And the line, at that height, has to be inside the clip.
    final clipRect = tester.getRect(tagClip(text));
    final textRect = tester.getRect(text);
    expect(
      textRect.top,
      greaterThanOrEqualTo(clipRect.top - 0.01),
      reason: 'chip "$label" is clipped at the top',
    );
    expect(
      textRect.bottom,
      lessThanOrEqualTo(clipRect.bottom + 0.01),
      reason: 'chip "$label" is clipped at the bottom',
    );
  }

  for (final viewport in <({String name, Size size, bool compact})>[
    (name: 'phone 390', size: Size(390, 844), compact: true),
    (name: 'desktop 1440', size: Size(1440, 900), compact: false),
  ]) {
    testWidgets('${viewport.name}: room chips are whole at 200 % text', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        size: viewport.size,
        compact: viewport.compact,
        textScaler: const TextScaler.linear(2),
      );

      expectLabelFullyPainted(tester, 'talk');
      expectLabelFullyPainted(tester, 'English');

      // The whole pill, border included, and not just the letters.
      for (final label in <String>['talk', 'English']) {
        final clipRect = tester.getRect(tagClip(find.text(label)));
        final pill = tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        expect(pill.top, greaterThanOrEqualTo(clipRect.top - 0.01));
        expect(pill.bottom, lessThanOrEqualTo(clipRect.bottom + 0.01));
      }

      // The clip grew with the text rather than staying at 26.
      expect(tester.getSize(tagClip(find.text('talk'))).height, 52);

      expect(tester.takeException(), isNull);
    });

    testWidgets('${viewport.name}: default text size is unchanged', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        size: viewport.size,
        compact: viewport.compact,
        textScaler: TextScaler.noScaling,
      );

      // The scaled box must reproduce the original constant exactly at
      // scale 1 — this fix is not allowed to move the default layout, which
      // the shipped typeface (Inter, ~14 px per line at 11.5 px) fits. It is
      // deliberately NOT asserted that the label fits under the test font:
      // `flutter test` substitutes a taller fallback face, so that check
      // would be measuring the harness rather than the app.
      expect(tester.getSize(tagClip(find.text('talk'))).height, 26);
      expect(find.text('talk'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  }

  for (final scaler in <TextScaler>[
    TextScaler.noScaling,
    TextScaler.linear(2),
  ]) {
    testWidgets('long facets still run past the right edge at '
        '${scaler.scale(100).round()} % text', (tester) async {
      await pumpBanner(
        tester,
        size: const Size(390, 844),
        compact: true,
        textScaler: scaler,
        banner: wordyRoom,
      );

      // Deliberate: the row is one line, and the overflow is the signal
      // that a room carries more facets than the banner can show.
      final clipRect = tester.getRect(tagClip(find.text(longFacet)));
      expect(
        tester.getRect(find.text('English')).right,
        greaterThan(clipRect.right),
        reason: 'the horizontal "there is more" clip must be preserved',
      );

      expect(tester.takeException(), isNull);
    });
  }
}
