import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_moments_icon.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

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

/// The two content formats that live inside the single YO Moments
/// destination. Voice Moment remains the audio format name; YO Moments is the
/// section that brings audio and Reels together.
enum YoMomentsFormat { voice, reels }

/// The Voice Moments destination — a stories-style audio feed.
///
/// One surface, four filters (Discover / Following / Most engaged /
/// Recent), a story strip of per-author chains with real viewed state,
/// and a right detail panel on wide layouts. Chains open in the story
/// viewer; every surfaced Moment is live — inside its chosen availability
/// window (`expiresAt > now`) or permanent (no `expiresAt`, the author's
/// "keep until deleted" choice) — because expired audio is enforced dead
/// server-side and filtered client-side.
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
    this.onOpenDetail,
    this.playerFactory,
    this.expiryClock,
    this.expiryTimerFactory,
    this.reelService,
    this.initialFormat = YoMomentsFormat.voice,
    this.onCreateReel,
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

  /// How a Moment's full detail page opens. The shell passes a route that
  /// keeps the bottom navigation visible with Moments active; absent, the
  /// feed pushes the plain detail route with its own Back control.
  final void Function(VoiceMoment moment)? onOpenDetail;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  /// Injection seam for the existing Reels adapter. It is constructed lazily:
  /// a user who stays on Voice does not start the Reels network request.
  final ReelService? reelService;

  final YoMomentsFormat initialFormat;

  /// Test/host seam for the existing Reel composer route.
  final Future<void> Function()? onCreateReel;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> with RouteAware {
  late YoMomentsFormat _format = widget.initialFormat;
  late bool _voiceHasBeenOpened = _format == YoMomentsFormat.voice;
  late bool _reelsHasBeenOpened = _format == YoMomentsFormat.reels;
  int _reelsRevision = 0;
  late final ValueNotifier<bool> _voiceVisible = ValueNotifier<bool>(false);
  late final ValueNotifier<bool> _reelsVisible = ValueNotifier<bool>(false);
  ModalRoute<void>? _observedRoute;
  bool _routeIsCurrent = true;

  @override
  void initState() {
    super.initState();
    widget.isVisible?.addListener(_syncVisibility);
    _syncVisibility();
  }

  @override
  void didUpdateWidget(MomentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_syncVisibility);
      widget.isVisible?.addListener(_syncVisibility);
    }
    _syncVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _observedRoute)) return;
    if (_observedRoute != null) appRouteObserver.unsubscribe(this);
    _observedRoute = route;
    _routeIsCurrent = route?.isCurrent ?? true;
    if (route != null) appRouteObserver.subscribe(this, route);
    _syncVisibility();
  }

  @override
  void didPush() => _setRouteCurrent(true);

  @override
  void didPopNext() => _setRouteCurrent(true);

  @override
  void didPushNext() => _setRouteCurrent(false);

  @override
  void didPop() => _setRouteCurrent(false);

  void _setRouteCurrent(bool value) {
    if (_routeIsCurrent == value) return;
    _routeIsCurrent = value;
    _syncVisibility();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    widget.isVisible?.removeListener(_syncVisibility);
    _voiceVisible.dispose();
    _reelsVisible.dispose();
    super.dispose();
  }

  bool get _destinationVisible =>
      (widget.isVisible?.value ?? true) && _routeIsCurrent;

  void _syncVisibility() {
    _voiceVisible.value =
        _destinationVisible && _format == YoMomentsFormat.voice;
    _reelsVisible.value =
        _destinationVisible && _format == YoMomentsFormat.reels;
  }

  void _selectFormat(YoMomentsFormat format) {
    if (_format == format) return;
    setState(() {
      _format = format;
      if (format == YoMomentsFormat.voice) _voiceHasBeenOpened = true;
      if (format == YoMomentsFormat.reels) _reelsHasBeenOpened = true;
    });
    _syncVisibility();
  }

  Future<void> _createMoment() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RecordVoiceMomentScreen()),
    );
    if (created == true && mounted) {
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.text('Voice Moment posted.', 'Voice Moment opublikowany.'),
          ),
        ),
      );
    }
  }

  Future<void> _openReelComposer() async {
    final override = widget.onCreateReel;
    if (override != null) {
      await override();
      return;
    }
    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ReelComposerScreen()),
    );
  }

  Future<void> _createReelFromHeader() async {
    _selectFormat(YoMomentsFormat.reels);
    await _openReelComposer();
    if (mounted) setState(() => _reelsRevision += 1);
  }

  Future<void> _showCreateChooser() async {
    final palette = context.appPalette;
    final choice = await showModalBottomSheet<_YoMomentsCreateChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: palette.scrim.withValues(alpha: .72),
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 560,
      ),
      builder: (context) => const _YoMomentsCreateSheet(),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _YoMomentsCreateChoice.voice:
        _selectFormat(YoMomentsFormat.voice);
        await _createMoment();
      case _YoMomentsCreateChoice.reel:
        await _createReelFromHeader();
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
      backgroundColor: context.appPalette.background,
      body: YoPageBackground(
        section: YoPageSection.moments,
        child: SafeArea(
          child: Column(
            children: [
              ResponsiveContentFrame(
                width: ResponsiveContentWidth.feed,
                fillHeight: false,
                child: _MomentsHeader(
                  // The shell owns the chrome when this is a root tab; a
                  // pushed route keeps a real Back button.
                  showBack: !widget.isRootTab && Navigator.of(context).canPop(),
                  selectedFormat: _format,
                  onFormatSelected: _selectFormat,
                  onCreate: () => unawaited(_showCreateChooser()),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  key: const ValueKey<String>('yo-moments-format-stack'),
                  index: _format.index,
                  children: <Widget>[
                    if (_voiceHasBeenOpened)
                      MomentsFeedView(
                        key: const ValueKey('moments-feed'),
                        initialFilter: _initialFilter,
                        discoveryService: widget.discoveryService,
                        feedService: widget.feedService,
                        momentService: widget.momentService,
                        viewsService: widget.viewsService,
                        contentReportService: widget.contentReportService,
                        auth: widget.auth,
                        isVisible: _voiceVisible,
                        onOpenDetail: widget.onOpenDetail,
                        playerFactory: widget.playerFactory,
                        expiryClock: widget.expiryClock,
                        expiryTimerFactory: widget.expiryTimerFactory,
                        onRecord: () => unawaited(_createMoment()),
                      )
                    else
                      const SizedBox.shrink(
                        key: ValueKey<String>('yo-moments-voice-lazy'),
                      ),
                    if (_reelsHasBeenOpened)
                      ReelsFeedScreen(
                        key: ValueKey<String>(
                          'yo-moments-reels-$_reelsRevision',
                        ),
                        embedded: true,
                        service: widget.reelService,
                        isVisible: _reelsVisible,
                        onCreate: _openReelComposer,
                      )
                    else
                      const SizedBox.shrink(
                        key: ValueKey<String>('yo-moments-reels-lazy'),
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

/// "Voice Moments — Real voices. Real moments." plus the create CTA.
///
/// The CTA is ALWAYS enabled: the active-Moment cap (10 at once) is the
/// server's rule, enforced by `reserveMomentDraft`, and the recorder
/// surfaces its refusal honestly. A client that pre-guesses the cap goes
/// stale the day the server changes it.
class _MomentsHeader extends StatelessWidget {
  const _MomentsHeader({
    required this.showBack,
    required this.selectedFormat,
    required this.onFormatSelected,
    required this.onCreate,
  });

  final bool showBack;
  final YoMomentsFormat selectedFormat;
  final ValueChanged<YoMomentsFormat> onFormatSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compact is measured in TEXT-SCALED space, not raw pixels: at a
        // 2x accessibility scale the full CTA label is ~560 pt wide and
        // would squeeze the title into a per-character vertical wrap on
        // a 768 pt tablet. The icon CTA keeps its 48 pt target either
        // way.
        final textScaler = MediaQuery.textScalerOf(context);
        final scale = textScaler.scale(14).clamp(14.0, 28.0);
        final compact = constraints.maxWidth < 600 * (scale / 14);
        final accessibilityLayout =
            textScaler.scale(1) >= 1.6 && constraints.maxWidth < 720;
        final title = Semantics(
          header: true,
          child: Text(
            copy.moments,
            key: const ValueKey<String>('yo-moments-title'),
            // At accessibility sizes the header owns its own row, so let the
            // title take its natural height. A line cap would still truncate
            // some font/locale combinations at 200% even without ellipsis.
            maxLines: accessibilityLayout ? null : 1,
            softWrap: accessibilityLayout,
            overflow: accessibilityLayout
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.parent,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 26,
              height: 1.04,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        final backButton = IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: palette.textPrimary,
          tooltip: copy.text('Back', 'Wstecz'),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            14,
            compact ? 16 : 24,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (accessibilityLayout) ...[
                if (showBack)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: backButton,
                  ),
                SizedBox(width: double.infinity, child: title),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _CreateMomentButton(onTap: onCreate, compact: true),
                ),
              ] else
                Row(
                  children: [
                    if (showBack)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: backButton,
                      ),
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    _CreateMomentButton(onTap: onCreate, compact: compact),
                  ],
                ),
              const SizedBox(height: 10),
              // The rest of the app switches lists with pill chips (Reels
              // Discover/Your Reels, Friends filters, Awards categories); a
              // bordered Material SegmentedButton was the one control that
              // read as a different design system.
              _FormatSwitch(
                selected: selectedFormat,
                onSelected: onFormatSelected,
                compact: compact,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Voice / Reels, in the app's own pill language.
class _FormatSwitch extends StatelessWidget {
  const _FormatSwitch({
    required this.selected,
    required this.onSelected,
    required this.compact,
  });

  final YoMomentsFormat selected;
  final ValueChanged<YoMomentsFormat> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final options = <(YoMomentsFormat, IconData, String)>[
      (
        YoMomentsFormat.voice,
        Icons.mic_rounded,
        copy.contextualText('yoMoments.voiceFormat', 'Voice', 'Głos'),
      ),
      (
        YoMomentsFormat.reels,
        Icons.smart_display_rounded,
        copy.text('Reels', 'Reels'),
      ),
    ];
    return Container(
      key: const ValueKey<String>('yo-moments-format-tabs'),
      width: compact ? double.infinity : 340,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final (format, icon, label) in options)
            Expanded(
              child: _FormatSegment(
                icon: icon,
                label: label,
                selected: format == selected,
                onTap: () => onSelected(format),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormatSegment extends StatelessWidget {
  const _FormatSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimary : palette.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateMomentButton extends StatelessWidget {
  const _CreateMomentButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    if (compact) {
      // On a phone the title block and a full label cannot share the row;
      // the icon button keeps a 48 pt target.
      return IconButton.filled(
        key: const ValueKey('moments-create-cta'),
        onPressed: onTap,
        tooltip: copy.text('CREATE', 'UTWÓRZ'),
        style: IconButton.styleFrom(backgroundColor: colors.primary),
        icon: Icon(Icons.add_rounded, color: colors.onPrimary),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('moments-create-cta'),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(Icons.add_rounded, size: 18, color: colors.onPrimary),
      label: Text(
        copy.text('CREATE', 'UTWÓRZ'),
        style: TextStyle(color: colors.onPrimary, fontWeight: FontWeight.w800),
      ),
    );
  }
}

enum _YoMomentsCreateChoice { voice, reel }

class _YoMomentsCreateSheet extends StatelessWidget {
  const _YoMomentsCreateSheet();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final voiceLabel = copy.text('Create Voice Moment', 'Nagraj Voice Moment');
    final reelLabel = copy.text('Create Reel', 'Utwórz Reel');

    return Material(
      key: const ValueKey<String>('yo-moments-create-sheet'),
      color: palette.surfaceRaised,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                YoModalSheetChrome(
                  sheetLabel: copy.moments,
                  surfaceColor: palette.surfaceRaised,
                  closeColor: palette.textSecondary,
                ),
                _YoMomentsCreateTile(
                  key: const ValueKey<String>('create-voice-moment-choice'),
                  icon: const YoMomentsIcon(
                    state: YoMomentsIconState.active,
                    size: 28,
                  ),
                  label: voiceLabel,
                  subtitle: copy.text(
                    'Moments are short voice updates from people you follow.',
                    'Momenty to krótkie aktualizacje głosowe od obserwowanych osób.',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_YoMomentsCreateChoice.voice),
                ),
                const SizedBox(height: 10),
                _YoMomentsCreateTile(
                  key: const ValueKey<String>('create-reel-choice'),
                  icon: Icon(
                    Icons.smart_display_rounded,
                    size: 28,
                    color: palette.interactiveForeground,
                  ),
                  label: reelLabel,
                  subtitle: copy.text(
                    'Published photos and short videos will appear here.',
                    'Opublikowane zdjęcia i krótkie filmy pojawią się tutaj.',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_YoMomentsCreateChoice.reel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _YoMomentsCreateTile extends StatelessWidget {
  const _YoMomentsCreateTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final Widget icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      container: true,
      button: true,
      label: label,
      hint: subtitle,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: <Widget>[
                  SizedBox.square(dimension: 36, child: Center(child: icon)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
