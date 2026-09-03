import 'package:flutter/material.dart';

import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';

/// Stable shell destination for Reels.
///
/// The feed owns refresh-after-compose, while this wrapper owns the route so
/// both a pushed mobile destination and the persistent desktop slot share the
/// exact same product flow.
class ReelsDestinationScreen extends StatelessWidget {
  const ReelsDestinationScreen({this.isRootTab = false, super.key});

  final bool isRootTab;

  @override
  Widget build(BuildContext context) {
    return ReelsFeedScreen(
      embedded: isRootTab,
      onCreate: () async {
        await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(builder: (_) => const ReelComposerScreen()),
        );
      },
    );
  }
}
