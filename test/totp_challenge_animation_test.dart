import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/widgets/animated_totp_code_input.dart';

import 'totp_challenge_test_support.dart';

void main() {
  AnimatedTotpCodeInputState motionState(WidgetTester tester) => tester
      .state<AnimatedTotpCodeInputState>(find.byType(AnimatedTotpCodeInput));

  void expectClose(double actual, double expected, {double epsilon = .001}) {
    expect(actual, closeTo(expected, epsilon));
  }

  void expectOffsetClose(
    Offset actual,
    Offset expected, {
    double epsilon = .001,
  }) {
    expectClose(actual.dx, expected.dx, epsilon: epsilon);
    expectClose(actual.dy, expected.dy, epsilon: epsilon);
  }

  void expectFrameContinuity(TotpMotionFrame before, TotpMotionFrame after) {
    expect(after.nodes, hasLength(before.nodes.length));
    expectClose(after.orbitPhase, before.orbitPhase, epsilon: .000001);
    for (var index = 0; index < before.nodes.length; index += 1) {
      final oldNode = before.nodes[index];
      final newNode = after.nodes[index];
      expectOffsetClose(newNode.center, oldNode.center, epsilon: .000001);
      expectClose(newNode.size.width, oldNode.size.width, epsilon: .000001);
      expectClose(newNode.size.height, oldNode.size.height, epsilon: .000001);
      expectClose(newNode.cornerRadius, oldNode.cornerRadius, epsilon: .000001);
      expectClose(newNode.opacity, oldNode.opacity, epsilon: .000001);
      expectOffsetClose(newNode.velocity, oldNode.velocity, epsilon: .000001);
    }
  }

  TotpChallengePhase expectedResponsePhase(String name) => switch (name) {
    'compression' => TotpChallengePhase.submitting,
    'mid orbit entry' => TotpChallengePhase.orbitEntry,
    'orbit loop' => TotpChallengePhase.orbitLoop,
    _ => throw ArgumentError.value(name),
  };

  Future<void> driveToResponsePoint(WidgetTester tester, String name) async {
    switch (name) {
      case 'compression':
        await tester.pump(const Duration(milliseconds: 60));
      case 'mid orbit entry':
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 160));
      case 'orbit loop':
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump(const Duration(milliseconds: 400));
      default:
        throw ArgumentError.value(name);
    }
  }

  group('Voice Constellation geometry', () {
    final cases =
        <
          ({
            double width,
            TotpMotionBreakpoint breakpoint,
            Size field,
            double gap,
            double node,
            double radiusX,
            double radiusY,
            double centerY,
            double height,
          })
        >[
          (
            width: 359,
            breakpoint: TotpMotionBreakpoint.narrow,
            field: const Size(40, 50),
            gap: 6,
            node: 32,
            radiusX: 78,
            radiusY: 50,
            centerY: 72,
            height: 180,
          ),
          (
            width: 360,
            breakpoint: TotpMotionBreakpoint.medium,
            field: const Size(48, 56),
            gap: 8,
            node: 36,
            radiusX: 92,
            radiusY: 60,
            centerY: 82,
            height: 196,
          ),
          (
            width: 599,
            breakpoint: TotpMotionBreakpoint.medium,
            field: const Size(48, 56),
            gap: 8,
            node: 36,
            radiusX: 92,
            radiusY: 60,
            centerY: 82,
            height: 196,
          ),
          (
            width: 600,
            breakpoint: TotpMotionBreakpoint.wide,
            field: const Size(52, 60),
            gap: 10,
            node: 40,
            radiusX: 108,
            radiusY: 68,
            centerY: 90,
            height: 212,
          ),
        ];

    for (final value in cases) {
      test('resolves ${value.width.toInt()}px as ${value.breakpoint.name}', () {
        final geometry = TotpMotionGeometry.resolve(value.width);
        expect(geometry.breakpoint, value.breakpoint);
        expect(geometry.fieldSize, value.field);
        expect(geometry.fieldGap, value.gap);
        expect(geometry.nodeDiameter, value.node);
        expect(geometry.orbitRadiusX, value.radiusX);
        expect(geometry.orbitRadiusY, value.radiusY);
        expect(geometry.orbitCenterY, value.centerY);
        expect(geometry.stageHeight, value.height);
        expect(geometry.stageMaxWidth, 420);
        expect(geometry.statusSlotHeight, 42);
      });
    }

    test('places all six nodes on the handed-off ellipse equation', () {
      final geometry = TotpMotionGeometry.resolve(430);
      const stageWidth = 420.0;
      for (var index = 0; index < 6; index += 1) {
        final theta = -math.pi / 2 + index * math.pi / 3;
        final expected = Offset(
          stageWidth / 2 + math.cos(theta) * 92,
          82 + math.sin(theta) * 60,
        );
        expectOffsetClose(
          geometry.orbitPosition(index, stageWidth: stageWidth),
          expected,
        );
      }
    });

    for (final value
        in <
          ({
            double width,
            TotpMotionBreakpoint breakpoint,
            double stageHeight,
            Size cell,
          })
        >[
          (
            width: 320,
            breakpoint: TotpMotionBreakpoint.narrow,
            stageHeight: 180,
            cell: const Size(40, 50),
          ),
          (
            width: 390,
            breakpoint: TotpMotionBreakpoint.medium,
            stageHeight: 196,
            cell: const Size(48, 56),
          ),
          (
            width: 430,
            breakpoint: TotpMotionBreakpoint.medium,
            stageHeight: 196,
            cell: const Size(48, 56),
          ),
          (
            width: 768,
            breakpoint: TotpMotionBreakpoint.wide,
            stageHeight: 212,
            cell: const Size(52, 60),
          ),
          (
            width: 1440,
            breakpoint: TotpMotionBreakpoint.wide,
            stageHeight: 212,
            cell: const Size(52, 60),
          ),
        ]) {
      testWidgets(
        'screen passes outer ${value.width.toInt()}px slot before 420px cap',
        (tester) async {
          useTotpSurface(tester, Size(value.width, 900));
          await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
          await tester.pump();

          final geometry = motionState(tester).debugGeometry;
          expect(geometry.breakpoint, value.breakpoint);
          expect(
            tester.getSize(find.byKey(totpMotionStageKey)).height,
            value.stageHeight,
          );
          expect(
            tester.getSize(find.byKey(totpMotionStageKey)).width,
            lessThanOrEqualTo(420),
          );
          expect(tester.getSize(find.byKey(totpDigitCellKey(0))), value.cell);
          expect(
            find.ancestor(
              of: find.byKey(totpMotionStageKey),
              matching: find.byType(RepaintBoundary),
            ),
            findsWidgets,
          );
        },
      );
    }
  });

  group('Voice Constellation phase timing', () {
    testWidgets('new digit uses the 140ms entry controller', (tester) async {
      await tester.pumpWidget(totpTestApp(FakeTotpChallenge()));
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));

      editable.controller.text = '1';
      expectClose(motionState(tester).debugDigitEntryProgress, 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expectClose(
        motionState(tester).debugDigitEntryProgress,
        .5,
        epsilon: .02,
      );
      await tester.pump(const Duration(milliseconds: 69));
      expect(motionState(tester).debugDigitEntryProgress, lessThan(1));
      await tester.pump(const Duration(milliseconds: 1));
      expectClose(motionState(tester).debugDigitEntryProgress, 1);
    });

    testWidgets('uses exact compression entry and loop boundaries', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      expect(
        motionState(tester).debugFrame.phase,
        TotpChallengePhase.submitting,
      );

      await tester.pump(const Duration(milliseconds: 119));
      expect(
        motionState(tester).debugFrame.phase,
        TotpChallengePhase.submitting,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        motionState(tester).debugFrame.phase,
        TotpChallengePhase.orbitEntry,
      );
      await tester.pump(const Duration(milliseconds: 319));
      expect(
        motionState(tester).debugFrame.phase,
        TotpChallengePhase.orbitEntry,
      );
      final entryEnd = motionState(tester).debugFrame;
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        motionState(tester).debugFrame.phase,
        TotpChallengePhase.orbitLoop,
      );
      final loopStart = motionState(tester).debugFrame;
      for (var index = 0; index < loopStart.nodes.length; index += 1) {
        expectOffsetClose(
          loopStart.nodes[index].center,
          entryEnd.nodes[index].center,
          epsilon: .2,
        );
        expectClose(
          loopStart.nodes[index].size.width,
          entryEnd.nodes[index].size.width,
          epsilon: .2,
        );
        expectClose(
          loopStart.nodes[index].cornerRadius,
          entryEnd.nodes[index].cornerRadius,
          epsilon: .2,
        );
        expect(
          loopStart.nodes[index].velocity.distance,
          lessThan(1),
          reason: 'loop must start without a tangent jump',
        );
      }

      final cycleStart = motionState(tester).debugFrame;
      await tester.pump(const Duration(milliseconds: 900));
      final cycleMidpoint = motionState(tester).debugFrame;
      expect(
        (cycleMidpoint.orbitPhase - cycleStart.orbitPhase).abs(),
        greaterThan(.1),
      );
      await tester.pump(const Duration(milliseconds: 900));
      final cycleEnd = motionState(tester).debugFrame;
      expect(cycleEnd.phase, TotpChallengePhase.orbitLoop);
      final wrappedPhaseDelta = math.atan2(
        math.sin(cycleEnd.orbitPhase - cycleStart.orbitPhase),
        math.cos(cycleEnd.orbitPhase - cycleStart.orbitPhase),
      );
      expectClose(wrappedPhaseDelta, 0, epsilon: .02);
      await disposePendingTotp(tester, pending);
    });

    testWidgets(
      'orbit loop honors radial pulse sway dash phase and node signal tokens',
      (tester) async {
        final challenge = FakeTotpChallenge();
        final pending = challenge.enqueuePending();
        await tester.pumpWidget(totpTestApp(challenge));
        await tester.pump();
        await tester.enterText(find.byKey(totpCodeInputKey), '123456');
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pump(const Duration(milliseconds: 1800));

        final state = motionState(tester);
        expect(state.debugFrame.phase, TotpChallengePhase.orbitLoop);
        expectClose(state.debugOrbitCycle, 1, epsilon: .002);
        final dashStart = state.debugOrbitDashPhaseDegrees;

        for (var index = 0; index < 6; index += 1) {
          final strengths = state.debugCyanSignalStrengths;
          expectClose(strengths[index], 1, epsilon: .0001);
          expect(
            strengths.indexOf(strengths.reduce(math.max)),
            index,
            reason: 'cyan accent must peak on node $index',
          );
          final peakDecoration =
              tester
                      .widget<DecoratedBox>(find.byKey(totpNodeKey(index)))
                      .decoration
                  as BoxDecoration;
          expect(peakDecoration.boxShadow, hasLength(2));

          await tester.pump(const Duration(milliseconds: 150));
          final halfway = state.debugCyanSignalStrengths;
          final next = (index + 1) % 6;
          expectClose(halfway[index], .2373046875, epsilon: .0001);
          expectClose(halfway[next], .2373046875, epsilon: .0001);
          await tester.pump(const Duration(milliseconds: 150));
        }

        expectClose(
          state.debugOrbitDashPhaseDegrees - dashStart,
          24,
          epsilon: .002,
        );
        expectClose(state.debugOrbitCycle, 2, epsilon: .002);

        await tester.pump(const Duration(milliseconds: 450));
        expectClose(state.debugOrbitSwayDegrees, 14, epsilon: .002);
        await tester.pump(const Duration(milliseconds: 900));
        expectClose(state.debugOrbitSwayDegrees, -14, epsilon: .002);
        await tester.pump(const Duration(milliseconds: 900));
        expectClose(state.debugOrbitSwayDegrees, 14, epsilon: .002);

        final geometry = state.debugGeometry;
        final stageWidth = tester.getSize(find.byKey(totpMotionStageKey)).width;
        final center = Offset(stageWidth / 2, geometry.orbitCenterY);
        for (var index = 0; index < 6; index += 1) {
          final scales = state.debugOrbitPulseScales;
          expectClose(scales[index], 1.04, epsilon: .0001);
          expectClose(scales[(index + 3) % 6], .96, epsilon: .0001);
          final node = state.debugFrame.nodes[index];
          final dx = (node.center.dx - center.dx) / geometry.orbitRadiusX;
          final dy = (node.center.dy - center.dy) / geometry.orbitRadiusY;
          expectClose(
            math.sqrt(dx * dx + dy * dy),
            scales[index],
            epsilon: .0001,
          );
          expect(node.size, Size.square(geometry.nodeDiameter));
          expectClose(node.cornerRadius, geometry.nodeDiameter / 2);
          if (index < 5) {
            await tester.pump(const Duration(milliseconds: 300));
          }
        }

        await disposePendingTotp(tester, pending);
      },
    );

    testWidgets('steady orbit remains C1 across the 1800ms wrap', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump(const Duration(microseconds: 1799900));

      final state = motionState(tester);
      final before = state.debugFrame;
      final swayBefore = state.debugOrbitSwayDegrees;
      await tester.pump(const Duration(microseconds: 100));
      final at = state.debugFrame;
      final swayAt = state.debugOrbitSwayDegrees;
      await tester.pump(const Duration(microseconds: 100));
      final after = state.debugFrame;
      final swayAfter = state.debugOrbitSwayDegrees;

      expectClose(state.debugOrbitCycle, 2.0000556, epsilon: .000002);
      expectClose((swayAt - swayBefore) / .0001, 48.869, epsilon: .1);
      expectClose((swayAfter - swayAt) / .0001, 48.869, epsilon: .1);
      for (var index = 0; index < 6; index += 1) {
        expect(
          (at.nodes[index].center - before.nodes[index].center).distance,
          lessThan(.02),
        );
        expect(
          (after.nodes[index].center - at.nodes[index].center).distance,
          lessThan(.02),
        );
        expect(
          (after.nodes[index].velocity - before.nodes[index].velocity).distance,
          lessThan(.2),
        );
      }
      await disposePendingTotp(tester, pending);
    });

    for (final name in <String>[
      'compression',
      'mid orbit entry',
      'orbit loop',
    ]) {
      testWidgets(
        'success during $name starts from the captured render frame',
        (tester) async {
          final challenge = FakeTotpChallenge();
          final pending = challenge.enqueuePending();
          await tester.pumpWidget(totpTestApp(challenge));
          await tester.pump();
          await tester.enterText(find.byKey(totpCodeInputKey), '123456');
          await tester.tap(find.byKey(totpVerifyButtonKey));
          await tester.pump();
          await driveToResponsePoint(tester, name);
          final before = motionState(tester).debugFrame;
          expect(before.phase, expectedResponsePhase(name));

          pending.complete();
          await tester.pump();
          final handoff = motionState(tester).debugFrame;
          expect(handoff.phase, TotpChallengePhase.success);
          expectFrameContinuity(before, handoff);

          await tester.pump(const Duration(microseconds: 100));
          final moving = motionState(tester).debugFrame;
          for (var index = 0; index < before.nodes.length; index += 1) {
            final incoming = before.nodes[index].velocity;
            final displacement =
                moving.nodes[index].center - before.nodes[index].center;
            if (incoming.distance <= 1) {
              expect(
                displacement.distance,
                lessThanOrEqualTo(.01),
                reason: 'stationary node $index must not jump',
              );
              continue;
            }
            final observed = displacement / .0001;
            final cosine =
                (observed.dx * incoming.dx + observed.dy * incoming.dy) /
                (observed.distance * incoming.distance);
            expect(
              cosine,
              greaterThan(.98),
              reason: 'node $index must preserve its incoming direction',
            );
            expect(
              observed.distance / incoming.distance,
              inInclusiveRange(.75, 1.25),
              reason: 'node $index must preserve practical tangent speed',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets(
      'fast success still morphs round nodes into the six wave bars',
      (tester) async {
        final challenge = FakeTotpChallenge();
        final pending = challenge.enqueuePending();
        await tester.pumpWidget(totpTestApp(challenge));
        await tester.pump();
        await tester.enterText(find.byKey(totpCodeInputKey), '123456');
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        pending.complete();
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 160));
        final roundNodes = motionState(tester).debugFrame.nodes;
        for (final node in roundNodes) {
          expectClose(node.size.width, node.size.height, epsilon: .5);
          expectClose(
            node.cornerRadius,
            math.min(node.size.width, node.size.height) / 2,
            epsilon: .5,
          );
        }

        await tester.pump(const Duration(milliseconds: 180));
        final bars = motionState(tester).debugFrame.nodes;
        const barX = <double>[-42, -26, -9, 9, 26, 42];
        const barHeights = <double>[14, 24, 38, 38, 24, 14];
        final centerX =
            bars.map((node) => node.center.dx).reduce((a, b) => a + b) /
            bars.length;
        for (var index = 0; index < bars.length; index += 1) {
          expectClose(
            bars[index].center.dx - centerX,
            barX[index],
            epsilon: .8,
          );
          expectClose(bars[index].size.width, 7, epsilon: .5);
          expectClose(bars[index].size.height, barHeights[index], epsilon: .8);
        }

        expectClose(motionState(tester).debugSuccessBadgeProgress, 0);
        expect(
          tester.widget<Opacity>(find.byKey(totpSuccessTransitionKey)).opacity,
          0,
        );
        await tester.pump(const Duration(milliseconds: 119));
        expectClose(motionState(tester).debugSuccessBadgeProgress, 0);
        await tester.pump(const Duration(milliseconds: 1));
        expectClose(
          motionState(tester).debugSuccessBadgeProgress,
          0,
          epsilon: .01,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expectClose(
          motionState(tester).debugSuccessBadgeProgress,
          .5,
          epsilon: .02,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expectClose(motionState(tester).debugSuccessBadgeProgress, 1);
        expect(find.byKey(totpSuccessBadgeKey), findsOneWidget);
        expect(find.byKey(totpSuccessCheckKey), findsOneWidget);
        expect(
          tester.getSize(find.byKey(totpSuccessBadgeKey)),
          const Size(56, 56),
        );
        expect(find.byKey(totpInvalidBadgeKey), findsNothing);
        expect(find.byKey(totpInvalidXKey), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('success internal phase splices remain visually C1', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      pending.complete();
      await tester.pump();

      var elapsed = 0;
      for (final boundary in <int>[160, 340, 460]) {
        await tester.pump(Duration(milliseconds: boundary - elapsed - 1));
        final left = motionState(tester).debugFrame;
        await tester.pump(const Duration(milliseconds: 1));
        final at = motionState(tester).debugFrame;
        await tester.pump(const Duration(milliseconds: 1));
        final right = motionState(tester).debugFrame;
        elapsed = boundary + 1;

        for (var index = 0; index < at.nodes.length; index += 1) {
          expect(
            (at.nodes[index].center - left.nodes[index].center).distance,
            lessThan(.5),
            reason: '$boundary ms left splice for node $index',
          );
          expect(
            (right.nodes[index].center - at.nodes[index].center).distance,
            lessThan(.5),
            reason: '$boundary ms right splice for node $index',
          );
          expect(
            (at.nodes[index].size.width - left.nodes[index].size.width).abs(),
            lessThan(.5),
          );
          expect(
            (right.nodes[index].size.width - at.nodes[index].size.width).abs(),
            lessThan(.5),
          );
          expect(at.nodes[index].velocity.distance, lessThan(15));
          expect(right.nodes[index].velocity.distance, lessThan(15));
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final name in <String>[
      'compression',
      'mid orbit entry',
      'orbit loop',
    ]) {
      testWidgets('invalid during $name preserves its captured C1 tangent', (
        tester,
      ) async {
        final challenge = FakeTotpChallenge();
        final pending = challenge.enqueuePending();
        await tester.pumpWidget(totpTestApp(challenge));
        await tester.pump();
        await tester.enterText(find.byKey(totpCodeInputKey), '123456');
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump();
        await driveToResponsePoint(tester, name);
        final before = motionState(tester).debugFrame;
        expect(before.phase, expectedResponsePhase(name));

        pending.completeError(
          FirebaseAuthException(code: 'invalid-verification-code'),
        );
        await tester.pump();
        final handoff = motionState(tester).debugFrame;
        expect(handoff.phase, TotpChallengePhase.error);
        expectFrameContinuity(before, handoff);

        await tester.pump(const Duration(microseconds: 100));
        final moving = motionState(tester).debugFrame;
        for (var index = 0; index < before.nodes.length; index += 1) {
          final incoming = before.nodes[index].velocity;
          final displacement =
              moving.nodes[index].center - before.nodes[index].center;
          if (incoming.distance <= 1) {
            expect(
              displacement.distance,
              lessThanOrEqualTo(.01),
              reason: 'stationary node $index must not jump',
            );
            continue;
          }
          final observed = displacement / .0001;
          final cosine =
              (observed.dx * incoming.dx + observed.dy * incoming.dy) /
              (observed.distance * incoming.distance);
          expect(
            cosine,
            greaterThan(.98),
            reason: 'node $index must preserve its incoming direction',
          );
          expect(
            observed.distance / incoming.distance,
            inInclusiveRange(.75, 1.25),
            reason: 'node $index must preserve practical tangent speed',
          );
        }
        expect(find.byKey(totpSuccessBadgeKey), findsNothing);
        expect(find.byKey(totpSuccessCheckKey), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('invalid uses 100ms colour 240ms return and 360ms shake', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge(
        factors: const <TotpSignInFactor>[
          TotpSignInFactor(uid: 'factor-1', displayName: 'Primary app'),
          TotpSignInFactor(uid: 'factor-2', displayName: 'Backup app'),
        ],
      );
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(totpTestApp(challenge));
      await tester.pump();
      final editing = motionState(tester).debugFrame;
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      await driveToResponsePoint(tester, 'orbit loop');
      pending.completeError(
        FirebaseAuthException(code: 'invalid-verification-code'),
      );
      await tester.pump();

      expectClose(motionState(tester).debugErrorColorProgress, 0);
      await tester.pump(const Duration(milliseconds: 99));
      expect(
        motionState(tester).debugErrorColorProgress,
        inInclusiveRange(.98, 1),
      );
      expect(motionState(tester).debugShakeOffset, 0);
      expect(
        tester.widget<Opacity>(find.byKey(totpInvalidTransitionKey)).opacity,
        inInclusiveRange(.98, 1),
      );
      await tester.pump(const Duration(milliseconds: 1));
      expectClose(motionState(tester).debugErrorColorProgress, 1);

      await tester.pump(const Duration(milliseconds: 20));
      expectClose(
        motionState(tester).debugErrorReturnProgress,
        .5,
        epsilon: .01,
      );
      await tester.pump(const Duration(milliseconds: 119));
      expect(motionState(tester).debugErrorReturnProgress, lessThan(1));
      await tester.pump(const Duration(milliseconds: 1));
      expectClose(motionState(tester).debugErrorReturnProgress, 1);
      final returned = motionState(tester).debugFrame;
      for (var index = 0; index < returned.nodes.length; index += 1) {
        expectOffsetClose(
          returned.nodes[index].center,
          editing.nodes[index].center,
          epsilon: .01,
        );
      }

      await tester.pump(const Duration(milliseconds: 60));
      expectClose(motionState(tester).debugShakeOffset, -7, epsilon: .2);
      await tester.pump(const Duration(milliseconds: 299));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '123456');
      expect(
        tester.widget<TextField>(find.byKey(totpCodeInputKey)).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(totpFactorDropdownKey),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(totpVerifyButtonKey)).onPressed,
        isNull,
      );
      expect(find.byKey(totpInvalidXKey), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(editable.controller.text, isEmpty);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(motionState(tester).debugShakeOffset, 0);
      expect(motionState(tester).debugFrame.phase, TotpChallengePhase.editing);
      expect(find.byKey(totpInvalidBadgeKey), findsNothing);
      expect(find.byKey(totpInvalidXKey), findsNothing);
      expect(challenge.resolveCalls, 1);
    });

    testWidgets(
      'network error returns without shake and preserves six digits',
      (tester) async {
        final challenge = FakeTotpChallenge();
        final pending = challenge.enqueuePending();
        await tester.pumpWidget(totpTestApp(challenge));
        await tester.pump();
        await tester.enterText(find.byKey(totpCodeInputKey), '654321');
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump();
        await driveToResponsePoint(tester, 'orbit loop');
        pending.completeError(
          FirebaseAuthException(code: 'network-request-failed'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(motionState(tester).debugShakeOffset, 0);
        await tester.pump(const Duration(milliseconds: 300));
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.controller.text, '654321');
        expect(editable.focusNode.hasFocus, isTrue);
        expect(
          motionState(tester).debugFrame.phase,
          TotpChallengePhase.editing,
        );
        expect(challenge.resolveCalls, 1);
      },
    );
  });

  group('Voice Constellation reduced motion', () {
    for (final setting
        in <({String name, bool disableAnimations, bool accessibleNavigation})>[
          (
            name: 'disableAnimations',
            disableAnimations: true,
            accessibleNavigation: false,
          ),
          (
            name: 'accessibleNavigation',
            disableAnimations: false,
            accessibleNavigation: true,
          ),
        ]) {
      testWidgets('${setting.name} has a static row and no loop ticker', (
        tester,
      ) async {
        final challenge = FakeTotpChallenge();
        final pending = challenge.enqueuePending();
        await tester.pumpWidget(
          totpTestApp(
            challenge,
            disableAnimations: setting.disableAnimations,
            accessibleNavigation: setting.accessibleNavigation,
          ),
        );
        await tester.pump();
        await tester.enterText(find.byKey(totpCodeInputKey), '123456');
        await tester.tap(find.byKey(totpVerifyButtonKey));
        await tester.pump();

        final before = motionState(tester).debugFrame;
        expect(find.text('Verifying code'), findsOneWidget);
        for (final node in before.nodes) {
          expectClose(node.opacity, .7);
          expectOffsetClose(node.velocity, Offset.zero);
        }
        await tester.pump(const Duration(seconds: 3));
        final after = motionState(tester).debugFrame;
        expectFrameContinuity(before, after);
        await tester.pumpAndSettle(const Duration(milliseconds: 10));
        await disposePendingTotp(tester, pending);
      });
    }

    testWidgets('success is a 120ms crossfade without artificial hold', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      final probe = TotpRouteProbe();
      await tester.pumpWidget(
        totpRouteTestApp(challenge, probe, disableAnimations: true),
      );
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      pending.complete();
      await tester.pump();

      expectClose(motionState(tester).debugSuccessBadgeProgress, 0);
      expect(
        tester.widget<Opacity>(find.byKey(totpSuccessTransitionKey)).opacity,
        0,
      );
      expect(totpCheckPainterProgress(tester), 1);
      expect(find.byKey(totpSuccessHaloKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expectClose(
        motionState(tester).debugSuccessBadgeProgress,
        .5,
        epsilon: .02,
      );
      expect(totpCheckPainterProgress(tester), 1);
      expect(find.byKey(totpSuccessHaloKey), findsNothing);
      final midpoint = motionState(tester).debugFrame;
      for (final node in midpoint.nodes) {
        expectClose(node.opacity, .5, epsilon: .02);
      }
      await tester.pump(const Duration(milliseconds: 59));
      expect(probe.results, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(probe.results, <bool?>[true]);
      expect(probe.challengePops, 1);
    });

    testWidgets('success check stays complete through the reduced crossfade', (
      tester,
    ) async {
      await tester.pumpWidget(
        totpTestApp(FakeTotpChallenge(), disableAnimations: true),
      );
      await tester.pump();

      final completed = motionState(tester).playSuccess();
      await tester.pump();
      expectClose(motionState(tester).debugSuccessBadgeProgress, 0);
      expect(totpCheckPainterProgress(tester), 1);
      expect(find.byKey(totpSuccessHaloKey), findsNothing);

      await tester.pump(const Duration(milliseconds: 120));
      expectClose(motionState(tester).debugSuccessBadgeProgress, 1);
      expect(
        tester.widget<Opacity>(find.byKey(totpSuccessTransitionKey)).opacity,
        1,
      );
      expect(totpCheckPainterProgress(tester), 1);
      expect(find.byKey(totpSuccessHaloKey), findsNothing);
      expect(await completed, isTrue);
    });

    testWidgets('invalid response uses a 100ms colour change without shake', (
      tester,
    ) async {
      final challenge = FakeTotpChallenge();
      final pending = challenge.enqueuePending();
      await tester.pumpWidget(
        totpTestApp(challenge, accessibleNavigation: true),
      );
      await tester.pump();
      await tester.enterText(find.byKey(totpCodeInputKey), '123456');
      await tester.tap(find.byKey(totpVerifyButtonKey));
      await tester.pump();
      final origin = tester.getTopLeft(find.byKey(totpMotionStageKey));
      pending.completeError(
        FirebaseAuthException(code: 'invalid-verification-code'),
      );
      await tester.pump();

      expect(motionState(tester).debugShakeOffset, 0);
      expect(
        tester.widget<Opacity>(find.byKey(totpInvalidTransitionKey)).opacity,
        0,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.widget<Opacity>(find.byKey(totpInvalidTransitionKey)).opacity,
        closeTo(.5, .03),
      );
      expect(motionState(tester).debugShakeOffset, 0);
      await tester.pump(const Duration(milliseconds: 49));
      expect(tester.getTopLeft(find.byKey(totpMotionStageKey)), origin);
      expect(find.byKey(totpInvalidBadgeKey), findsOneWidget);
      expect(find.byKey(totpInvalidXKey), findsOneWidget);
      expect(find.byKey(totpSuccessCheckKey), findsNothing);
      expect(motionState(tester).debugShakeOffset, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      expect(motionState(tester).debugFrame.phase, TotpChallengePhase.editing);
      expect(find.byKey(totpInvalidBadgeKey), findsNothing);
    });
  });
}
