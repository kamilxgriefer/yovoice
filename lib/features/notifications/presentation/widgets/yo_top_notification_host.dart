import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';

/// Presentation only. Delivery, privacy, deduplication and navigation authority
/// remain in the caller. No notification is retained before a host accepts it.
@immutable
class YoTopNotification {
  const YoTopNotification({
    required this.title,
    required this.type,
    required this.onOpen,
    this.body,
    this.leading,
    this.source,
  });

  final String title;
  final String? body;
  final NotificationType type;
  final VoidCallback onOpen;
  final Widget? leading;

  /// Presentation owner only; not a delivery/deduplication identifier.
  /// Lets a retiring route clear its own card without dismissing a newer one.
  final Object? source;

  bool get isAchievement => type == NotificationType.achievementUnlocked;
  Duration get duration => Duration(seconds: isAchievement ? 2 : 5);
}

/// An accepted show is immediately owned by the mounted foreground host.
/// A rejected show is never queued here: the existing delivery arbiter retries.
class YoTopNotificationController {
  _YoTopNotificationHostState? _host;
  bool _disposed = false;

  bool get isShowing => _host?._notification != null;

  bool show(YoTopNotification notification) =>
      !_disposed && (_host?._show(notification) ?? false);

  /// Privacy/session boundaries bypass exit animation and cancel every timer.
  void clear({Object? source}) {
    if (source != null && _host?._notification?.source != source) return;
    _host?._clear();
  }

  void dispose() {
    if (_disposed) return;
    clear();
    _disposed = true;
    _host = null;
  }
}

/// Installed inside MaterialApp.builder, outside the Navigator. Its Stack only
/// hit-tests the actual card, so sheets/routes cannot cover it and the rest of
/// the app remains interactive. It owns no global focus or modal barrier.
class YoTopNotificationHost extends StatefulWidget {
  const YoTopNotificationHost({
    required this.controller,
    required this.child,
    this.onReady,
    super.key,
  });

  final YoTopNotificationController controller;
  final Widget child;
  final VoidCallback? onReady;

  static YoTopNotificationController? maybeOf(BuildContext context) => context
      .findAncestorWidgetOfExactType<YoTopNotificationHost>()
      ?.controller;

  @override
  State<YoTopNotificationHost> createState() => _YoTopNotificationHostState();
}

class _YoTopNotificationHostState extends State<YoTopNotificationHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  late final Animation<double> _eased;
  YoTopNotification? _notification;
  Timer? _dismissTimer;
  int _generation = 0;
  int _contentRevision = 0;
  final _notificationFocus = FocusScopeNode(
    debugLabel: 'Notification region',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final _closeFocus = FocusNode(debugLabel: 'Notification close');
  final _openFocus = FocusNode(debugLabel: 'Notification open');
  final _contentScroll = ScrollController(keepScrollOffset: false);
  FocusNode? _returnFocus;
  bool _closing = false;
  bool _hovered = false;
  bool _focused = false;
  bool _reducedMotion = false;
  bool _accessibleNavigation = false;
  bool _foreground = true;
  bool _hasSpace = false;

  double _topInset(MediaQueryData media) =>
      math.max(media.padding.top, media.viewPadding.top) + 10;

  double _availableHeight(MediaQueryData media) => math.max(
    0.0,
    media.size.height - _topInset(media) - media.viewInsets.bottom - 10,
  );

  double _minimumHeight(MediaQueryData media) =>
      24 + 44 + math.max(48, 28 * media.textScaler.scale(1) + 20);

  @override
  void initState() {
    super.initState();
    _foreground = _isForeground(WidgetsBinding.instance.lifecycleState);
    widget.controller._host = this;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addHighlightModeListener(_handleHighlightMode);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 160),
    )..addStatusListener(_handleMotionStatus);
    _eased = CurvedAnimation(parent: _motion, curve: Curves.easeOutCubic);
    _notifyReadyAfterFrame();
  }

  bool _isForeground(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _handleHighlightMode(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant YoTopNotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._host = null;
      _clear();
      widget.controller._host = this;
      _notifyReadyAfterFrame();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final previousAccessibleNavigation = _accessibleNavigation;
    final previousHasSpace = _hasSpace;
    _hasSpace = _availableHeight(media) >= _minimumHeight(media);
    _accessibleNavigation = media.accessibleNavigation;
    _reducedMotion = media.disableAnimations || media.accessibleNavigation;
    if (_reducedMotion && _notification != null) {
      if (_closing) {
        _clear();
      } else {
        _motion.value = 1;
      }
    }
    if (previousAccessibleNavigation != _accessibleNavigation) {
      _scheduleDismissal();
    }
    if (!_hasSpace) {
      _clear();
    } else if (!previousHasSpace) {
      _notifyReadyAfterFrame();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    if (!_foreground) {
      _clear();
    } else {
      _notifyReadyAfterFrame();
    }
  }

  void _notifyReadyAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foreground && !widget.controller._disposed) {
        widget.onReady?.call();
      }
    });
  }

  bool _show(YoTopNotification notification) {
    if (!mounted ||
        !_foreground ||
        !_hasSpace ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      return false;
    }
    _dismissTimer?.cancel();
    _generation++;
    _contentRevision++;
    setState(() {
      _notification = notification;
      _closing = false;
    });
    if (_reducedMotion) {
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
    _scheduleDismissal();
    return true;
  }

  void _scheduleDismissal() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    final notification = _notification;
    if (notification == null ||
        _closing ||
        !_foreground ||
        _accessibleNavigation ||
        _hovered ||
        _focused) {
      return;
    }
    final generation = _generation;
    // Leaving hover/focus grants a full reading window. Never dismiss while
    // someone is inspecting or keyboard-navigating an actionable notification.
    _dismissTimer = Timer(notification.duration, () {
      if (mounted && generation == _generation) _dismiss();
    });
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _generation++;
    if (_notification == null) return;
    if (_reducedMotion) {
      _clear();
    } else {
      setState(() => _closing = true);
      _motion.reverse();
    }
  }

  // Deliberate region navigation, never focus on arrival. This parent handler
  // leaves route/modal Tab and Escape semantics unchanged outside the banner.
  KeyEventResult _handleRegionKey(FocusNode _, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        _notification == null ||
        _closing ||
        !_foreground ||
        !_hasSpace) {
      return KeyEventResult.ignored;
    }
    if (_notificationFocus.hasFocus && _contentScroll.hasClients) {
      final position = _contentScroll.position;
      final target = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowDown => position.pixels + 40,
        LogicalKeyboardKey.arrowUp => position.pixels - 40,
        LogicalKeyboardKey.pageDown =>
          position.pixels + position.viewportDimension * .8,
        LogicalKeyboardKey.pageUp =>
          position.pixels - position.viewportDimension * .8,
        LogicalKeyboardKey.home => position.minScrollExtent,
        LogicalKeyboardKey.end => position.maxScrollExtent,
        _ => null,
      };
      if (target != null) {
        _contentScroll.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f6 &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      if (_notificationFocus.hasFocus) {
        _restorePreviousFocus();
      } else {
        // Never request an unattached node: Flutter could defer that request
        // across a session clear and focus a later account's notification.
        if (_closeFocus.context?.mounted != true ||
            !_closeFocus.canRequestFocus) {
          return KeyEventResult.ignored;
        }
        _returnFocus = FocusManager.instance.primaryFocus;
        _closeFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _notificationFocus.hasFocus) {
      _dismissFromInteraction();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _restorePreviousFocus() {
    final previous = _returnFocus;
    _returnFocus = null;
    if (previous?.context?.mounted == true && previous!.canRequestFocus) {
      previous.requestFocus();
    } else {
      _notificationFocus.unfocus(
        disposition: UnfocusDisposition.previouslyFocusedChild,
      );
    }
  }

  void _dismissFromInteraction() {
    if (_notificationFocus.hasFocus) _restorePreviousFocus();
    _dismiss();
  }

  void _handleMotionStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _closing) _clear();
  }

  void _clear() {
    _generation++;
    // External/session/lifecycle clears and Open deliberately do not restore
    // old-route focus. The destination/auth boundary owns its next focus.
    _returnFocus = null;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _motion.stop();
    if (_notification == null) return;
    setState(() {
      _notification = null;
      _closing = false;
      _hovered = false;
      _focused = false;
    });
  }

  void _open(YoTopNotification notification) {
    if (_notification != notification || _closing) return;
    _clear();
    notification.onOpen();
  }

  @override
  void dispose() {
    _generation++;
    _dismissTimer?.cancel();
    _notification = null;
    if (widget.controller._host == this) widget.controller._host = null;
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeHighlightModeListener(_handleHighlightMode);
    _returnFocus = null;
    _notificationFocus.dispose();
    _closeFocus.dispose();
    _openFocus.dispose();
    _contentScroll.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notification = _notification;
    final media = MediaQuery.of(context);
    final top = _topInset(media);
    final availableHeight = _availableHeight(media);
    final showKeyboardHint = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ =>
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
    };
    // Give only the card an Overlay for Material tooltips. Keep the Navigator
    // outside it: existing route rootOverlay entries must stay below the card.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleRegionKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned.fill(
            child: Overlay.wrap(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (notification != null && _hasSpace)
                    Positioned(
                      top: top,
                      left: math.max(media.padding.left, 16),
                      right: math.max(media.padding.right, 16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 520,
                            maxHeight: math.min(
                              availableHeight,
                              math.min(
                                360,
                                math.max(
                                  _minimumHeight(media),
                                  availableHeight * .65,
                                ),
                              ),
                            ),
                          ),
                          child: AnimatedBuilder(
                            animation: _motion,
                            builder: (context, child) => Opacity(
                              opacity: _eased.value,
                              child: Transform.translate(
                                offset: Offset(0, -18 * (1 - _eased.value)),
                                child: Transform.scale(
                                  scale: .98 + .02 * _eased.value,
                                  alignment: Alignment.topCenter,
                                  child: child,
                                ),
                              ),
                            ),
                            child: MouseRegion(
                              onEnter: (_) {
                                _hovered = true;
                                _scheduleDismissal();
                              },
                              onExit: (_) {
                                _hovered = false;
                                _scheduleDismissal();
                              },
                              child: FocusScope(
                                node: _notificationFocus,
                                onFocusChange: (focused) {
                                  _focused = focused;
                                  _scheduleDismissal();
                                },
                                child: IgnorePointer(
                                  ignoring: _closing,
                                  child: _NotificationCard(
                                    notification: notification,
                                    contentRevision: _contentRevision,
                                    closeFocus: _closeFocus,
                                    openFocus: _openFocus,
                                    scrollController: _contentScroll,
                                    showKeyboardHint: showKeyboardHint,
                                    onOpen: () => _open(notification),
                                    onClose: _dismissFromInteraction,
                                  ),
                                ),
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
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onOpen,
    required this.onClose,
    required this.contentRevision,
    required this.closeFocus,
    required this.openFocus,
    required this.scrollController,
    required this.showKeyboardHint,
  });

  final YoTopNotification notification;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final int contentRevision;
  final FocusNode closeFocus;
  final FocusNode openFocus;
  final ScrollController scrollController;
  final bool showKeyboardHint;

  IconData get _icon => switch (notification.type) {
    NotificationType.achievementUnlocked => Icons.emoji_events_rounded,
    NotificationType.directMessage ||
    NotificationType.mention ||
    NotificationType.reply => Icons.chat_bubble_outline_rounded,
    NotificationType.friendRequest ||
    NotificationType.friendAccepted ||
    NotificationType.follow => Icons.person_add_alt_1_rounded,
    NotificationType.roomInvite ||
    NotificationType.broadcastInvite ||
    NotificationType.liveStarted => Icons.graphic_eq_rounded,
    NotificationType.clubInvite ||
    NotificationType.clubInviteAccepted => Icons.groups_outlined,
    NotificationType.moderation => Icons.shield_outlined,
    _ => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final accent = notification.isAchievement
        ? palette.warningForeground
        : palette.interactiveForeground;
    final body = notification.isAchievement ? null : notification.body?.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        key: const ValueKey('yo-top-notification-card'),
        color: palette.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child:
                            notification.leading ??
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(_icon, size: 22, color: accent),
                            ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: onOpen,
                        canRequestFocus: false,
                        excludeFromSemantics: true,
                        borderRadius: BorderRadius.circular(8),
                        child: KeyedSubtree(
                          key: ValueKey(contentRevision),
                          child: SingleChildScrollView(
                            key: const ValueKey('yo-top-notification-scroll'),
                            primary: false,
                            controller: scrollController,
                            child: Semantics(
                              container: true,
                              liveRegion: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notification.title,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontSize: 14,
                                      height: 1.3,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (body?.isNotEmpty == true) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      body!,
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('yo-top-notification-close'),
                      focusNode: closeFocus,
                      onPressed: onClose,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.standard,
                        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: WidgetStateProperty.resolveWith(
                          (states) => BorderSide(
                            width: 2,
                            color: states.contains(WidgetState.focused)
                                ? palette.focus
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        color: palette.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  if (showKeyboardHint)
                    Tooltip(
                      message: '${copy.notifications} · F6',
                      child: Semantics(
                        label: '${copy.notifications} · F6',
                        child: ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: palette.borderStrong),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              LogicalKeyboardKey.f6.keyLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        key: const ValueKey('yo-top-notification-open'),
                        focusNode: openFocus,
                        onPressed: onOpen,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(copy.text('Open', 'Otwórz')),
                        style: ButtonStyle(
                          visualDensity: VisualDensity.standard,
                          foregroundColor: WidgetStatePropertyAll(
                            palette.interactiveForeground,
                          ),
                          minimumSize: const WidgetStatePropertyAll(
                            Size(44, 44),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          side: WidgetStateProperty.resolveWith(
                            (states) => BorderSide(
                              width: 2,
                              color: states.contains(WidgetState.focused)
                                  ? palette.focus
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
