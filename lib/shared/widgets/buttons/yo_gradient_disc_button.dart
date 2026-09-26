import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';

/// Hosts a draw-only [YoGradientDisc] inside the CALLER's own tap widget
/// (refine-look R6 / R14).
///
/// The disc owns no gesture, key, tooltip or semantics, and the surfaces
/// that draw it already pin their tap widget by type and key: the feed's
/// play control is an `IconButton`, the expanded player's disc and the
/// Moment card's bead are `InkWell`s under their own `Semantics`. This host
/// keeps all of that exactly where it is and adds only what the disc needs
/// from the control around it:
///
/// * a [WidgetStatesController] the caller hands to its `IconButton` /
///   `InkWell` (`statesController:`), so the disc can follow the control's
///   REAL hover and keyboard-focus states — pointer hover lifts the contact
///   and the glow by .06, keyboard focus paints the disc's 2 px `focus` ring
///   3 px outside it (the control's own focus highlight only shows in the
///   traditional highlight mode, and so does this one);
/// * the .94 press scale ([YoPressFeedback.disc]) around the painted disc,
///   touch and stylus only, zero under Reduce Motion.
///
/// ```dart
/// YoGradientDiscButton(
///   disc: (hovered, focused) => YoGradientDisc(
///     size: 48,
///     icon: Icons.play_arrow_rounded,
///     gloss: true,
///     hovered: hovered,
///     focused: focused,
///   ),
///   builder: (context, states, disc) => IconButton(
///     key: const ValueKey('play'),
///     statesController: states,
///     onPressed: onPlay,
///     icon: disc,
///   ),
/// )
/// ```
class YoGradientDiscButton extends StatefulWidget {
  const YoGradientDiscButton({
    required this.disc,
    required this.builder,
    this.enabled = true,
    this.pressScale = YoPressFeedback.disc,
    super.key,
  });

  /// Builds the disc for the control's current hover and focus.
  final YoGradientDisc Function(bool hovered, bool focused) disc;

  /// Builds the caller's own tap widget around the finished [disc]; the
  /// caller passes [WidgetStatesController] on as its `statesController`.
  final Widget Function(
    BuildContext context,
    WidgetStatesController states,
    Widget disc,
  )
  builder;

  /// A disabled control neither scales nor reacts.
  final bool enabled;

  /// The press scale; [YoPressFeedback.disc] (.94) by default.
  final double pressScale;

  /// A light haptic tick when a voice starts to play (R14), on the two
  /// platforms that have a haptic engine for it. Everywhere else — web,
  /// desktop — it does nothing rather than calling into an absent channel.
  static void playHaptic() {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        unawaited(HapticFeedback.lightImpact());
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        break;
    }
  }

  @override
  State<YoGradientDiscButton> createState() => _YoGradientDiscButtonState();
}

class _YoGradientDiscButtonState extends State<YoGradientDiscButton> {
  final WidgetStatesController _states = WidgetStatesController();
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_statesChanged);
  }

  @override
  void dispose() {
    _states
      ..removeListener(_statesChanged)
      ..dispose();
    super.dispose();
  }

  // The control reports some states while it is itself being built (focus
  // and disabled follow its callback), and this ancestor cannot rebuild in
  // that phase, so such a change is picked up right after the frame.
  void _statesChanged() {
    if (!mounted) return;
    final states = _states.value;
    final hovered = states.contains(WidgetState.hovered);
    final focused = states.contains(WidgetState.focused);
    if (hovered == _hovered && focused == _focused) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _statesChanged());
      return;
    }
    setState(() {
      _hovered = hovered;
      _focused = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final disc = YoPressFeedback(
      scale: widget.pressScale,
      enabled: enabled,
      child: widget.disc(enabled && _hovered, _focused),
    );
    return widget.builder(context, _states, disc);
  }
}
