// Developer-only harness for the Rooms 2.0 stage system.
//
// Renders the REAL stage widgets (RoomIdentityCard / StageGrid /
// ListenersStrip) with mocked participant sets of 2, 10, 50 and 500 so
// the scalability contract can be verified visually on Web without live
// users: the stage must stay calm at every size.
//
// Run with:
//   flutter run -d web-server -t lib/dev/stage_preview.dart
//
// Not referenced by lib/main.dart; never part of a shipped build.

import 'dart:math';

import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/presentation/widgets/room_stage.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  int _total = 10;
  bool _someoneSpeaking = true;

  static const _names = [
    'Ada', 'Griefer', 'Sieeema', 'Noor', 'Kai', 'Luna', 'Mateo', 'Zoe',
    'Iris', 'Theo', 'Mila', 'Odin', 'Nova', 'Remy', 'Sage', 'Vera',
  ];

  List<StageSpeaker> _speakers(int total) {
    final random = Random(7);
    // Community heuristic: host + up to ~20% speakers, capped at 12.
    final speakerCount = total <= 2 ? total : min(12, max(2, total ~/ 5));
    return [
      for (var i = 0; i < speakerCount; i++)
        StageSpeaker(
          userId: 'u$i',
          displayName: _names[i % _names.length],
          photoUrl: null,
          isHost: i == 0,
          isModerator: i == 1 && speakerCount > 3,
          isMuted: i.isEven && i != 0,
          isSpeaking: _someoneSpeaking && (i == 0 || i == 2),
          audioLevel: _someoneSpeaking ? .3 + .6 * random.nextDouble() : 0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final speakers = _speakers(_total);
    final listeners = _total - speakers.length;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF05030A),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final size in const [2, 10, 50, 500])
                      ChoiceChip(
                        selected: _total == size,
                        label: Text('$size people'),
                        onSelected: (_) => setState(() => _total = size),
                      ),
                    FilterChip(
                      selected: _someoneSpeaking,
                      label: const Text('speaking'),
                      onSelected: (v) =>
                          setState(() => _someoneSpeaking = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  children: [
                    RoomIdentityCard(
                      roomName: 'Midnight Tech Talk',
                      topic:
                          'Late-night conversations about building things '
                          'that matter.',
                      accent: const Color(0xFF9D20FF),
                      quiet: !_someoneSpeaking,
                    ),
                    const SizedBox(height: 14),
                    StageGrid(
                      speakers: speakers,
                      accent: const Color(0xFF9D20FF),
                      onOverflowTap: () {},
                    ),
                    const SizedBox(height: 12),
                    ListenersStrip(
                      count: max(0, listeners),
                      accent: const Color(0xFF9D20FF),
                      onTap: () {},
                      previewNames: _names.take(4).toList(),
                      previewPhotoUrls: const [null, null, null, null],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
