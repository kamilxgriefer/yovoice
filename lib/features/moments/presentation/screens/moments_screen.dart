import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/creator/presentation/screens/find_creators_screen.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reel_composer_screen.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';
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

/// [YoMomentsFormat] now lives beside the chrome that names it; every
/// existing importer of this screen keeps resolving it from here.
export 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart'
    show YoMomentsFormat;

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
    this.reelVideoBuilder,
    this.initialFormat = YoMomentsFormat.voice,
    this.onCreateReel,
    this.onOpenFindCreators,
    this.friendService,
    this.followService,
    super.key,
  });

  final MomentService? momentService;
  final HomeFeedService? feedService;
  final MomentDiscoveryService? discoveryService;

  /// How the "Find people" action of the Following empty state opens the
  /// Find creators destination. The shell may pass its own slot switch;
  /// absent, the existing [FindCreatorsScreen] route is pushed with its
  /// own Back control.
  final VoidCallback? onOpenFindCreators;

  /// Injection seams for the calm context panel's real pool (friends the
  /// viewer does not follow yet); production passes nothing.
  final FriendService? friendService;
  final FollowService? followService;

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

  /// Injection seam for the Reel frame's decoder. Production leaves it null
  /// and the card drives the real player; a widget test or a review capture
  /// supplies a still stand-in, because no decoder runs off-device.
  @visibleForTesting
  final ReelVideoBuilder? reelVideoBuilder;

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

  Future<void> _openFindCreators() async {
    final override = widget.onOpenFindCreators;
    if (override != null) {
      override();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const FindCreatorsScreen()),
    );
  }

  /// The shared header for the Voice column: title row, then the format
  /// switch. The create `+` sits in the header only while no local panel
  /// exists (below 1100); on desktop the panel's "Utwórz" owns creation.
  Widget _voiceHeader(BuildContext context, YoMomentsLayout layout) {
    final showBack = !widget.isRootTab && Navigator.of(context).canPop();
    return YoMomentsHeader(
      showBack: showBack,
      selectedFormat: _format,
      onFormatSelected: _selectFormat,
      gutter: layout.gutter,
      fullWidthSwitch: layout.isNarrow,
      onCreate: layout.showsLocalPanel
          ? null
          : () => unawaited(_showCreateChooser()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appPalette.background,
      body: YoPageBackground(
        section: YoPageSection.moments,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = YoMomentsLayout.of(
                constraints.maxWidth,
                textScale: MediaQuery.textScalerOf(context).scale(1),
              );
              final immersiveReels = !layout.showsLocalPanel;
              // At the card-stage widths (600-1099) the Yeels stage is a card
              // on the page canvas and its header row is laid on that canvas,
              // above the card — not on footage. The header then takes its
              // canvas variant (palette ink, the theme's own "+" lift), as
              // the feed's own chips and refresh do there (the batch-6 review
              // of refine-look §8.4). Only the phone stage lays the chrome on
              // a frame.
              final reelsOnCanvas = immersiveReels && !layout.isNarrow;
              final showBack =
                  !widget.isRootTab && Navigator.of(context).canPop();
              return Column(
                children: [
                  // The Voice column draws the header inside its own main
                  // column (beside the local panel on desktop); the Reels
                  // stage still takes it from here until its own slice.
                  if (_format == YoMomentsFormat.reels && !immersiveReels)
                    ResponsiveContentFrame(
                      width: ResponsiveContentWidth.feed,
                      fillHeight: false,
                      child: YoMomentsHeader(
                        // The shell owns the chrome when this is a root tab; a
                        // pushed route keeps a real Back button.
                        showBack: showBack,
                        selectedFormat: _format,
                        onFormatSelected: _selectFormat,
                        gutter: layout.gutter,
                        onCreate: () => unawaited(_showCreateChooser()),
                      ),
                    ),
                  // The header's resting "+" keeps a clear 8 px above the
                  // stage's docked panels, so its contact shadow is never
                  // cut by the conversation panel's top edge.
                  if (_format == YoMomentsFormat.reels && !immersiveReels)
                    const SizedBox(height: AppRhythm.tight),
                  Expanded(
                    key: const ValueKey('yo-moments-retained-content'),
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
                            friendService: widget.friendService,
                            followService: widget.followService,
                            auth: widget.auth,
                            isVisible: _voiceVisible,
                            onOpenDetail: widget.onOpenDetail,
                            playerFactory: widget.playerFactory,
                            expiryClock: widget.expiryClock,
                            expiryTimerFactory: widget.expiryTimerFactory,
                            onRecord: () => unawaited(_createMoment()),
                            onCreate: () => unawaited(_showCreateChooser()),
                            onOpenFindCreators: () =>
                                unawaited(_openFindCreators()),
                            headerBuilder: _voiceHeader,
                            immersiveHeader: buildImmersiveMomentsHeader(
                              context,
                              showBack: showBack,
                              selectedFormat: _format,
                              onFormatSelected: _selectFormat,
                              onCreate: () => unawaited(_showCreateChooser()),
                              onCanvas: true,
                            ),
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
                            immersive: immersiveReels,
                            immersiveHeader: buildImmersiveMomentsHeader(
                              context,
                              showBack: showBack,
                              selectedFormat: _format,
                              onFormatSelected: _selectFormat,
                              onCreate: () => unawaited(_showCreateChooser()),
                              onCanvas: reelsOnCanvas,
                            ),
                            service: widget.reelService,
                            videoBuilder: widget.reelVideoBuilder,
                            isVisible: _reelsVisible,
                            // Yeels use the same existing friend graph as the
                            // Voice half's people panel. The feed resolves the
                            // production service when no host seam is supplied.
                            friendService: widget.friendService,
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
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Compact format navigation over footage, without consuming the video stage.
///
/// The two formats are large, trackless text tabs. The active format gains
/// violet ink, weight and a short animated glow line; the pool filters below
/// stay deliberately quieter, so the two levels cannot be parsed as one row.
///
/// [onCanvas] is the Voice feed's variant: the same keys, labels, slots and
/// callbacks, drawn in palette roles because Głos sits on the page canvas,
/// not over footage (white words with a black glyph outline on a Pearl
/// canvas were the wrong theme colours). Yeels stays immersive in both
/// themes and keeps the media plates.
ImmersiveFeedHeaderSlots buildImmersiveMomentsHeader(
  BuildContext context, {
  required bool showBack,
  required YoMomentsFormat selectedFormat,
  required ValueChanged<YoMomentsFormat> onFormatSelected,
  required VoidCallback onCreate,
  bool onCanvas = false,
}) {
  final copy = AppLocalizations.of(context);
  final palette = context.appPalette;
  final backLabel = MaterialLocalizations.of(context).backButtonTooltip;
  return ImmersiveFeedHeaderSlots(
    formatSwitch: ImmersiveSegmentedSwitch(
      key: const ValueKey<String>('yo-moments-format-tabs'),
      onCanvas: onCanvas,
      groupLabel: copy.contextualText(
        'yoMoments.contentFormat',
        'Content format',
        'Format treści',
      ),
      selectedIndex: selectedFormat.index,
      onSelected: (index) => onFormatSelected(YoMomentsFormat.values[index]),
      segments: <ImmersiveChromeOption>[
        ImmersiveChromeOption(
          key: const ValueKey<String>('yo-moments-format-voice'),
          label: copy.contextualText('yoMoments.voiceFormat', 'Voice', 'Głos'),
        ),
        const ImmersiveChromeOption(
          key: ValueKey<String>('yo-moments-format-reels'),
          label: 'Yeels',
        ),
      ],
    ),
    leading: showBack
        ? OverlayPlateButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: backLabel,
            onTap: () => Navigator.of(context).maybePop(),
            glyphColor: onCanvas ? palette.textPrimary : Colors.white,
            plateColor: onCanvas ? Colors.transparent : null,
            hoverPlateColor: onCanvas ? palette.surfaceMuted : null,
          )
        : null,
    // Refine-look R6 / §8.4: on the canvas AND over media the create action
    // is the 48 px gradient disc with the brand lift — the screen's one CTA
    // lift, the same disc the wide header draws. Same control, key and
    // spoken label as the plate it replaces.
    trailing: _MomentsCreateDisc(
      key: const ValueKey('moments-create-cta'),
      semanticLabel: copy.text('CREATE', 'UTWÓRZ'),
      onTap: onCreate,
      onMedia: !onCanvas,
    ),
  );
}

/// The immersive header's "+" (refine-look R6): a 48 px [YoGradientDisc] in
/// the logo's gradient with the brand lift and a white `+`, pressed to .94 on
/// touch ([YoPressFeedback.disc]) and lifted a touch more under a pointer.
///
/// The tap target is the same [AccessibleTapRegion] the media plate used —
/// one button node with the spoken label, a 48 px circle, and the two-tone
/// focus ring that stays visible on any frame.
///
/// Over media the disc takes the immersive (Dark) palette, so its lift is
/// the same over footage in both themes: Yeels are immersive in Dark AND
/// Pearl, and Pearl's paper lift would all but vanish on a video.
class _MomentsCreateDisc extends StatefulWidget {
  const _MomentsCreateDisc({
    required this.semanticLabel,
    required this.onTap,
    required this.onMedia,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final bool onMedia;

  @override
  State<_MomentsCreateDisc> createState() => _MomentsCreateDiscState();
}

class _MomentsCreateDiscState extends State<_MomentsCreateDisc> {
  /// The immersive theme the disc reads its palette from over media.
  static final ThemeData _immersive = AppTheme.darkTheme;

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget disc = YoGradientDisc(
      size: AppSizing.standardControlHeight,
      icon: Icons.add_rounded,
      emphasis: YoDiscEmphasis.lift,
      hovered: _hovered,
    );
    if (widget.onMedia) disc = Theme(data: _immersive, child: disc);
    return YoPressFeedback(
      scale: YoPressFeedback.disc,
      child: AccessibleTapRegion(
        onTap: widget.onTap,
        semanticLabel: widget.semanticLabel,
        tooltip: widget.semanticLabel,
        circular: true,
        minimumSize: const Size.square(AppSizing.standardControlHeight),
        focusContrastColor: Colors.black,
        onHover: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        child: disc,
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
    final reelLabel = copy.text('Create Yeel', 'Utwórz Yeel');

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
                // One ink and one construction in both icon circles (the
                // batch-6 review): an outline frame with a filled play, in
                // `interactiveForeground`. The Moments mark fills its whole
                // box where a Material glyph keeps 2 px of air, so it is
                // drawn at 20 to sit at the same optical size as the 24 px
                // glyph beside it.
                _YoMomentsCreateTile(
                  key: const ValueKey<String>('create-voice-moment-choice'),
                  icon: YoMomentsIcon(
                    state: YoMomentsIconState.inactive,
                    size: 20,
                    color: palette.interactiveForeground,
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
                    Icons.smart_display_outlined,
                    size: 24,
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

  /// The tile's icon circle (refine-look §8.4).
  static const double iconCircle = 44;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      button: true,
      label: label,
      hint: subtitle,
      onTap: onTap,
      excludeSemantics: true,
      // Refine-look R2 at the block radius: the top-lit block fill, a
      // hairline edge, Pearl's contact shadow pair, the .985 touch press and
      // no ripple off Android. The Semantics above stays the tile's one
      // node, so the card announces nothing of its own.
      child: YoCard(
        onTap: onTap,
        semanticButton: false,
        minHeight: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: iconCircle,
              height: iconCircle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: .14),
              ),
              child: icon,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    label,
                    // Calm type (refine-look §2.6): w700, not w800.
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}
