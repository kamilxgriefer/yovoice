import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';

/// [MomentCard] used to live in this file and is imported from here by the
/// creator, profile and Home surfaces. It has its own file and is
/// re-exported so no existing importer had to change.
export 'package:yovoice/features/moments/presentation/widgets/moment_card.dart'
    show MomentCard;
export 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart'
    show MomentsFilter;

/// The two historic halves of the destination, kept as an entry seam:
/// callers that used to route to the Following tab still land on the
/// Following filter of the feed.
enum MomentsTab {
  /// The discovery feed — now the composed page with the story strip,
  /// featured cards and the recent list.
  discover,

  /// The personal slice: your own Moments plus friends and follows.
  following,
}

/// The Voice Moments destination — a stories-style audio feed.
///
/// One surface, four filters (Discover / Following / Most engaged /
/// Recent), a story strip of per-author chains with real viewed state,
/// and a right detail panel on wide layouts. Chains open in the story
/// viewer; every surfaced Moment is inside its 24-hour life
/// (`expiresAt > now`), because expired audio is enforced dead server-side
/// and filtered client-side.
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({
    this.momentService,
    this.feedService,
    this.discoveryService,
    this.viewsService,
    this.contentReportService,
    this.auth,
    this.isRootTab = false,
    this.isVisible,
    this.initialTab = MomentsTab.discover,
    this.initialFilter,
    this.playerFactory,
    super.key,
  });

  final MomentService? momentService;
  final HomeFeedService? feedService;
  final MomentDiscoveryService? discoveryService;

  /// Injection seam for the caller's viewed-state; production passes
  /// nothing.
  final MomentViewsService? viewsService;

  /// Injection seam for the report action on every Moment surface this
  /// screen owns; production passes nothing.
  final ContentReportService? contentReportService;

  /// Injection seam for the viewer's identity.
  final FirebaseAuth? auth;

  /// True when the desktop shell renders this as a fixed content slot
  /// rather than pushing it as a route — the screen then draws no back
  /// button, because the shell owns navigation (ADR-047).
  final bool isRootTab;

  /// False while the shell is showing another tab, so playback stops
  /// instead of continuing from an invisible IndexedStack child.
  final ValueListenable<bool>? isVisible;

  /// Legacy entry seam; [initialFilter] wins when both are provided.
  final MomentsTab initialTab;

  /// Which filter chip starts selected.
  final MomentsFilter? initialFilter;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  Future<void> _createMoment() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RecordVoiceMomentScreen()),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Voice Moment posted.')));
    }
  }

  MomentsFilter get _initialFilter =>
      widget.initialFilter ??
      switch (widget.initialTab) {
        MomentsTab.discover => MomentsFilter.discover,
        MomentsTab.following => MomentsFilter.following,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _MomentsHeader(
              // The shell owns the chrome when this is a root tab; a
              // pushed route keeps a real Back button.
              showBack: !widget.isRootTab && Navigator.of(context).canPop(),
              onCreate: () => unawaited(_createMoment()),
            ),
            Expanded(
              child: MomentsFeedView(
                key: const ValueKey('moments-feed'),
                initialFilter: _initialFilter,
                discoveryService: widget.discoveryService,
                feedService: widget.feedService,
                momentService: widget.momentService,
                viewsService: widget.viewsService,
                contentReportService: widget.contentReportService,
                auth: widget.auth,
                isVisible: widget.isVisible,
                playerFactory: widget.playerFactory,
                onRecord: () => unawaited(_createMoment()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Voice Moments — Real voices. Real moments." plus the create CTA.
///
/// The CTA is ALWAYS enabled: the active-Moment cap (10 at once) is the
/// server's rule, enforced by `reserveMomentDraft`, and the recorder
/// surfaces its refusal honestly. A client that pre-guesses the cap goes
/// stale the day the server changes it.
class _MomentsHeader extends StatelessWidget {
  const _MomentsHeader({required this.showBack, required this.onCreate});

  final bool showBack;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compact is measured in TEXT-SCALED space, not raw pixels: at a
        // 2x accessibility scale the full CTA label is ~560 pt wide and
        // would squeeze the title into a per-character vertical wrap on
        // a 768 pt tablet. The icon CTA keeps its 48 pt target either
        // way.
        final scale = MediaQuery.textScalerOf(context)
            .scale(14)
            .clamp(14.0, 28.0);
        final compact = constraints.maxWidth < 600 * (scale / 14);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            14,
            compact ? 16 : 24,
            8,
          ),
          child: Row(
            children: [
              if (showBack)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textPrimary,
                    tooltip: 'Back',
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Voice Moments',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real voices. Real moments.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: .95),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CreateMomentButton(onTap: onCreate, compact: compact),
            ],
          ),
        );
      },
    );
  }
}

class _CreateMomentButton extends StatelessWidget {
  const _CreateMomentButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // On a phone the title block and a full label cannot share the row;
      // the icon button keeps a 48 pt target.
      return IconButton.filled(
        key: const ValueKey('moments-create-cta'),
        onPressed: onTap,
        tooltip: 'Create your Moment',
        style: IconButton.styleFrom(backgroundColor: AppColors.primary),
        icon: const Icon(Icons.mic_rounded, color: AppColors.textPrimary),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('moments-create-cta'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(
        Icons.mic_rounded,
        size: 18,
        color: AppColors.textPrimary,
      ),
      label: const Text(
        'Create your Moment',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
