import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/auth/presentation/screens/totp_challenge_screen.dart';

const totpCodeInputKey = ValueKey<String>('totp-code-input');
const totpFactorDropdownKey = ValueKey<String>('totp-factor-dropdown');
const totpVerifyButtonKey = ValueKey<String>('totp-verify-button');
const totpMotionStageKey = ValueKey<String>('totp-motion-stage');
const totpStatusChannelKey = ValueKey<String>('totp-status-channel');
const totpLogoKey = ValueKey<String>('totp-logo');
const totpSuccessBadgeKey = ValueKey<String>('totp-success-badge');
const totpSuccessHaloKey = ValueKey<String>('totp-success-halo');
const totpSuccessCheckKey = ValueKey<String>('totp-success-check');
const totpSuccessTransitionKey = ValueKey<String>('totp-success-transition');
const totpInvalidBadgeKey = ValueKey<String>('totp-invalid-badge');
const totpInvalidXKey = ValueKey<String>('totp-invalid-x');
const totpInvalidTransitionKey = ValueKey<String>('totp-invalid-transition');
const totpErrorCardKey = ValueKey<String>('totp-error-card');

ValueKey<String> totpDigitCellKey(int index) =>
    ValueKey<String>('totp-digit-cell-$index');

ValueKey<String> totpNodeKey(int index) => ValueKey<String>('totp-node-$index');

@immutable
class TotpResolveCall {
  const TotpResolveCall({required this.factorUid, required this.code});

  final String factorUid;
  final String code;
}

typedef TotpResolveHandler = Future<void> Function(TotpResolveCall call);

/// Deterministic challenge fake for debounce, single-flight and phase tests.
///
/// Calls are captured synchronously before a scripted Future is awaited. This
/// lets a test prove that UI motion never delays the Firebase boundary.
class FakeTotpChallenge implements TotpSignInChallengeClient {
  FakeTotpChallenge({
    List<TotpSignInFactor>? factors,
    Iterable<TotpResolveHandler> outcomes = const <TotpResolveHandler>[],
  }) : factors =
           factors ??
           const <TotpSignInFactor>[
             TotpSignInFactor(
               uid: 'factor-1',
               displayName: 'Authenticator app',
             ),
           ],
       _outcomes = Queue<TotpResolveHandler>.of(outcomes);

  @override
  final List<TotpSignInFactor> factors;

  final Queue<TotpResolveHandler> _outcomes;
  final List<TotpResolveCall> calls = <TotpResolveCall>[];

  int get resolveCalls => calls.length;
  TotpResolveCall? get lastCall => calls.isEmpty ? null : calls.last;

  void enqueueSuccess() {
    _outcomes.add((_) async {});
  }

  void enqueueError(Object error, [StackTrace? stackTrace]) {
    _outcomes.add((_) => Future<void>.error(error, stackTrace));
  }

  Completer<void> enqueuePending() {
    final completer = Completer<void>();
    _outcomes.add((_) => completer.future);
    return completer;
  }

  void enqueue(TotpResolveHandler handler) {
    _outcomes.add(handler);
  }

  @override
  Future<void> resolve({
    required String factorUid,
    required String code,
  }) async {
    final call = TotpResolveCall(factorUid: factorUid, code: code);
    calls.add(call);
    if (_outcomes.isEmpty) return;
    await _outcomes.removeFirst()(call);
  }
}

class TotpRouteProbe {
  final List<bool?> results = <bool?>[];
  int challengePops = 0;
}

class _TotpNavigatorObserver extends NavigatorObserver {
  _TotpNavigatorObserver(this.probe);

  final TotpRouteProbe probe;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == '/totp-challenge') {
      probe.challengePops += 1;
    }
    super.didPop(route, previousRoute);
  }
}

class _TotpRouteLauncher extends StatefulWidget {
  const _TotpRouteLauncher({required this.challenge, required this.probe});

  final TotpSignInChallengeClient challenge;
  final TotpRouteProbe probe;

  @override
  State<_TotpRouteLauncher> createState() => _TotpRouteLauncherState();
}

class _TotpRouteLauncherState extends State<_TotpRouteLauncher> {
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final result = await Navigator.of(context).push<bool>(
          PageRouteBuilder<bool>(
            settings: const RouteSettings(name: '/totp-challenge'),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) =>
                TotpChallengeScreen(challenge: widget.challenge),
          ),
        );
        widget.probe.results.add(result);
      });
    }
    return const ColoredBox(color: Colors.black);
  }
}

Widget totpTestApp(
  TotpSignInChallengeClient challenge, {
  ThemeData? theme,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewInsets = EdgeInsets.zero,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  locale: locale,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
      textScaler: textScaler,
      viewInsets: viewInsets,
    ),
    child: child!,
  ),
  home: TotpChallengeScreen(challenge: challenge),
);

Widget totpRouteTestApp(
  TotpSignInChallengeClient challenge,
  TotpRouteProbe probe, {
  ThemeData? theme,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewInsets = EdgeInsets.zero,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  locale: locale,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  navigatorObservers: <NavigatorObserver>[_TotpNavigatorObserver(probe)],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: disableAnimations,
      accessibleNavigation: accessibleNavigation,
      textScaler: textScaler,
      viewInsets: viewInsets,
    ),
    child: child!,
  ),
  home: _TotpRouteLauncher(challenge: challenge, probe: probe),
);

void useTotpSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> disposePendingTotp(
  WidgetTester tester,
  Completer<void> pending,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  if (!pending.isCompleted) pending.complete();
  await tester.pump();
}

List<Map<Object?, Object?>> captureTotpAnnouncements(WidgetTester tester) {
  final captured = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (Object? message) async {
      if (message is Map && message['type'] == 'announce') {
        captured.add(message['data'] as Map<Object?, Object?>);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return captured;
}

bool isAssertiveAnnouncement(Map<Object?, Object?> announcement) =>
    announcement['assertiveness'] == Assertiveness.assertive.index;

String announcementMessage(Map<Object?, Object?> announcement) =>
    announcement['message'] as String;

double totpCheckPainterProgress(WidgetTester tester) {
  final customPaint = tester.widget<CustomPaint>(
    find.byKey(totpSuccessCheckKey),
  );
  final dynamic painter = customPaint.painter;
  return painter.progress as double;
}

List<SemanticsNode> totpLiveRegions(WidgetTester tester) {
  return _totpSemanticsNodes(
    tester,
    (data) => data.flagsCollection.isLiveRegion,
  );
}

List<SemanticsNode> totpTextFields(WidgetTester tester) {
  return _totpSemanticsNodes(
    tester,
    (data) => data.flagsCollection.isTextField,
  );
}

List<SemanticsNode> totpNodesWithLabel(WidgetTester tester, String label) {
  return _totpSemanticsNodes(tester, (data) => data.label == label);
}

List<SemanticsNode> _totpSemanticsNodes(
  WidgetTester tester,
  bool Function(SemanticsData data) matches,
) {
  final found = <SemanticsNode>[];

  void visit(SemanticsNode node) {
    if (matches(node.getSemanticsData())) {
      found.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  SemanticsNode? root;
  void visitOwner(PipelineOwner owner) {
    root ??= owner.semanticsOwner?.rootSemanticsNode;
    owner.visitChildren(visitOwner);
  }

  visitOwner(tester.binding.rootPipelineOwner);
  if (root != null) visit(root!);
  return found;
}
