// Developer-only harness for the avatar/banner crop editor.
//
// Generates a test image locally and opens the REAL ImageCropScreen so
// the editor (pinch/drag/reset/confirm, circular avatar mask, 16:9 profile
// banner frame, 21:9 room-cover frame, JPEG render) can be visually verified
// on Web without a
// signed-in Firebase session or an OS file dialog.
//
// Run with:
//   flutter run -d web-server -t lib/dev/crop_preview.dart
//
// Not referenced by lib/main.dart; never part of a shipped build.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';
import 'package:yovoice/features/profile/presentation/screens/image_crop_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PreviewApp());
}

/// A deterministic, recognizable test card: color bands + grid so crop
/// position and zoom are visually obvious in the editor.
Future<ui.Image> _makeTestImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const colors = [
    Color(0xFF7B2FF7),
    Color(0xFFFF3E81),
    Color(0xFF2FB7F7),
    Color(0xFFFFC94D),
  ];
  final bandWidth = width / colors.length;
  for (var i = 0; i < colors.length; i++) {
    canvas.drawRect(
      Rect.fromLTWH(i * bandWidth, 0, bandWidth, height.toDouble()),
      Paint()..color = colors[i],
    );
  }
  final grid = Paint()
    ..color = const Color(0x66FFFFFF)
    ..strokeWidth = 2;
  for (var x = 0.0; x < width; x += 100) {
    canvas.drawLine(Offset(x, 0), Offset(x, height.toDouble()), grid);
  }
  for (var y = 0.0; y < height; y += 100) {
    canvas.drawLine(Offset(0, y), Offset(width.toDouble(), y), grid);
  }
  return recorder.endRecording().toImage(width, height);
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _Launcher(),
    );
  }
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  Future<void> _open(BuildContext context, ProfileImageKind kind) async {
    final image = await _makeTestImage(1600, 1200);
    if (!context.mounted) return;
    final bytes = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => ImageCropScreen(image: image, kind: kind),
      ),
    );
    image.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bytes == null
              ? 'Editor cancelled'
              : 'Cropped JPEG rendered: '
                    '${(bytes as dynamic).length} bytes',
        ),
      ),
    );
  }

  Future<void> _openRoomCover(BuildContext context) async {
    final image = await _makeTestImage(1600, 1200);
    if (!context.mounted) return;
    final bytes = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => ImageCropScreen.roomCover(image: image),
      ),
    );
    image.dispose();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bytes == null
              ? 'Editor cancelled'
              : 'Cropped room-cover JPEG rendered: '
                    '${(bytes as dynamic).length} bytes',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0618),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => _open(context, ProfileImageKind.avatar),
              child: const Text('Open avatar editor'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _open(context, ProfileImageKind.banner),
              child: const Text('Open banner editor'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _openRoomCover(context),
              child: const Text('Open room-cover editor'),
            ),
          ],
        ),
      ),
    );
  }
}
