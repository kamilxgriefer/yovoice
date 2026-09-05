// Local-only visual/native recording preview. No Firebase initialization,
// uploads, real users, or publication. Run with -t on an iOS Simulator.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';

void main() => runApp(const _Preview());

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool _pearl = false;
  bool _polish = true;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: Locale(_polish ? 'pl' : 'en'),
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('YO Moments · LOCAL PREVIEW')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Local preview only. Sample image / real device recording. Nothing can be published.',
            ),
            SwitchListTile(
              title: const Text('Pearl'),
              value: _pearl,
              onChanged: (v) => setState(() => _pearl = v),
            ),
            SwitchListTile(
              title: const Text('Polski / English'),
              value: _polish,
              onChanged: (v) => setState(() => _polish = v),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReelComposerScreen(
                    service: ReelService(
                      auth: _PreviewAuth(),
                      callableInvoker: (_, _) async =>
                          throw StateError('Local preview cannot publish.'),
                    ),
                    imagePicker: _SamplePicker(),
                  ),
                ),
              ),
              child: const Text('Reel · sample photo'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecordVoiceMomentScreen(
                    momentService: _NoPublishMomentService(),
                  ),
                ),
              ),
              child: const Text('Voice Moment · device microphone'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SamplePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    final data = await rootBundle.load(
      'assets/images/atmospheres/rooms-lounge.webp',
    );
    return XFile.fromData(
      data.buffer.asUint8List(),
      name: 'local-preview.webp',
      mimeType: 'image/webp',
    );
  }
}

class _PreviewAuth implements FirebaseAuth {
  @override
  User? get currentUser => null;
  @override
  Stream<User?> userChanges() => Stream.value(null);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Local preview only');
}

class _NoPublishMomentService implements MomentService {
  @override
  void abandonPendingPublish(RecordedAudio audio) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Local preview cannot publish.');
}
