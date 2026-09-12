import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

/// `VoiceRoom.category` is a stored slug — `talk`, `gaming`, `chill` — and
/// `voice_room.dart` even defaults a room with no category to the literal
/// `'talk'`. Discover has owned the display name for every slug for a long
/// time; Home did not use it, so a real room on a real device showed a
/// lowercase `talk` in the eyebrow of its biggest card. These tests pin the
/// eyebrow to the display name, in both languages, and pin the fallback so an
/// unknown slug still shows something rather than nothing.
VoiceRoom _room({required String category, String name = 'Wieczorne granie'}) =>
    VoiceRoom(
      id: 'r1',
      hostId: 'h1',
      hostName: 'Host',
      hostPhotoUrl: null,
      name: name,
      description: '',
      category: category,
      visibility: 'public',
      language: 'Polish',
      maxParticipants: null,
      participantCount: 3,
      memberCount: 0,
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
      experience: 'community',
    );

void main() {
  group('the eyebrow names the category, it does not print its slug', () {
    test('a known slug reads as its English display name', () {
      final eyebrow = homeHeroEyebrow(
        copy: const AppLocalizations(Locale('en')),
        room: _room(category: 'talk'),
      );
      expect(eyebrow, startsWith('Talk'));
      expect(eyebrow, isNot(contains('talk •')));
    });

    test('a known slug reads as its Polish display name', () {
      final eyebrow = homeHeroEyebrow(
        copy: const AppLocalizations(Locale('pl')),
        room: _room(category: 'talk'),
      );
      expect(eyebrow, startsWith('Rozmowy'));
    });

    test('every slug Discover knows has a display name on Home too', () {
      const copy = AppLocalizations(Locale('pl'));
      for (final slug in const [
        'talk',
        'music',
        'gaming',
        'chill',
        'study',
        'business',
        'tech',
      ]) {
        final eyebrow = homeHeroEyebrow(
          copy: copy,
          room: _room(category: slug),
        );
        expect(
          eyebrow.startsWith(slug),
          isFalse,
          reason: 'the slug "$slug" reached the eyebrow unreplaced',
        );
      }
    });

    test('an unknown slug is still shown rather than dropped', () {
      final eyebrow = homeHeroEyebrow(
        copy: const AppLocalizations(Locale('pl')),
        room: _room(category: 'astronomia'),
      );
      expect(eyebrow, startsWith('astronomia'));
    });

    test('a room with no category simply has none in its eyebrow', () {
      final eyebrow = homeHeroEyebrow(
        copy: const AppLocalizations(Locale('pl')),
        room: _room(category: '   '),
      );
      expect(eyebrow, 'Wieczorne granie');
    });
  });
}
