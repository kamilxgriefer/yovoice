import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "Zacznij tutaj" (firstSteps A) inside `MainShell`.
///
/// `MainShell` cannot be pumped in a widget test (it constructs its Firebase
/// services itself), so what the card and the dead ends do once they are IN
/// the shell is pinned here on the shell's source, the way
/// `test/server_shell_visibility_test.dart` pins the Servers slot. The
/// behaviour behind each line is tested where it can run:
/// `test/first_steps_home_test.dart` (a held card, every step's callback),
/// `test/first_steps_dead_ends_test.dart` (Find Pages host, the Notifications
/// action) and `test/guided_onboarding_offscreen_anchor_test.dart` (the tour).
///
/// `main_shell.dart` is where the build-42 tracks meet. A merge that drops or
/// rewires one of these lines turns a guard below red; if the line was
/// changed on purpose, re-read the reason next to the guard before editing
/// the guard.
String _flattened(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n')
    .replaceAll(RegExp(r'\s+'), ' ');

String _between(String source, String from, String to) {
  final start = source.indexOf(from);
  expect(start, isNot(-1), reason: 'missing: $from');
  final end = source.indexOf(to, start + from.length);
  expect(end, isNot(-1), reason: 'missing after "$from": $to');
  return source.substring(start, end);
}

const _mainShell = 'lib/features/home/presentation/screens/main_shell.dart';

void main() {
  final shell = _flattened(_mainShell);

  const cardWiring =
      'contentEnabled: _startChecklistContent, '
      'onOpenContent: _openContentFromStart, '
      'onAddProfilePhoto: _openEditProfile,';

  group('the five steps lead to the real places', () {
    test('phone Start', () {
      final mobile = _between(
        shell,
        'Widget get _mobileHome => MobileHome(',
        'Widget _desktopHome(',
      );
      // Photo, follow, and the gate that makes the card wait.
      expect(mobile, contains(cardWiring));
      // Friend: the Friends tab.
      expect(
        mobile,
        contains('onOpenFriends: () => _onDestinationSelected(2),'),
      );
      // Server: the Servers tab.
      expect(
        mobile,
        contains('onOpenServers: () => _onDestinationSelected(_serversSlot),'),
      );
      // Voice: the recorder.
      expect(mobile, contains('onCreateMoment: _openCreateMoment,'));
    });

    test('desktop Start', () {
      final desktop = _between(
        shell,
        'Widget _desktopHome(',
        'void _openContentFromStart()',
      );
      expect(desktop, contains(cardWiring));
      expect(
        desktop,
        contains('onViewAllFriends: () => _onDestinationSelected(2),'),
      );
      expect(
        desktop,
        contains('onOpenServers: () => _onDestinationSelected(_serversSlot),'),
      );
      expect(desktop, contains('onCreateMoment: _openCreateMoment,'));
    });

    test('exactly the two Homes are wired, nothing else', () {
      expect(cardWiring.allMatches(shell), hasLength(2));
    });

    test('follow opens Treści, and only while Treści exists', () {
      expect(
        shell,
        contains(
          'void _openContentFromStart() { '
          'if (!_contentEnabled) return; '
          '_onDestinationSelected(_contentSlot); }',
        ),
      );
    });

    test('photo opens the profile editor with the profile the card read', () {
      final editor = _between(
        shell,
        'void _openEditProfile(UserProfile profile) {',
        'Future<void> _openConversation',
      );
      expect(
        editor,
        contains('builder: (_) => EditProfileScreen(profile: profile),'),
      );
    });
  });

  group('the card waits for Pages and for the guided tour', () {
    test('null until both are settled, then the real Pages answer', () {
      expect(
        shell,
        contains(
          'bool? get _startChecklistContent => '
          '_contentKnown && _startChecklistReleased ? _contentEnabled : null;',
        ),
      );
    });

    test('the Pages check marks itself known when it completes or fails', () {
      expect(
        shell,
        contains(
          '_pagesAvailability.refresh(_currentUserId).whenComplete(() { '
          'if (mounted && !_contentKnown) '
          'setState(() => _contentKnown = true); })',
        ),
      );
    });

    test('an account the tour is for keeps the card back until the tour '
        'is finished or skipped', () {
      final prepare = _between(
        shell,
        'Future<void> _prepareGuidedOnboarding() async {',
        'Future<void> _showPendingGuidedOnboarding() async {',
      );
      // Eligible: the tour goes first and this path returns WITHOUT
      // releasing. Not eligible: released at once.
      expect(
        prepare,
        contains(
          'if (eligible) { _onboardingPending = true; '
          'await _showPendingGuidedOnboarding(); return; } '
          '_releaseStartChecklist();',
        ),
      );

      final show = _between(
        shell,
        'Future<void> _showPendingGuidedOnboarding() async {',
        'Future<void> _preparePermissionSetup() async {',
      );
      // Released only once the tour returned an outcome (finished, skipped
      // or Back), never while it is still waiting for its turn.
      expect(
        show,
        contains(
          'final outcome = await _presentGuidedOnboarding(); '
          'if (!mounted || outcome == null) return; '
          '_onboardingPending = false; '
          '_releaseStartChecklist();',
        ),
      );
    });

    test('a failed eligibility check does not keep the card back for good', () {
      expect(
        shell,
        contains(
          '_prepareGuidedOnboarding().whenComplete(() { '
          'if (!_onboardingPending) _releaseStartChecklist(); })',
        ),
      );
    });

    test('there is no other way to release the card', () {
      // Not eligible, tour over, check failed: three call sites.
      expect('_releaseStartChecklist();'.allMatches(shell), hasLength(3));
      expect(
        shell,
        contains(
          'void _releaseStartChecklist() { '
          'if (!mounted || _startChecklistReleased) return; '
          'setState(() => _startChecklistReleased = true); }',
        ),
      );
      // Nothing ever takes the release back within a session.
      expect(
        '_startChecklistReleased = false'.allMatches(shell),
        hasLength(1),
        reason: 'only the field initialiser',
      );
    });
  });

  group('Find Pages from empty Notifications', () {
    test('the shell registers its host and removes it when it goes', () {
      expect(shell, contains('PagesShellBridge.findHost = _hostFindPages;'));
      expect(
        shell,
        contains(
          'if (PagesShellBridge.findHost == _hostFindPages) { '
          'PagesShellBridge.findHost = null; }',
        ),
      );
    });

    test('it is hosted in the shell chrome on the Treści destination, and '
        'only while Treści exists', () {
      final host = _between(
        shell,
        'Future<void> _hostFindPages(BuildContext context) async {',
        'await _pushHostedDestination(route); }',
      );
      expect(host, contains('if (!mounted || !_contentEnabled) return;'));
      expect(host, contains("RouteSettings(name: 'pages/find')"));
      expect(host, contains('body: const FindPagesHost(),'));
      expect(host, contains('selectedIndex: _contentSlot,'));
      expect(host, contains('activeDesktopItem: DesktopNavItem.content,'));
    });
  });
}
