import 'dart:async';

import 'package:flutter/material.dart';

class RecordVoiceMomentScreen extends StatefulWidget {
  const RecordVoiceMomentScreen({super.key});

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

  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleRecording() {
    if (_recording) {
      _timer?.cancel();
      setState(() => _recording = false);
      return;
    }

    setState(() {
      _seconds = 0;
      _recording = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      if (_seconds >= 59) {
        timer.cancel();
        setState(() => _recording = false);
        return;
      }

      setState(() => _seconds++);
    });
  }

  String get _timeLabel {
    final minutes = _seconds ~/ 60;
    final seconds = _seconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} / 1:00';
  }

  void _showEngineNotice() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'The recording interface is ready. Native microphone capture and upload are the next integration step.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
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
            colors: [
              Color(0xFF31104D),
              Color(0xFF120B1B),
              _background,
            ],
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
                      onPressed: () => Navigator.pop(context),
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
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                        decoration: BoxDecoration(
                          color: _surface.withValues(alpha: .92),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Share your voice',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'A Voice Moment can be up to 60 seconds long.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 38),
                            SizedBox(
                              height: 120,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: List.generate(31, (index) {
                                  final pattern = ((index * 17) % 48) + 18;
                                  final animated = _recording
                                      ? (pattern + ((_seconds + index) % 15))
                                          .toDouble()
                                      : pattern.toDouble();

                                  return AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 240),
                                    width: 5,
                                    height: animated,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Color(0xFF6A00FF),
                                          Color(0xFFC53AFF),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _timeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Semantics(
                              button: true,
                              label: _recording
                                  ? 'Stop recording'
                                  : 'Start recording',
                              child: InkWell(
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
                                        color: (_recording
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
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed:
                                    _seconds == 0 ? null : _showEngineNotice,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _primary,
                                  disabledBackgroundColor:
                                      const Color(0xFF2B2435),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                ),
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
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
