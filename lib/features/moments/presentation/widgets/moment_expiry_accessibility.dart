import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';

/// Accessibility plumbing shared by exact-expiry surfaces.
///
/// Expiry is driven by a timer rather than by a user gesture. Replacing a
/// focused player, row or composer without an announcement leaves assistive
/// technology on a detached node, so every visible surface announces one
/// short status and restores keyboard focus to a stable target.
final class MomentExpiryAnnouncer {
  final Set<Object> _announcedTransitions = <Object>{};

  /// Speaks [message] at most once for [transition].
  ///
  /// Callers deliberately use a compact status instead of repeating the
  /// entire replacement subtree. A live region on that subtree as well would
  /// produce duplicate speech on web, where announcements share one DOM node.
  void announce(
    BuildContext context, {
    required Object transition,
    required String message,
    Assertiveness assertiveness = Assertiveness.polite,
  }) {
    final text = message.trim();
    if (!context.mounted ||
        text.isEmpty ||
        !momentExpirySurfaceIsVisible(context) ||
        !_announcedTransitions.add(transition)) {
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        Directionality.of(context),
        assertiveness: assertiveness,
      ),
    );
  }
}

/// Whether [context] belongs to the currently painted expiry surface.
///
/// A route below an opaque child route is still active, and cached tab bodies
/// remain mounted inside [IndexedStack], [Visibility] or [Offstage]. None of
/// those hidden surfaces may announce or reclaim keyboard focus.
bool momentExpirySurfaceIsVisible(BuildContext context) {
  if (!context.mounted) return false;

  final route = ModalRoute.of(context);
  if (route != null && !route.isCurrent) return false;

  var isVisible = !_widgetHidesExpirySurface(context.widget);
  context.visitAncestorElements((ancestor) {
    if (_widgetHidesExpirySurface(ancestor.widget)) {
      isVisible = false;
      return false;
    }
    return true;
  });
  if (!isVisible) return false;

  final firstChild = context.findRenderObject();
  if (firstChild == null || !firstChild.attached) return false;

  var child = firstChild;
  while (child.parent != null) {
    final parent = child.parent!;
    if (parent is RenderOffstage && parent.offstage) return false;
    if (parent is RenderIndexedStack &&
        !_indexedStackPaintsChild(parent, child)) {
      return false;
    }
    child = parent;
  }
  return true;
}

bool _widgetHidesExpirySurface(Widget widget) =>
    (widget is Offstage && widget.offstage) ||
    (widget is Visibility && !widget.visible);

bool _indexedStackPaintsChild(RenderIndexedStack stack, RenderObject branch) {
  final index = stack.index;
  if (index == null) return false;

  RenderBox? selected = stack.firstChild;
  for (
    var childIndex = 0;
    childIndex < index && selected != null;
    childIndex += 1
  ) {
    selected = stack.childAfter(selected);
  }
  return identical(selected, branch);
}

typedef MomentExpiryListTransitionBuilder =
    Widget Function(
      BuildContext context,
      FocusNode recoveryFocus,
      FocusNode Function(String momentId) tileFocusNode,
    );

/// Observes a stream-backed Moment list without owning its subscription.
///
/// Home's mobile and desktop strips receive exact-expiry removals as ordinary
/// list updates. This bridge compares the prior active list before the new one
/// is painted, announces only removals that are actually expired, and keeps a
/// focus node per tile so focus can recover when that tile disappears.
class MomentExpiryListTransition extends StatefulWidget {
  const MomentExpiryListTransition({
    required this.moments,
    required this.clock,
    required this.transitionScope,
    required this.announcementBuilder,
    required this.builder,
    super.key,
  });

  final List<VoiceMoment> moments;
  final DateTime Function() clock;
  final String transitionScope;
  final String Function(int removedCount) announcementBuilder;
  final MomentExpiryListTransitionBuilder builder;

  @override
  State<MomentExpiryListTransition> createState() =>
      _MomentExpiryListTransitionState();
}

class _MomentExpiryListTransitionState
    extends State<MomentExpiryListTransition> {
  final _announcer = MomentExpiryAnnouncer();
  final _recoveryFocus = FocusNode(
    debugLabel: 'Moment list heading after expiry',
  );
  final Map<String, FocusNode> _tileFocusNodes = <String, FocusNode>{};
  late List<VoiceMoment> _previousMoments;
  Set<String> _currentIds = const <String>{};

  @override
  void initState() {
    super.initState();
    _remember(widget.moments);
  }

  @override
  void didUpdateWidget(covariant MomentExpiryListTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _previousMoments;
    _remember(widget.moments);

    final currentIds = _currentIds;
    final now = widget.clock();
    final expired = previous
        .where(
          (moment) =>
              !currentIds.contains(moment.id) && !moment.isActiveAt(now),
        )
        .toList(growable: false);
    final previousFocus = FocusManager.instance.primaryFocus;
    final focusedTileWasRemoved = expired.any(
      (moment) => _tileFocusNodes[moment.id]?.hasFocus ?? false,
    );

    if (expired.isNotEmpty) {
      final expiredIds = expired.map((moment) => moment.id).toList()..sort();
      _announcer.announce(
        context,
        transition: '${widget.transitionScope}:${expiredIds.join(',')}',
        message: widget.announcementBuilder(expired.length),
      );
      if (focusedTileWasRemoved) {
        recoverMomentExpiryFocusAfterFrame(
          context: context,
          fallback: _recoveryFocus,
          previousFocus: previousFocus,
        );
      }
    }
    _disposeRemovedTileFocusNodesAfterFrame();
  }

  void _remember(List<VoiceMoment> moments) {
    _previousMoments = List<VoiceMoment>.of(moments);
    _currentIds = moments.map((moment) => moment.id).toSet();
  }

  FocusNode _tileFocusNode(String momentId) => _tileFocusNodes.putIfAbsent(
    momentId,
    () => FocusNode(debugLabel: 'Voice Moment tile $momentId'),
  );

  void _disposeRemovedTileFocusNodesAfterFrame() {
    final removedIds = _tileFocusNodes.keys
        .where((id) => !_currentIds.contains(id))
        .toList(growable: false);
    if (removedIds.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final id in removedIds) {
        if (_currentIds.contains(id)) continue;
        _tileFocusNodes.remove(id)?.dispose();
      }
    });
  }

  @override
  void dispose() {
    _recoveryFocus.dispose();
    for (final focusNode in _tileFocusNodes.values) {
      focusNode.dispose();
    }
    _tileFocusNodes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _recoveryFocus, _tileFocusNode);
}

/// Whether [focus] currently belongs to the subtree rooted at [scope].
bool momentExpiryFocusIsWithin(BuildContext scope, FocusNode? focus) {
  final focusContext = focus?.context;
  if (focusContext == null) return false;
  if (identical(focusContext, scope)) return true;

  var inside = false;
  focusContext.visitAncestorElements((ancestor) {
    if (identical(ancestor, scope)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// After the expired subtree has been removed, move focus only when the node
/// that used to own it was detached. Focus elsewhere on the page is preserved.
void recoverMomentExpiryFocusAfterFrame({
  required BuildContext context,
  required FocusNode fallback,
  required FocusNode? previousFocus,
  bool force = false,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted ||
        !momentExpirySurfaceIsVisible(context) ||
        !fallback.canRequestFocus) {
      return;
    }
    if (force || (previousFocus != null && !previousFocus.hasFocus)) {
      fallback.requestFocus();
    }
  });
}

/// A non-interactive heading that can safely receive recovered keyboard focus.
/// The outline makes that programmatic move visible instead of creating an
/// invisible focus stop.
class MomentExpiryFocusTarget extends StatefulWidget {
  const MomentExpiryFocusTarget({
    required this.focusNode,
    required this.semanticLabel,
    required this.child,
    this.focusColor,
    super.key,
  });

  final FocusNode focusNode;
  final String semanticLabel;
  final Widget child;
  final Color? focusColor;

  @override
  State<MomentExpiryFocusTarget> createState() =>
      _MomentExpiryFocusTargetState();
}

class _MomentExpiryFocusTargetState extends State<MomentExpiryFocusTarget> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (mounted) setState(() => _focused = focused);
      },
      child: Semantics(
        container: true,
        header: true,
        label: widget.semanticLabel,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused
                  ? widget.focusColor ?? context.appPalette.focus
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
