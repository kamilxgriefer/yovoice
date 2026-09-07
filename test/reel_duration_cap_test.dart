import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/translations/translations_moments_creation.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_trim_strip.dart';

/// The Reel recording cap was raised from 90 seconds to 5 minutes on
/// 2026-09-07 after a tester lost a recording that ran past the old limit.
///
/// The cap is enforced at six client sites and mirrored from
/// `functions/reels/contract.js` (`MAX_DURATION_MS`). Before this change every
/// site carried its own `90 * 1000` literal and nothing proved they agreed, so
/// these tests pin the shared constant, the boundary on both sides, and the
/// user-facing copy that states the limit.
void main() {
  Map<String, Object> mediaWire({
    required int durationMs,
    String kind = 'video',
  }) {
    return <String, Object>{
      'kind': kind,
      'contentType': 'video/mp4',
      'size': 1000000,
      'generation': '1700000000000001',
      'durationMs': durationMs,
    };
  }

  Map<String, Object> audioWire({required int durationMs}) {
    return <String, Object>{
      'contentType': 'audio/mpeg',
      'size': 12000000,
      'generation': '1700000000000002',
      'durationMs': durationMs,
    };
  }

  group('Reel duration cap', () {
    test('every client enforcement point reads one five-minute constant', () {
      expect(maxReelDurationMs, 5 * 60 * 1000);
      expect(minReelDurationMs, 1000);

      // The trim strip's doc comment promises it mirrors the publish contract.
      // Binding the constants keeps that comment true by construction rather
      // than by review.
      expect(reelMaxTrimSelectionMs, maxReelDurationMs);
      expect(reelMinTrimSelectionMs, minReelDurationMs);
    });

    test('a five-minute video descriptor parses and one over is refused', () {
      expect(
        ReelMediaDescriptor.fromWire(
          mediaWire(durationMs: maxReelDurationMs),
        ).durationMs,
        maxReelDurationMs,
      );
      expect(
        ReelMediaDescriptor.fromWire(
          mediaWire(durationMs: minReelDurationMs),
        ).durationMs,
        minReelDurationMs,
      );
      for (final durationMs in <int>[
        maxReelDurationMs + 1,
        minReelDurationMs - 1,
      ]) {
        expect(
          () => ReelMediaDescriptor.fromWire(mediaWire(durationMs: durationMs)),
          throwsA(isA<FormatException>()),
          reason: 'durationMs $durationMs must not parse',
        );
      }
    });

    test('backing audio shares the five-minute cap', () {
      expect(
        ReelBackingAudioDescriptor.fromWire(
          audioWire(durationMs: maxReelDurationMs),
        ).durationMs,
        maxReelDurationMs,
      );
      expect(
        () => ReelBackingAudioDescriptor.fromWire(
          audioWire(durationMs: maxReelDurationMs + 1),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a five-minute trim selection validates, longer does not', () {
      const composition = ReelComposition(
        caption: 'A five-minute Reel',
        trimStartMs: 0,
        trimEndMs: maxReelDurationMs,
      );
      expect(
        composition.validate(
          mediaKind: ReelMediaKind.video,
          durationMs: maxReelDurationMs,
          hasBackingAudio: false,
        ),
        isNull,
      );

      // A window running past the media is still refused, and the message no
      // longer quotes the retired 90-second limit.
      const overlong = ReelComposition(
        caption: 'Too long',
        trimStartMs: 0,
        trimEndMs: maxReelDurationMs + 1,
      );
      expect(
        overlong.validate(
          mediaKind: ReelMediaKind.video,
          durationMs: maxReelDurationMs + 1,
          hasBackingAudio: false,
        ),
        'Video trim must select between 1 second and 5 minutes.',
      );
    });

    test('the audio trim offset accepts the full five minutes', () {
      const composition = ReelComposition(
        caption: 'Backed by a long track',
        trimStartMs: 0,
        trimEndMs: 30 * 1000,
        backingAudioVolume: 70,
        audioTrimStartMs: maxReelDurationMs,
        audioRightsAttested: true,
        audioAttribution: 'Original recording',
      );
      expect(
        composition.validate(
          mediaKind: ReelMediaKind.video,
          durationMs: 30 * 1000,
          hasBackingAudio: true,
        ),
        isNull,
      );
    });
  });

  group('Reel limit copy', () {
    test('states five minutes and keeps the unchanged byte limits', () {
      const media =
          'Photos up to 10 MB. Videos: 1 second – 5 minutes, up to 100 MB.';
      const audio =
          'Use your own MP3, M4A or WAV: 1 second – 5 minutes, up to 15 MB.';
      expect(momentsCreationTranslationKeys, contains(media));
      expect(momentsCreationTranslationKeys, contains(audio));

      // The byte caps deliberately did NOT move with the duration, so the copy
      // must keep quoting them.
      expect(media, contains('100 MB'));
      expect(audio, contains('15 MB'));
    });

    test('no locale still advertises the retired 90-second limit', () {
      final stale = <String>[];
      for (final entry in momentsCreationTranslations.entries) {
        for (final value in entry.value.values) {
          if (value.contains('1–90') ||
              value.contains('1-90') ||
              value.contains('90 seconds')) {
            stale.add('${entry.key}: $value');
          }
        }
      }
      expect(
        stale,
        isEmpty,
        reason: 'these locales still state the old cap:\n${stale.join('\n')}',
      );
    });

    test('every locale states the new duration in its own words', () {
      // Guards against a locale silently falling back to English, and against
      // a partial rollout that updates the key but not the 43 translations.
      const mediaKey =
          'Photos up to 10 MB. Videos: 1 second – 5 minutes, up to 100 MB.';
      for (final entry in momentsCreationTranslations.entries) {
        final value = entry.value[mediaKey];
        expect(value, isNotNull, reason: 'locale ${entry.key} has no entry');
        expect(
          value,
          isNot(equals(mediaKey)),
          reason: 'locale ${entry.key} fell back to the English source',
        );
        expect(
          value!.contains('5') || value.contains('٥') || value.contains('५'),
          isTrue,
          reason: 'locale ${entry.key} does not state the five-minute cap',
        );
      }
    });
  });
}
