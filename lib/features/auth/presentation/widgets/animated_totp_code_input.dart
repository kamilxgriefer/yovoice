import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';

enum TotpMotionBreakpoint { narrow, medium, wide }

enum TotpChallengePhase {
  editing,
  submitting,
  orbitEntry,
  orbitLoop,
  success,
  successHold,
  exit,
  error,
}

@immutable
class TotpMotionNodeFrame {
  const TotpMotionNodeFrame({
    required this.center,
    required this.size,
    required this.cornerRadius,
    required this.opacity,
    required this.velocity,
  });

  final Offset center;
  final Size size;
  final double cornerRadius;
  final double opacity;
  final Offset velocity;
}

@immutable
class TotpMotionFrame {
  const TotpMotionFrame({
    required this.phase,
    required this.nodes,
    required this.orbitPhase,
  });

  final TotpChallengePhase phase;
  final List<TotpMotionNodeFrame> nodes;
  final double orbitPhase;
}

@immutable
class TotpMotionGeometry {
  const TotpMotionGeometry({
    required this.breakpoint,
    required this.fieldSize,
    required this.fieldGap,
    required this.nodeDiameter,
    required this.orbitRadiusX,
    required this.orbitRadiusY,
    required this.orbitCenterY,
    required this.stageHeight,
    this.stageMaxWidth = 420,
    this.statusSlotHeight = 42,
  });

  factory TotpMotionGeometry.resolve(double contentSlotWidth) {
    if (contentSlotWidth < 360) {
      return const TotpMotionGeometry(
        breakpoint: TotpMotionBreakpoint.narrow,
        fieldSize: Size(40, 50),
        fieldGap: 6,
        nodeDiameter: 32,
        orbitRadiusX: 78,
        orbitRadiusY: 50,
        orbitCenterY: 72,
        stageHeight: 180,
      );
    }
    if (contentSlotWidth < 600) {
      return const TotpMotionGeometry(
        breakpoint: TotpMotionBreakpoint.medium,
        fieldSize: Size(48, 56),
        fieldGap: 8,
        nodeDiameter: 36,
        orbitRadiusX: 92,
        orbitRadiusY: 60,
        orbitCenterY: 82,
        stageHeight: 196,
      );
    }
    return const TotpMotionGeometry(
      breakpoint: TotpMotionBreakpoint.wide,
      fieldSize: Size(52, 60),
      fieldGap: 10,
      nodeDiameter: 40,
      orbitRadiusX: 108,
      orbitRadiusY: 68,
      orbitCenterY: 90,
      stageHeight: 212,
    );
  }

  final TotpMotionBreakpoint breakpoint;
  final Size fieldSize;
  final double fieldGap;
  final double nodeDiameter;
  final double orbitRadiusX;
  final double orbitRadiusY;
  final double orbitCenterY;
  final double stageHeight;
  final double stageMaxWidth;
  final double statusSlotHeight;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TotpMotionGeometry &&
            other.breakpoint == breakpoint &&
            other.fieldSize == fieldSize &&
            other.fieldGap == fieldGap &&
            other.nodeDiameter == nodeDiameter &&
            other.orbitRadiusX == orbitRadiusX &&
            other.orbitRadiusY == orbitRadiusY &&
            other.orbitCenterY == orbitCenterY &&
            other.stageHeight == stageHeight &&
            other.stageMaxWidth == stageMaxWidth &&
            other.statusSlotHeight == statusSlotHeight;
  }

  @override
  int get hashCode => Object.hash(
    breakpoint,
    fieldSize,
    fieldGap,
    nodeDiameter,
    orbitRadiusX,
    orbitRadiusY,
    orbitCenterY,
    stageHeight,
    stageMaxWidth,
    statusSlotHeight,
  );

  Offset orbitPosition(int index, {required double stageWidth}) {
    final theta = -math.pi / 2 + index * math.pi / 3;
    return Offset(
      stageWidth / 2 + math.cos(theta) * orbitRadiusX,
      orbitCenterY + math.sin(theta) * orbitRadiusY,
    );
  }
}

/// A single semantic TOTP field whose six visual copies become the animated
/// Voice Constellation. Firebase knowledge deliberately stays in the screen.
class AnimatedTotpCodeInput extends StatefulWidget {
  const AnimatedTotpCodeInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.contentSlotWidth,
    required this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final double contentSlotWidth;
  final ValueChanged<String> onSubmitted;

  @override
  State<AnimatedTotpCodeInput> createState() => AnimatedTotpCodeInputState();
}

class AnimatedTotpCodeInputState extends State<AnimatedTotpCodeInput>
    with TickerProviderStateMixin {
  static const _entryCurve = Cubic(.16, 1, .3, 1);
  static const _barX = <double>[-42, -26, -9, 9, 26, 42];
  static const _barHeights = <double>[14, 24, 38, 38, 24, 14];

  late final AnimationController _digitController;
  late final AnimationController _phaseController;
  late final AnimationController _orbitController;

  TotpChallengePhase _phase = TotpChallengePhase.editing;
  TotpMotionFrame? _capturedFrame;
  bool _invalidError = false;
  bool _disposed = false;
  int _sequence = 0;
  int _lastAnimatedDigit = -1;
  late String _lastCode;
  double _stageWidth = 320;

  TotpMotionGeometry get debugGeometry =>
      TotpMotionGeometry.resolve(widget.contentSlotWidth);

  TotpMotionFrame get debugFrame => _frameForCurrentState();

  double get debugDigitEntryProgress => _digitController.value;

  double get debugShakeOffset => _shakeOffset;

  double get debugErrorColorProgress => _phase == TotpChallengePhase.error
      ? (_phaseController.value * (_reduceMotion ? 100 : 600) / 100).clamp(
          0.0,
          1.0,
        )
      : 0;

  double get debugErrorReturnProgress => _phase == TotpChallengePhase.error
      ? (_phaseController.value * 600 / 240).clamp(0.0, 1.0)
      : 0;

  double get debugSuccessBadgeProgress => _phase == TotpChallengePhase.success
      ? (_reduceMotion
            ? _phaseController.value
            : ((_successElapsed - 460) / 200).clamp(0.0, 1.0))
      : 0;

  double get debugSuccessCheckProgress => _phase == TotpChallengePhase.success
      ? (_reduceMotion ? 1 : debugSuccessBadgeProgress)
      : 0;

  @visibleForTesting
  double get debugOrbitCycle => _orbitCycle;

  @visibleForTesting
  double get debugOrbitDashPhaseDegrees => _orbitDashPhaseDegrees(_orbitCycle);

  @visibleForTesting
  double get debugOrbitSwayDegrees {
    if (_phase != TotpChallengePhase.orbitLoop) return 0;
    return _orbitSwayRadians(_orbitCycle) * 180 / math.pi;
  }

  @visibleForTesting
  List<double> get debugOrbitPulseScales {
    if (_phase != TotpChallengePhase.orbitLoop) {
      return const <double>[1, 1, 1, 1, 1, 1];
    }
    return List<double>.generate(
      6,
      (index) => _orbitPulseScale(_orbitCycle, index),
      growable: false,
    );
  }

  @visibleForTesting
  List<double> get debugCyanSignalStrengths {
    if (_phase != TotpChallengePhase.orbitLoop) {
      return const <double>[0, 0, 0, 0, 0, 0];
    }
    return List<double>.generate(
      6,
      (index) => _cyanNodeSignal(_orbitCycle, index),
      growable: false,
    );
  }

  double get _successElapsed => _phaseController.value * 1040;

  double get _orbitCycle {
    final elapsed = _orbitController.lastElapsedDuration;
    if (elapsed == null) return _orbitController.value;
    return elapsed.inMicroseconds /
        const Duration(milliseconds: 1800).inMicroseconds;
  }

  double _orbitAmbientBlend(double cycle) =>
      _smootherStep((cycle * 1800 / 200).clamp(0.0, 1.0));

  double _orbitRadians(double cycle) => _unitCycle(cycle) * math.pi * 2;

  double _orbitSwayRadians(double cycle) =>
      math.sin(_orbitRadians(cycle)) *
      (14 * math.pi / 180) *
      _orbitAmbientBlend(cycle);

  double _orbitPulseScale(double cycle, int index) =>
      1 +
      math.sin(_orbitRadians(cycle) - index * math.pi / 3) *
          .04 *
          _orbitAmbientBlend(cycle);

  double _cyanNodeSignal(double cycle, int index) =>
      math
          .pow(
            math.max(0, math.cos(_orbitRadians(cycle) - index * math.pi / 3)),
            10,
          )
          .toDouble() *
      _orbitAmbientBlend(cycle);

  double _orbitDashPhaseDegrees(double cycle) => cycle * 24;

  TotpChallengePhase get _effectivePhase {
    if (_phase != TotpChallengePhase.success || _reduceMotion) return _phase;
    if (_successElapsed < 660) return TotpChallengePhase.success;
    if (_successElapsed < 840) return TotpChallengePhase.successHold;
    return TotpChallengePhase.exit;
  }

  bool get _reduceMotion {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  @override
  void initState() {
    super.initState();
    _lastCode = widget.controller.text;
    _digitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      value: 1,
    );
    _phaseController = AnimationController(vsync: this);
    _phaseController.addStatusListener(_handlePhaseStatus);
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    widget.controller.addListener(_handleTextChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AnimatedTotpCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
      _lastCode = widget.controller.text;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion && _orbitController.isAnimating) {
      _orbitController.stop();
    }
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleTextChanged() {
    final oldLength = _lastCode.length;
    final newCode = widget.controller.text;
    final newLength = newCode.length;
    _lastCode = newCode;
    if (_phase == TotpChallengePhase.editing && newLength > oldLength) {
      _lastAnimatedDigit = newLength - 1;
      if (_reduceMotion) {
        _digitController.value = 1;
      } else {
        _digitController.forward(from: 0);
      }
    }
    if (mounted) setState(() {});
  }

  void _handlePhaseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _disposed || !mounted) return;
    if (_phase == TotpChallengePhase.submitting && !_reduceMotion) {
      _phase = TotpChallengePhase.orbitEntry;
      _phaseController.duration = const Duration(microseconds: 319500);
      _phaseController.forward(from: 0);
      setState(() {});
    } else if (_phase == TotpChallengePhase.orbitEntry && !_reduceMotion) {
      _phase = TotpChallengePhase.orbitLoop;
      _phaseController.value = 1;
      _orbitController.repeat();
      setState(() {});
    }
  }

  void startSubmitting() {
    ++_sequence;
    _capturedFrame = null;
    _invalidError = false;
    _orbitController.stop();
    _phaseController.stop();
    _phase = TotpChallengePhase.submitting;
    _phaseController.value = 0;
    if (mounted) setState(() {});

    if (_reduceMotion) return;
    _phaseController.duration = const Duration(microseconds: 119500);
    _phaseController.forward(from: 0);
  }

  Future<bool> playSuccess() async {
    final sequence = ++_sequence;
    _captureAndStop();
    _invalidError = false;
    _phase = TotpChallengePhase.success;
    _phaseController.duration = _reduceMotion
        ? const Duration(microseconds: 119500)
        : const Duration(microseconds: 1039500);
    _phaseController.value = 0;
    if (mounted) setState(() {});
    if (!await _forwardPhase(sequence)) return false;
    return _isCurrent(sequence, TotpChallengePhase.success);
  }

  Future<void> playError({required bool invalid}) async {
    final sequence = ++_sequence;
    _captureAndStop();
    _invalidError = invalid;
    _phase = TotpChallengePhase.error;
    _phaseController.duration = _reduceMotion
        ? const Duration(microseconds: 99500)
        : const Duration(microseconds: 599500);
    _phaseController.value = 0;
    if (mounted) setState(() {});
    await _forwardPhase(sequence);
    // Intentionally keep the final error treatment visible. The screen can
    // restore editing immediately; the next user edit calls resetEditing().
  }

  void resetEditing() {
    ++_sequence;
    _phaseController.stop();
    _orbitController.stop();
    _capturedFrame = null;
    _invalidError = false;
    _phase = TotpChallengePhase.editing;
    _phaseController.value = 0;
    _orbitController.value = 0;
    if (mounted) setState(() {});
  }

  void _captureAndStop() {
    _capturedFrame = _frameForCurrentState();
    _phaseController.stop();
    _orbitController.stop();
  }

  Future<bool> _forwardPhase(int sequence) async {
    try {
      await _phaseController.forward(from: _phaseController.value).orCancel;
      return !_disposed && mounted && sequence == _sequence;
    } on TickerCanceled {
      return false;
    }
  }

  bool _isCurrent(int sequence, TotpChallengePhase phase) =>
      !_disposed && mounted && sequence == _sequence && _phase == phase;

  @override
  void dispose() {
    _disposed = true;
    ++_sequence;
    widget.controller.removeListener(_handleTextChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _digitController.dispose();
    _phaseController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  List<TotpMotionNodeFrame> _rowNodes({double opacity = 1}) {
    final geometry = debugGeometry;
    final totalWidth = geometry.fieldSize.width * 6 + geometry.fieldGap * 5;
    final startX = (_stageWidth - totalWidth) / 2;
    final centerY = 8 + geometry.fieldSize.height / 2;
    return List<TotpMotionNodeFrame>.generate(6, (index) {
      return TotpMotionNodeFrame(
        center: Offset(
          startX +
              geometry.fieldSize.width / 2 +
              index * (geometry.fieldSize.width + geometry.fieldGap),
          centerY,
        ),
        size: geometry.fieldSize,
        cornerRadius: 14,
        opacity: opacity,
        velocity: Offset.zero,
      );
    }, growable: false);
  }

  TotpMotionFrame _frameForCurrentState() {
    final geometry = debugGeometry;
    final row = _rowNodes(
      opacity: _reduceMotion && _phase != TotpChallengePhase.editing ? .7 : 1,
    );

    if (_reduceMotion) {
      if (_phase == TotpChallengePhase.success ||
          _phase == TotpChallengePhase.successHold ||
          _phase == TotpChallengePhase.exit) {
        return TotpMotionFrame(
          phase: _phase,
          nodes: row
              .map(
                (node) => TotpMotionNodeFrame(
                  center: node.center,
                  size: node.size,
                  cornerRadius: node.cornerRadius,
                  opacity: (1 - _phaseController.value).clamp(0, 1),
                  velocity: Offset.zero,
                ),
              )
              .toList(growable: false),
          orbitPhase: 0,
        );
      }
      return TotpMotionFrame(phase: _phase, nodes: row, orbitPhase: 0);
    }

    switch (_phase) {
      case TotpChallengePhase.editing:
        return TotpMotionFrame(phase: _phase, nodes: row, orbitPhase: 0);
      case TotpChallengePhase.submitting:
        final t = Curves.easeOutCubic.transform(_phaseController.value);
        return TotpMotionFrame(
          phase: _phase,
          nodes: row
              .map(
                (node) => TotpMotionNodeFrame(
                  center: node.center,
                  size: Size(
                    node.size.width * _lerp(1, .94, t),
                    node.size.height * _lerp(1, .94, t),
                  ),
                  cornerRadius: node.cornerRadius,
                  opacity: 1,
                  velocity: Offset.zero,
                ),
              )
              .toList(growable: false),
          orbitPhase: 0,
        );
      case TotpChallengePhase.orbitEntry:
        final raw = _phaseController.value;
        final t = _entryCurve.transform(raw);
        final nodes = List<TotpMotionNodeFrame>.generate(6, (index) {
          final start = row[index];
          final end = geometry.orbitPosition(index, stageWidth: _stageWidth);
          final center = Offset.lerp(start.center, end, t)!;
          final velocity = _finiteVelocity(
            (sample) => Offset.lerp(
              start.center,
              end,
              _entryCurve.transform(sample.clamp(0, 1)),
            )!,
            raw,
            const Duration(milliseconds: 320),
          );
          return TotpMotionNodeFrame(
            center: center,
            size: Size.lerp(
              Size(start.size.width * .94, start.size.height * .94),
              Size.square(geometry.nodeDiameter),
              t,
            )!,
            cornerRadius: _lerp(
              start.cornerRadius,
              geometry.nodeDiameter / 2,
              t,
            ),
            opacity: 1,
            velocity: velocity,
          );
        }, growable: false);
        return TotpMotionFrame(phase: _phase, nodes: nodes, orbitPhase: 0);
      case TotpChallengePhase.orbitLoop:
        return _orbitFrame(geometry);
      case TotpChallengePhase.success:
        final effective = _effectivePhase;
        if (effective == TotpChallengePhase.success) {
          return _successFrame(geometry);
        }
        return _finalSuccessFrame(effective);
      case TotpChallengePhase.error:
        return _errorFrame(row);
      case TotpChallengePhase.successHold:
        return _finalSuccessFrame(TotpChallengePhase.successHold);
      case TotpChallengePhase.exit:
        return _finalSuccessFrame(TotpChallengePhase.exit);
    }
  }

  TotpMotionFrame _orbitFrame(TotpMotionGeometry geometry) {
    final cycle = _orbitCycle;
    final phase = cycle * math.pi * 2;
    List<TotpMotionNodeFrame> at(double sampleCycle) {
      final rock = _orbitSwayRadians(sampleCycle);
      return List<TotpMotionNodeFrame>.generate(6, (index) {
        final theta = -math.pi / 2 + index * math.pi / 3 + rock;
        final pulse = _orbitPulseScale(sampleCycle, index);
        return TotpMotionNodeFrame(
          center: Offset(
            _stageWidth / 2 + math.cos(theta) * geometry.orbitRadiusX * pulse,
            geometry.orbitCenterY +
                math.sin(theta) * geometry.orbitRadiusY * pulse,
          ),
          size: Size.square(geometry.nodeDiameter),
          cornerRadius: geometry.nodeDiameter / 2,
          opacity: 1,
          velocity: Offset.zero,
        );
      }, growable: false);
    }

    final base = at(cycle);
    const delta = .0001;
    final before = at(cycle - delta);
    final after = at(cycle + delta);
    const cycleSeconds = 1.8;
    final nodes = List<TotpMotionNodeFrame>.generate(6, (index) {
      return TotpMotionNodeFrame(
        center: base[index].center,
        size: base[index].size,
        cornerRadius: base[index].cornerRadius,
        opacity: 1,
        velocity:
            (after[index].center - before[index].center) /
            (2 * delta * cycleSeconds),
      );
    }, growable: false);
    return TotpMotionFrame(phase: _phase, nodes: nodes, orbitPhase: phase);
  }

  TotpMotionFrame _successFrame(TotpMotionGeometry geometry) {
    final captured =
        _capturedFrame ??
        TotpMotionFrame(
          phase: TotpChallengePhase.submitting,
          nodes: _rowNodes(),
          orbitPhase: 0,
        );
    final elapsed = _successElapsed.clamp(0.0, 660.0);
    final center = Offset(_stageWidth / 2, geometry.orbitCenterY);

    if (elapsed <= 160) {
      final t = (elapsed / 160).clamp(0.0, 1.0);
      final easedSize = _entryCurve.transform(t);
      final nodes = List<TotpMotionNodeFrame>.generate(6, (index) {
        final start = captured.nodes[index];
        final theta = -math.pi / 2 + index * math.pi / 3;
        final target = Offset(
          center.dx + math.cos(theta) * geometry.orbitRadiusX * .55,
          center.dy + math.sin(theta) * geometry.orbitRadiusY * .55,
        );
        const durationSeconds = .160;
        final p1 = start.center + start.velocity * (durationSeconds / 3);
        final p2 = target;
        final position = _cubic(start.center, p1, p2, target, t);
        final velocity =
            _cubicDerivative(start.center, p1, p2, target, t) / durationSeconds;
        final diameter = geometry.nodeDiameter;
        return TotpMotionNodeFrame(
          center: position,
          size: Size.lerp(start.size, Size.square(diameter), easedSize)!,
          cornerRadius: _lerp(start.cornerRadius, diameter / 2, easedSize),
          opacity: _lerp(start.opacity, 1, easedSize),
          velocity: velocity,
        );
      }, growable: false);
      return TotpMotionFrame(
        phase: _phase,
        nodes: nodes,
        orbitPhase: captured.orbitPhase,
      );
    }

    if (elapsed <= 340) {
      final raw = ((elapsed - 160) / 180).clamp(0.0, 1.0);
      final t = _smootherStep(raw);
      final nodes = List<TotpMotionNodeFrame>.generate(6, (index) {
        final theta = -math.pi / 2 + index * math.pi / 3;
        final start = Offset(
          center.dx + math.cos(theta) * geometry.orbitRadiusX * .55,
          center.dy + math.sin(theta) * geometry.orbitRadiusY * .55,
        );
        final target = Offset(center.dx + _barX[index], center.dy);
        final velocity =
            (target - start) * (_smootherStepDerivative(raw) / .180);
        return TotpMotionNodeFrame(
          center: Offset.lerp(start, target, t)!,
          size: Size.lerp(
            Size.square(geometry.nodeDiameter),
            Size(7, _barHeights[index]),
            t,
          )!,
          cornerRadius: _lerp(geometry.nodeDiameter / 2, 3.5, t),
          opacity: 1,
          velocity: velocity,
        );
      }, growable: false);
      return TotpMotionFrame(
        phase: _phase,
        nodes: nodes,
        orbitPhase: captured.orbitPhase,
      );
    }

    if (elapsed <= 460) {
      final local = ((elapsed - 340) / 120).clamp(0.0, 1.0);
      final breathWave = math.sin(math.pi * local);
      final breath = 1 + .25 * breathWave * breathWave;
      return TotpMotionFrame(
        phase: _phase,
        nodes: List<TotpMotionNodeFrame>.generate(6, (index) {
          return TotpMotionNodeFrame(
            center: Offset(center.dx + _barX[index], center.dy),
            size: Size(7, _barHeights[index] * breath),
            cornerRadius: 3.5,
            opacity: 1,
            velocity: Offset.zero,
          );
        }, growable: false),
        orbitPhase: captured.orbitPhase,
      );
    }

    final raw = ((elapsed - 460) / 200).clamp(0.0, 1.0);
    final t = _smootherStep(raw);
    return TotpMotionFrame(
      phase: _phase,
      nodes: List<TotpMotionNodeFrame>.generate(6, (index) {
        final start = Offset(center.dx + _barX[index], center.dy);
        return TotpMotionNodeFrame(
          center: Offset.lerp(start, center, t)!,
          size: Size(7, _barHeights[index] * (1 - t * .55)),
          cornerRadius: 3.5,
          opacity: (1 - t * 5).clamp(0, 1),
          velocity: (center - start) * (_smootherStepDerivative(raw) / .200),
        );
      }, growable: false),
      orbitPhase: captured.orbitPhase,
    );
  }

  TotpMotionFrame _errorFrame(List<TotpMotionNodeFrame> row) {
    final captured =
        _capturedFrame ??
        TotpMotionFrame(
          phase: TotpChallengePhase.editing,
          nodes: row,
          orbitPhase: 0,
        );
    final returnProgress = (_phaseController.value * 600 / 240).clamp(0.0, 1.0);
    final propertyProgress = _entryCurve.transform(returnProgress);
    final nodes = List<TotpMotionNodeFrame>.generate(6, (index) {
      final start = captured.nodes[index];
      final target = row[index];
      final position = returnProgress >= 1
          ? target.center
          : _cubic(
              start.center,
              start.center + start.velocity * (.240 / 3),
              target.center,
              target.center,
              returnProgress,
            );
      final velocity = returnProgress >= 1
          ? Offset.zero
          : _cubicDerivative(
                  start.center,
                  start.center + start.velocity * (.240 / 3),
                  target.center,
                  target.center,
                  returnProgress,
                ) /
                .240;
      return TotpMotionNodeFrame(
        center: position,
        size: Size.lerp(start.size, target.size, propertyProgress)!,
        cornerRadius: _lerp(
          start.cornerRadius,
          target.cornerRadius,
          propertyProgress,
        ),
        opacity: _lerp(start.opacity, 1, propertyProgress),
        velocity: velocity,
      );
    }, growable: false);
    return TotpMotionFrame(
      phase: _phase,
      nodes: nodes,
      orbitPhase: captured.orbitPhase,
    );
  }

  TotpMotionFrame _finalSuccessFrame(TotpChallengePhase phase) {
    final geometry = debugGeometry;
    final center = Offset(_stageWidth / 2, geometry.orbitCenterY);
    return TotpMotionFrame(
      phase: phase,
      nodes: List<TotpMotionNodeFrame>.generate(
        6,
        (_) => TotpMotionNodeFrame(
          center: center,
          size: const Size(7, 7),
          cornerRadius: 3.5,
          opacity: 0,
          velocity: Offset.zero,
        ),
        growable: false,
      ),
      orbitPhase: _capturedFrame?.orbitPhase ?? 0,
    );
  }

  Offset _finiteVelocity(
    Offset Function(double value) position,
    double value,
    Duration duration,
  ) {
    const delta = .0001;
    final low = (value - delta).clamp(0.0, 1.0);
    final high = (value + delta).clamp(0.0, 1.0);
    if (high == low) return Offset.zero;
    return (position(high) - position(low)) /
        ((high - low) *
            duration.inMicroseconds /
            Duration.microsecondsPerSecond);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _unitCycle(double value) => value - value.floorToDouble();

  static double _smootherStep(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  static double _smootherStepDerivative(double t) =>
      30 * t * t * (t - 1) * (t - 1);

  static Offset _cubic(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final oneMinus = 1 - t;
    return p0 * (oneMinus * oneMinus * oneMinus) +
        p1 * (3 * oneMinus * oneMinus * t) +
        p2 * (3 * oneMinus * t * t) +
        p3 * (t * t * t);
  }

  static Offset _cubicDerivative(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double t,
  ) {
    final oneMinus = 1 - t;
    return (p1 - p0) * (3 * oneMinus * oneMinus) +
        (p2 - p1) * (6 * oneMinus * t) +
        (p3 - p2) * (3 * t * t);
  }

  double get _shakeOffset {
    if (!_invalidError || _reduceMotion || _phase != TotpChallengePhase.error) {
      return 0;
    }
    final elapsed = _phaseController.value * 600;
    if (elapsed < 240) return 0;
    final t = ((elapsed - 240) / 360).clamp(0.0, 1.0);
    const values = <double>[0, -7, 6, -4, 3, -1, 0];
    final scaled = t * (values.length - 1);
    final index = scaled.floor().clamp(0, values.length - 2);
    return _lerp(values[index], values[index + 1], scaled - index);
  }

  String get _statusText => switch (_phase) {
    TotpChallengePhase.submitting ||
    TotpChallengePhase.orbitEntry ||
    TotpChallengePhase.orbitLoop => 'Verifying code',
    TotpChallengePhase.success ||
    TotpChallengePhase.successHold ||
    TotpChallengePhase.exit => 'Code verified',
    _ => '',
  };

  bool get _showSuccess =>
      _phase == TotpChallengePhase.success ||
      _phase == TotpChallengePhase.successHold ||
      _phase == TotpChallengePhase.exit;

  bool get _showInvalid => _phase == TotpChallengePhase.error && _invalidError;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final geometry = debugGeometry;
    final animations = Listenable.merge(<Listenable>[
      _digitController,
      _phaseController,
      _orbitController,
    ]);

    return LayoutBuilder(
      builder: (context, constraints) {
        _stageWidth = math.min(geometry.stageMaxWidth, constraints.maxWidth);
        return Center(
          child: RepaintBoundary(
            child: SizedBox(
              key: const ValueKey<String>('totp-motion-stage'),
              width: _stageWidth,
              height: geometry.stageHeight,
              child: AnimatedBuilder(
                animation: animations,
                child: _buildRealInput(geometry, palette),
                builder: (context, realInput) {
                  final frame = debugFrame;
                  final exitProgress = ((_successElapsed - 840) / 200).clamp(
                    0.0,
                    1.0,
                  );
                  final exitOpacity = frame.phase == TotpChallengePhase.exit
                      ? 1 - Curves.easeInCubic.transform(exitProgress)
                      : 1.0;
                  final exitY = frame.phase == TotpChallengePhase.exit
                      ? -8 * Curves.easeInCubic.transform(exitProgress)
                      : 0.0;
                  return Opacity(
                    opacity: exitOpacity.clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(_shakeOffset, exitY),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            bottom: geometry.statusSlotHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  radius: .72,
                                  colors: <Color>[
                                    AppColors.primary.withValues(alpha: .16),
                                    palette.surfaceSunken.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            bottom: geometry.statusSlotHeight,
                            child: CustomPaint(
                              painter: _OrbitPathPainter(
                                geometry: geometry,
                                phase: frame.phase,
                                orbitPhase: frame.orbitPhase,
                                opacity: switch (_phase) {
                                  TotpChallengePhase.success =>
                                    1 - (_successElapsed / 460).clamp(0.0, 1.0),
                                  TotpChallengePhase.error =>
                                    1 - debugErrorReturnProgress,
                                  _ => 1,
                                },
                                lineColor: palette.borderStrong,
                              ),
                            ),
                          ),
                          for (
                            var index = 0;
                            index < frame.nodes.length;
                            index++
                          )
                            _buildNode(
                              palette: palette,
                              geometry: geometry,
                              frame: frame.nodes[index],
                              index: index,
                            ),
                          realInput!,
                          if (_showSuccess)
                            _SuccessBadge(
                              center: Offset(
                                _stageWidth / 2,
                                geometry.orbitCenterY,
                              ),
                              reduceMotion: _reduceMotion,
                              progress: _reduceMotion
                                  ? _phaseController.value
                                  : (_successElapsed.clamp(0, 660) - 460) / 200,
                            ),
                          if (_showInvalid)
                            _InvalidBadge(
                              center: Offset(
                                _stageWidth / 2,
                                geometry.orbitCenterY +
                                    geometry.orbitRadiusY * .72,
                              ),
                              progress: debugErrorColorProgress,
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: geometry.statusSlotHeight,
                            child: Semantics(
                              key: const ValueKey<String>(
                                'totp-status-channel',
                              ),
                              container: true,
                              liveRegion: true,
                              label: _statusText,
                              child: ExcludeSemantics(
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: _reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                    child: Text(
                                      _statusText,
                                      key: ValueKey<String>(_statusText),
                                      textAlign: TextAlign.center,
                                      style: AppTypography.labelLarge.copyWith(
                                        color: _statusText == 'Code verified'
                                            ? palette.successForeground
                                            : palette.textSecondary,
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
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNode({
    required AppPalette palette,
    required TotpMotionGeometry geometry,
    required TotpMotionNodeFrame frame,
    required int index,
  }) {
    final value = widget.controller.text;
    final glyph = index < value.length ? value[index] : '';
    final isMoving =
        _phase != TotpChallengePhase.editing &&
        _phase != TotpChallengePhase.submitting &&
        _phase != TotpChallengePhase.error;
    final glyphOpacity = _phase == TotpChallengePhase.success && !_reduceMotion
        ? (1 - _successElapsed / 160).clamp(0.0, 1.0)
        : 1.0;
    final entryProgress =
        index == _lastAnimatedDigit &&
            _phase == TotpChallengePhase.editing &&
            !_reduceMotion
        ? _entryCurve.transform(_digitController.value)
        : 1.0;
    final focused = widget.focusNode.hasFocus && widget.enabled;
    final baseBorderColor = focused ? palette.focus : palette.borderStrong;
    final errorColorProgress = _phase == TotpChallengePhase.error
        ? Curves.easeOut.transform(
            (_phaseController.value * (_reduceMotion ? 100 : 600) / 100).clamp(
              0.0,
              1.0,
            ),
          )
        : 0.0;
    final borderColor = Color.lerp(
      baseBorderColor,
      _invalidError ? AppColors.error : palette.warningForeground,
      errorColorProgress,
    )!;
    final signalStrength = _phase == TotpChallengePhase.orbitLoop
        ? _cyanNodeSignal(_orbitCycle, index)
        : 0.0;
    final movingFill = Color.lerp(
      AppColors.primary.withValues(alpha: .92),
      AppColors.accent.withValues(alpha: .96),
      signalStrength * .72,
    )!;

    return Positioned(
      left: frame.center.dx - frame.size.width / 2,
      top: frame.center.dy - frame.size.height / 2,
      child: Opacity(
        opacity: (frame.opacity * entryProgress).clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - entryProgress)),
          child: Transform.scale(
            scale: _lerp(.94, 1, entryProgress),
            child: SizedBox(
              key: ValueKey<String>('totp-digit-cell-$index'),
              width: frame.size.width,
              height: frame.size.height,
              child: ExcludeSemantics(
                child: DecoratedBox(
                  key: ValueKey<String>('totp-node-$index'),
                  decoration: BoxDecoration(
                    color: isMoving ? movingFill : palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(frame.cornerRadius),
                    border: Border.all(
                      color: isMoving
                          ? AppColors.accent.withValues(
                              alpha: .52 + .48 * signalStrength,
                            )
                          : borderColor,
                      width: focused ? 2 : 1,
                    ),
                    boxShadow: isMoving
                        ? <BoxShadow>[
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: .28),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                            if (signalStrength > .01)
                              BoxShadow(
                                color: AppColors.accent.withValues(
                                  alpha: .40 * signalStrength,
                                ),
                                blurRadius: 18,
                                spreadRadius: 2 * signalStrength,
                              ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: MediaQuery.withNoTextScaling(
                      child: Opacity(
                        opacity: glyphOpacity,
                        child: Text(
                          glyph,
                          style: AppTypography.headlineMedium.copyWith(
                            color: isMoving
                                ? AppColors.white
                                : palette.textPrimary,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRealInput(TotpMotionGeometry geometry, AppPalette palette) {
    final totalWidth = geometry.fieldSize.width * 6 + geometry.fieldGap * 5;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Positioned(
      left: (_stageWidth - totalWidth) / 2,
      top: 8,
      width: totalWidth,
      height: geometry.fieldSize.height,
      child: Semantics(
        container: true,
        label: '6-digit authenticator code',
        child: TextField(
          key: const ValueKey<String>('totp-code-input'),
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: textScale < 1.5,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          maxLength: 6,
          enableSuggestions: false,
          autocorrect: false,
          enableIMEPersonalizedLearning: false,
          showCursor: false,
          cursorColor: Colors.transparent,
          style: const TextStyle(color: Colors.transparent),
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            counterText: '',
            filled: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge({
    required this.center,
    required this.progress,
    required this.reduceMotion,
  });

  final Offset center;
  final double progress;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    final haloT = Curves.easeOut.transform(t);
    return Positioned(
      left: center.dx - 44,
      top: center.dy - 44,
      width: 88,
      height: 88,
      child: Opacity(
        key: const ValueKey<String>('totp-success-transition'),
        opacity: t,
        child: Transform.scale(
          scale: reduceMotion
              ? 1
              : .94 + .06 * Curves.easeOutCubic.transform(t),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!reduceMotion)
                Opacity(
                  opacity: (.32 * (1 - haloT)).clamp(0, 1),
                  child: Container(
                    key: const ValueKey<String>('totp-success-halo'),
                    width: 56 + 32 * haloT,
                    height: 56 + 32 * haloT,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Container(
                key: const ValueKey<String>('totp-success-badge'),
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: CustomPaint(
                  key: const ValueKey<String>('totp-success-check'),
                  painter: _CheckPainter(reduceMotion ? 1 : t),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvalidBadge extends StatelessWidget {
  const _InvalidBadge({required this.center, required this.progress});

  final Offset center;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 28,
      top: center.dy - 28,
      child: Opacity(
        key: const ValueKey<String>('totp-invalid-transition'),
        opacity: progress.clamp(0.0, 1.0),
        child: Container(
          key: const ValueKey<String>('totp-invalid-badge'),
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.error,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.close_rounded,
            key: ValueKey<String>('totp-invalid-x'),
            color: AppColors.contrastInk,
            size: 34,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .27, size.height * .52)
      ..lineTo(size.width * .44, size.height * .68)
      ..lineTo(size.width * .74, size.height * .34);
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * progress.clamp(0, 1));
    canvas.drawPath(
      visible,
      Paint()
        ..color = AppColors.contrastInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _OrbitPathPainter extends CustomPainter {
  const _OrbitPathPainter({
    required this.geometry,
    required this.phase,
    required this.orbitPhase,
    required this.opacity,
    required this.lineColor,
  });

  final TotpMotionGeometry geometry;
  final TotpChallengePhase phase;
  final double orbitPhase;
  final double opacity;
  final Color lineColor;

  bool get _visible =>
      phase == TotpChallengePhase.orbitEntry ||
      phase == TotpChallengePhase.orbitLoop ||
      phase == TotpChallengePhase.success ||
      phase == TotpChallengePhase.error;

  @override
  void paint(Canvas canvas, Size size) {
    if (!_visible) return;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, geometry.orbitCenterY),
      width: geometry.orbitRadiusX * 2,
      height: geometry.orbitRadiusY * 2,
    );
    final path = Path()..addOval(rect);
    final metric = path.computeMetrics().first;
    final dashPaint = Paint()
      ..color = lineColor.withValues(alpha: .42 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const dash = 3.0;
    const gap = 7.0;
    final elapsedCycles = orbitPhase / (math.pi * 2);
    final dashDegrees = elapsedCycles * 24;
    final shift = (dashDegrees / 360) * metric.length;
    const period = dash + gap;
    var distance = -(shift % period);
    while (distance < metric.length) {
      final start = math.max(0.0, distance);
      final end = math.min(metric.length, distance + dash);
      if (end > start) {
        canvas.drawPath(metric.extractPath(start, end), dashPaint);
      }
      distance += period;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPathPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.phase != phase ||
      oldDelegate.orbitPhase != orbitPhase ||
      oldDelegate.opacity != opacity ||
      oldDelegate.lineColor != lineColor;
}
