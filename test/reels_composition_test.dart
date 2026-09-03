import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';

ReelComposition _videoComposition({
  bool audio = false,
  List<ReelLinkOverlay> links = const <ReelLinkOverlay>[],
}) {
  return ReelComposition(
    caption: 'A short Reel',
    trimStartMs: 1000,
    trimEndMs: 15 * 1000,
    linkOverlays: links,
    backingAudioVolume: audio ? 70 : 0,
    audioRightsAttested: audio,
    audioAttribution: audio ? 'Original recording' : '',
  );
}

void main() {
  test(
    'public HTTPS validation fails closed for local and deceptive hosts',
    () {
      for (final value in <String>[
        'http://example.com',
        'https://localhost/path',
        'https://api.local/path',
        'https://127.0.0.1/path',
        'https://10.0.0.2/path',
        'https://169.254.169.254/latest/meta-data',
        'https://[::1]/path',
        'https://user:password@example.com/path',
        'https://example.com:8443/path',
        'https://intranet/path',
      ]) {
        expect(isSafePublicHttpsUri(Uri.parse(value)), isFalse, reason: value);
      }
      expect(
        isSafePublicHttpsUri(Uri.parse('https://music.example.com/watch?v=1')),
        isTrue,
      );
    },
  );

  test('composition round-trips exact editing parameters', () {
    final original = ReelComposition(
      caption: 'Caption',
      crop: const ReelCropTransform(scale: 1.8, offsetX: -.2, offsetY: .3),
      filter: ReelFilter.cool,
      trimStartMs: 1000,
      trimEndMs: 20 * 1000,
      textOverlays: const <ReelTextOverlay>[
        ReelTextOverlay(
          id: 'title_1',
          text: 'Hello',
          x: .4,
          y: .3,
          scale: 1.25,
          color: ReelOverlayColor.cyan,
        ),
      ],
      linkOverlays: <ReelLinkOverlay>[
        ReelLinkOverlay(
          id: 'link_1',
          label: 'Listen',
          uri: Uri.parse('https://example.com/music'),
          x: .5,
          y: .7,
        ),
      ],
      originalAudioVolume: 80,
    );
    final decoded = ReelComposition.fromWire(
      original.toWire(),
      mediaKind: ReelMediaKind.video,
      durationMs: 30 * 1000,
      hasBackingAudio: false,
    );
    expect(decoded.toWire(), original.toWire());
  });

  test('audio upload requires rights attestation', () {
    expect(
      _videoComposition().validate(
        mediaKind: ReelMediaKind.video,
        durationMs: 30 * 1000,
        hasBackingAudio: true,
      ),
      contains('backing audio'),
    );
    expect(
      _videoComposition(audio: true).validate(
        mediaKind: ReelMediaKind.video,
        durationMs: 30 * 1000,
        hasBackingAudio: true,
      ),
      isNull,
    );
  });

  test('feed decoder accepts opaque Firebase uid and rejects extra fields', () {
    final wire = <String, Object?>{
      'id': 'reel_1',
      'authorId': 'opaque user-Ż',
      'authorName': 'Creator',
      'media': <String, Object>{
        'kind': 'image',
        'contentType': 'image/jpeg',
        'size': 1024,
        'generation': '123',
        'durationMs': 0,
      },
      'backingAudio': null,
      'composition': const ReelComposition(originalAudioVolume: 0).toWire(),
      'publishedAtMillis': 1900000000000,
      'sortKey': '1900000000000_reel_1',
    };
    expect(Reel.fromWire(wire).authorId, 'opaque user-Ż');
    expect(
      () => Reel.fromWire(<String, Object?>{
        ...wire,
        'email': 'secret@example.com',
      }),
      throwsFormatException,
    );
  });
}
