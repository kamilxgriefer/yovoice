import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/onboarding/data/guided_onboarding_progress.dart';

enum GuidedOnboardingTarget { create, moments, chats, more }

Future<GuidedOnboardingOutcome?> showGuidedOnboardingTour(
  BuildContext context, {
  required Map<GuidedOnboardingTarget, GlobalKey> anchors,
  required bool desktop,
  bool Function(Size viewport)? desktopLayoutFor,
  ValueChanged<bool>? onLayoutChanged,
}) async {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final route = RawDialogRoute<GuidedOnboardingOutcome>(
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    requestFocus: true,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => GuidedOnboardingTour(
      anchors: anchors,
      desktop: desktop,
      desktopLayoutFor: desktopLayoutFor,
      onLayoutChanged: onLayoutChanged,
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
  );
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<GuidedOnboardingOutcome>(route);
  await route.completed;
  return result;
}

class GuidedOnboardingTour extends StatefulWidget {
  const GuidedOnboardingTour({
    required this.anchors,
    required this.desktop,
    this.desktopLayoutFor,
    this.onLayoutChanged,
    super.key,
  });

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;
  final bool desktop;
  final bool Function(Size viewport)? desktopLayoutFor;
  final ValueChanged<bool>? onLayoutChanged;

  @override
  State<GuidedOnboardingTour> createState() => _GuidedOnboardingTourState();
}

class _GuidedOnboardingTourState extends State<GuidedOnboardingTour> {
  int _index = 0;
  bool _closing = false;
  GuidedOnboardingTarget? _trackedAnchorTarget;
  Rect? _trackedAnchor;
  bool _anchorRefreshScheduled = false;
  Size? _trackedViewport;
  bool? _trackedDesktopLayout;

  List<_GuidedTourStep> _steps(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final desktop = _usesDesktopLayout(context);
    return [
      _GuidedTourStep(
        icon: Icons.waving_hand_rounded,
        title: copy.text('Welcome to YO Voice', 'Witaj w YO Voice'),
        body: copy.text(
          'Join live rooms, listen to Voice Moments, and catch up with your people.',
          'Dołączaj do pokojów na żywo, słuchaj Voice Moments i bądź na bieżąco ze swoją społecznością.',
        ),
      ),
      _GuidedTourStep(
        target: GuidedOnboardingTarget.create,
        icon: Icons.graphic_eq_rounded,
        title: copy.text('Use your voice', 'Użyj swojego głosu'),
        body: desktop
            ? copy.text(
                'Create a Voice Moment or start a Voice Room here.',
                'Tutaj szybko nagrasz Voice Moment lub utworzysz pokój głosowy.',
              )
            : copy.text(
                'Create a Voice Room here. Open Your Moments to record a Voice Moment.',
                'Tutaj utworzysz pokój głosowy. Otwórz Twoje Momenty, aby nagrać Voice Moment.',
              ),
      ),
      _GuidedTourStep(
        target: GuidedOnboardingTarget.moments,
        icon: Icons.graphic_eq_outlined,
        title: copy.text('Hear what\'s new', 'Usłysz, co nowego'),
        body: copy.text(
          'Moments are short voice updates from people you follow.',
          'Voice Moments to krótkie nagrania głosowe od obserwowanych osób.',
        ),
      ),
      _GuidedTourStep(
        target: GuidedOnboardingTarget.chats,
        icon: Icons.chat_bubble_outline_rounded,
        title: copy.text('Keep conversations going', 'Pozostań w kontakcie'),
        body: copy.text(
          'Message friends, send photos or voice notes, and start a direct call.',
          'Pisz do znajomych, wysyłaj zdjęcia i głosówki albo zadzwoń bezpośrednio.',
        ),
      ),
      _GuidedTourStep(
        target: GuidedOnboardingTarget.more,
        icon: Icons.grid_view_rounded,
        title: copy.text('More, one tap away', 'Wszystko inne pod ręką'),
        body: desktop
            ? copy.text(
                'Open Clubs, Creator Studio, Awards, alerts, and Settings. You can replay this tour in Settings anytime.',
                'Otwórz kluby, Creator Studio, nagrody, powiadomienia i ustawienia. Ten przewodnik możesz odtworzyć ponownie w ustawieniach.',
              )
            : copy.text(
                'Find Friends, Clubs, your profile, and Settings here. Replay this tour from Settings anytime.',
                'Tutaj znajdziesz znajomych, kluby, profil i ustawienia. Przewodnik możesz zawsze odtworzyć w ustawieniach.',
              ),
      ),
    ];
  }

  bool _usesDesktopLayout(BuildContext context) =>
      widget.desktopLayoutFor?.call(MediaQuery.sizeOf(context)) ??
      widget.desktop;

  void _move(int delta) {
    if (_closing) return;
    final next = (_index + delta).clamp(0, _steps(context).length - 1);
    if (next == _index) return;
    setState(() => _index = next);
  }

  void _finish(GuidedOnboardingOutcome outcome) {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop(outcome);
  }

  Rect? _anchorRect(GuidedOnboardingTarget? target) {
    if (target == null) return null;
    final renderObject = widget.anchors[target]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Rect? _trackedAnchorRect(GuidedOnboardingTarget target) {
    if (_trackedAnchorTarget != target) {
      _trackedAnchorTarget = target;
      _trackedAnchor = _anchorRect(target);
    }
    _scheduleAnchorRefresh(target);
    return _trackedAnchor;
  }

  void _scheduleAnchorRefresh(GuidedOnboardingTarget target) {
    if (_anchorRefreshScheduled) return;
    _anchorRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorRefreshScheduled = false;
      if (!mounted || _closing || _trackedAnchorTarget != target) return;
      final measured = _anchorRect(target);
      if (_sameRect(_trackedAnchor, measured)) return;
      setState(() => _trackedAnchor = measured);
    });
  }

  bool _sameRect(Rect? first, Rect? second) {
    if (first == null || second == null) return first == second;
    return (first.left - second.left).abs() < .1 &&
        (first.top - second.top).abs() < .1 &&
        (first.width - second.width).abs() < .1 &&
        (first.height - second.height).abs() < .1;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps(context);
    final step = steps[_index];
    final viewport = MediaQuery.sizeOf(context);
    final desktopLayout = _usesDesktopLayout(context);
    final placementTarget = step.target ?? GuidedOnboardingTarget.create;
    if (_trackedViewport != viewport ||
        _trackedDesktopLayout != desktopLayout) {
      final layoutChanged = _trackedDesktopLayout != desktopLayout;
      // A key can briefly retain the previous responsive branch's RenderBox.
      // Never feed that stale desktop rect into mobile positioning (or vice
      // versa); use the safe centered placement until post-layout remeasure.
      _trackedViewport = viewport;
      _trackedDesktopLayout = desktopLayout;
      _trackedAnchorTarget = placementTarget;
      _trackedAnchor = null;
      if (layoutChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_closing) {
            widget.onLayoutChanged?.call(desktopLayout);
          }
        });
      }
    }
    final measuredAnchor = _trackedAnchorRect(placementTarget);
    final anchor = step.target == null ? null : measuredAnchor;
    // Welcome has no spotlight, but sharing Create's placement keeps the card
    // stable when the user advances instead of making it jump to the dock.
    final positionAnchor = measuredAnchor;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(GuidedOnboardingOutcome.skipped);
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _SkipTourIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousStepIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _NextStepIntent(),
        },
        child: Actions(
          actions: {
            _SkipTourIntent: CallbackAction<_SkipTourIntent>(
              onInvoke: (_) {
                _finish(GuidedOnboardingOutcome.skipped);
                return null;
              },
            ),
            _PreviousStepIntent: CallbackAction<_PreviousStepIntent>(
              onInvoke: (_) {
                _move(-1);
                return null;
              },
            ),
            _NextStepIntent: CallbackAction<_NextStepIntent>(
              onInvoke: (_) {
                if (_index == steps.length - 1) {
                  _finish(GuidedOnboardingOutcome.completed);
                } else {
                  _move(1);
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            includeSemantics: false,
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: BlockSemantics(
                child: Material(
                  type: MaterialType.transparency,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      final padding = MediaQuery.paddingOf(context);
                      final card = _GuidedTourCard(
                        key: const ValueKey('guided-tour-step-card'),
                        step: step,
                        index: _index,
                        count: steps.length,
                        showBack: _index > 0,
                        showSkip: _index < steps.length - 1,
                        onBack: () => _move(-1),
                        onSkip: () => _finish(GuidedOnboardingOutcome.skipped),
                        onNext: () => _index == steps.length - 1
                            ? _finish(GuidedOnboardingOutcome.completed)
                            : _move(1),
                      );

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            key: const ValueKey('guided-tour-scrim'),
                            painter: _TourScrimPainter(
                              palette: context.appPalette,
                              anchor: anchor,
                            ),
                          ),
                          if (anchor != null)
                            _TourHighlight(
                              key: ValueKey(
                                'guided-tour-highlight-${step.target!.name}',
                              ),
                              rect: anchor,
                            ),
                          _positionCard(
                            size: size,
                            safePadding: padding,
                            anchor: positionAnchor,
                            desktop: desktopLayout,
                            child: card,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _positionCard({
    required Size size,
    required EdgeInsets safePadding,
    required Rect? anchor,
    required bool desktop,
    required Widget child,
  }) {
    if (anchor == null) {
      return SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Center(
          child: _TourCardBounds(maxHeight: size.height - 32, child: child),
        ),
      );
    }

    if (desktop) {
      final left = (anchor.right + 24)
          .clamp(296.0, size.width - 456)
          .toDouble();
      return Positioned(
        left: left,
        right: 24,
        top: safePadding.top + 16,
        bottom: safePadding.bottom + 16,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _TourCardBounds(
            maxHeight: size.height - safePadding.vertical - 32,
            child: child,
          ),
        ),
      );
    }

    final availableAbove = (anchor.top - safePadding.top - 28)
        .clamp(180.0, size.height)
        .toDouble();
    return Positioned(
      left: 16,
      right: 16,
      top: safePadding.top + 12,
      bottom: size.height - anchor.top + 16,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _TourCardBounds(maxHeight: availableAbove, child: child),
      ),
    );
  }
}

class _GuidedTourStep {
  const _GuidedTourStep({
    required this.icon,
    required this.title,
    required this.body,
    this.target,
  });

  final GuidedOnboardingTarget? target;
  final IconData icon;
  final String title;
  final String body;
}

class _TourCardBounds extends StatelessWidget {
  const _TourCardBounds({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
    child: child,
  );
}

class _GuidedTourCard extends StatelessWidget {
  const _GuidedTourCard({
    required this.step,
    required this.index,
    required this.count,
    required this.showBack,
    required this.showSkip,
    required this.onBack,
    required this.onSkip,
    required this.onNext,
    super.key,
  });

  final _GuidedTourStep step;
  final int index;
  final int count;
  final bool showBack;
  final bool showSkip;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final finalStep = index == count - 1;
    final stepLabel = copy.tourStepSemantics(
      index + 1,
      count,
      step.title,
      step.body,
    );
    return Semantics(
      key: const ValueKey('guided-tour-card'),
      container: true,
      scopesRoute: true,
      namesRoute: true,
      liveRegion: true,
      explicitChildNodes: true,
      label: stepLabel,
      child: Material(
        color: palette.surfaceRaised,
        elevation: 18,
        shadowColor: palette.shadow.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [colors.primary, colors.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: .22),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Icon(
                          step.icon,
                          color: colors.onPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          copy.tourProgress(index + 1, count),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .7,
                          ),
                        ),
                      ),
                    ),
                    if (showSkip)
                      TextButton(
                        key: const ValueKey('guided-tour-skip'),
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textSecondary,
                          minimumSize: const Size(48, 48),
                        ),
                        child: Text(copy.text('Skip', 'Pomiń')),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  fit: FlexFit.loose,
                  child: ExcludeSemantics(
                    child: SingleChildScrollView(
                      primary: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.title,
                            key: const ValueKey('guided-tour-heading'),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.45,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            step.body,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var dot = 0; dot < count; dot++) ...[
                        AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          width: dot == index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: dot == index
                                ? colors.primary
                                : palette.borderStrong,
                          ),
                        ),
                        if (dot != count - 1) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  runAlignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (showBack)
                      OutlinedButton(
                        key: const ValueKey('guided-tour-back'),
                        onPressed: onBack,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.textPrimary,
                          side: BorderSide(color: palette.borderStrong),
                          minimumSize: const Size(88, 48),
                        ),
                        child: Text(copy.text('Back', 'Wstecz')),
                      ),
                    FilledButton.icon(
                      key: const ValueKey('guided-tour-next'),
                      onPressed: onNext,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size(112, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      icon: Icon(
                        finalStep
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        size: 19,
                      ),
                      label: Text(
                        finalStep
                            ? copy.text('Done', 'Gotowe')
                            : copy.text('Next', 'Dalej'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TourHighlight extends StatelessWidget {
  const _TourHighlight({required this.rect, super.key});

  final Rect rect;

  @override
  Widget build(BuildContext context) {
    final highlight = rect.inflate(8);
    final circular = (rect.width - rect.height).abs() < 18;
    final palette = context.appPalette;
    final contrastRing = palette.textPrimary;
    final radius = BorderRadius.circular(circular ? highlight.height / 2 : 18);
    return Positioned(
      left: highlight.left,
      top: highlight.top,
      width: highlight.width,
      height: highlight.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: contrastRing, width: 3),
            boxShadow: [
              BoxShadow(
                color: palette.interactiveForeground.withValues(alpha: .38),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: palette.interactiveForeground,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TourScrimPainter extends CustomPainter {
  const _TourScrimPainter({required this.palette, required this.anchor});

  final AppPalette palette;
  final Rect? anchor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (anchor != null) {
      final cutout = anchor!.inflate(8);
      final circular = (anchor!.width - anchor!.height).abs() < 18;
      path.addRRect(
        RRect.fromRectAndRadius(
          cutout,
          Radius.circular(circular ? cutout.height / 2 : 18),
        ),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = palette.scrim.withValues(alpha: .84),
    );
  }

  @override
  bool shouldRepaint(_TourScrimPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.anchor != anchor;
}

class _SkipTourIntent extends Intent {
  const _SkipTourIntent();
}

class _PreviousStepIntent extends Intent {
  const _PreviousStepIntent();
}

class _NextStepIntent extends Intent {
  const _NextStepIntent();
}
