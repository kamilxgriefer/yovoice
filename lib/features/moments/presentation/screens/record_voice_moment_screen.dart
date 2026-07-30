import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:yovoice/features/moments/data/services/moment_service.dart';

class RecordVoiceMomentScreen extends StatefulWidget {
  const RecordVoiceMomentScreen({
    this.replyToMomentId,
    this.replyToAuthorName,
    super.key,
  });

  final String? replyToMomentId;
  final String? replyToAuthorName;

  @override
  State<RecordVoiceMomentScreen> createState() =>
      _RecordVoiceMomentScreenState();
}

class _RecordVoiceMomentScreenState extends State<RecordVoiceMomentScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF151020);
  static const Color _border = Color(0xFF382A47);
  static const Color _muted = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFF9D20FF);

  final AudioRecorder _recorder = AudioRecorder();
  final MomentService _momentService = MomentService();
  final TextEditingController _captionController = TextEditingController();

  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  bool _publishing = false;
  String? _recordedPath;

  bool get _hasRecording => _recordedPath != null && _seconds > 0;

  @override
  void dispose() {
    _timer?.cancel();
    _captionController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_publishing) return;
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showMessage(
          'Microphone permission is required to record a Voice Moment.',
        );
        return;
      }

      await _deleteOldRecording();
      final temporaryDirectory = await getTemporaryDirectory();
      final path =
          '${temporaryDirectory.path}/voice_moment_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _seconds = 0;
        _recordedPath = null;
        _recording = true;
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (_seconds >= 59) {
          timer.cancel();
          unawaited(_stopRecording());
          return;
        }
        setState(() => _seconds++);
      });
    } catch (error) {
      _showMessage('Could not start recording: $error');
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _timer?.cancel();

    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordedPath = path;
        if (_seconds == 0) _seconds = 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _recording = false);
      _showMessage('Could not finish recording: $error');
    }
  }

  Future<void> _deleteOldRecording() async {
    final oldPath = _recordedPath;
    _recordedPath = null;
    if (oldPath == null) return;
    final file = File(oldPath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _recordAgain() async {
    await _deleteOldRecording();
    if (!mounted) return;
    setState(() => _seconds = 0);
  }

  Future<void> _publish() async {
    final path = _recordedPath;
    if (path == null || _publishing) return;

    setState(() => _publishing = true);
    try {
      await _momentService.publishRecordedMoment(
        localFilePath: path,
        durationSeconds: _seconds.clamp(1, 60),
        caption: _captionController.text,
        replyToMomentId: widget.replyToMomentId,
      );

      final file = File(path);
      if (await file.exists()) await file.delete();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _showMessage('Could not publish Voice Moment: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  String get _timeLabel {
    final minutes = _seconds ~/ 60;
    final seconds = _seconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} / 1:00';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.1,
            colors: [Color(0xFF31104D), Color(0xFF120B1B), _background],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _publishing
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Record Voice Moment',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 30),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        decoration: BoxDecoration(
                          color: _surface.withValues(alpha: .92),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          children: [
                            Text(
                              widget.replyToMomentId == null
                                  ? 'Share your voice'
                                  : "Reply to ${widget.replyToAuthorName ?? 'this moment'}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.replyToMomentId == null
                                  ? 'Record between 1 and 60 seconds and publish it directly to your feed.'
                                  : 'Record a voice reply up to 60 seconds long.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              height: 110,
                              width: double.infinity,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final barCount = constraints.maxWidth < 330
                                      ? 21
                                      : 27;
                                  return Row(
                                    children: List.generate(barCount, (index) {
                                      final pattern = ((index * 17) % 48) + 18;
                                      final animated = _recording
                                          ? (pattern +
                                                    ((_seconds + index) % 15))
                                                .toDouble()
                                          : pattern.toDouble();
                                      return Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                          ),
                                          child: Center(
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 240,
                                              ),
                                              width: 5,
                                              height: animated,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: [
                                                    Color(0xFF6A00FF),
                                                    Color(0xFFC53AFF),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _timeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 24),
                            InkWell(
                              onTap: _toggleRecording,
                              customBorder: const CircleBorder(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: 86,
                                height: 86,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _recording
                                      ? const Color(0xFFFF416C)
                                      : _primary,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_recording
                                                  ? const Color(0xFFFF416C)
                                                  : _primary)
                                              .withValues(alpha: .42),
                                      blurRadius: 28,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _recording
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                              ),
                            ),
                            if (_hasRecording) ...[
                              const SizedBox(height: 26),
                              TextField(
                                controller: _captionController,
                                enabled: !_publishing,
                                maxLength: 140,
                                maxLines: 3,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Add a caption…',
                                  hintStyle: const TextStyle(color: _muted),
                                  filled: true,
                                  fillColor: const Color(0xFF0D0914),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _publishing
                                          ? null
                                          : _recordAgain,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Record again'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: _border),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _publishing ? null : _publish,
                                      icon: _publishing
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.publish_rounded),
                                      label: Text(
                                        _publishing ? 'Publishing…' : 'Publish',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
