import 'package:flutter/material.dart';

import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

/// Stable shell destination for Reels.
///
/// Kept only for old deep links and enum callers. Reels now lives inside the
/// unified YO Moments destination; using that screen here also preserves its
/// host + format + current-route playback visibility contract.
class ReelsDestinationScreen extends StatelessWidget {
  const ReelsDestinationScreen({
    this.isRootTab = false,
    this.reelService,
    super.key,
  });

  final bool isRootTab;
  final ReelService? reelService;

  @override
  Widget build(BuildContext context) {
    return MomentsScreen(
      isRootTab: isRootTab,
      initialFormat: YoMomentsFormat.reels,
      reelService: reelService,
    );
  }
}
