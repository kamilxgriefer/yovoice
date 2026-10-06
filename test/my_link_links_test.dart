import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_entry_link.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/auth_entry_link.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/moment_links.dart';
import 'package:yovoice/features/moments/presentation/moment_share.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_link_destination_screen.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/profile/data/user_links.dart';
import 'package:yovoice/features/profile/presentation/my_link_copy.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';
import 'package:yovoice/features/servers/data/server_links.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// "Mój link" (ADR-238): the `?user=` and `?moment=` link contracts, what the
/// shell does with them, and the Voice Moment link destination.

const _uid = 'Zx8qT1mVbN4kLp0sWe7uYh2RcA93';

VoiceMoment _moment({String id = 'moment_1', String author = 'Ola Nowak'}) =>
    VoiceMoment(
      id: id,
      authorId: 'ola',
      authorName: author,
      authorPhotoUrl: null,
      caption: 'Poranek nad Wisłą',
      audioUrl: null,
      durationSeconds: 42,
      likeCount: 3,
      commentCount: 1,
      isPublished: true,
      createdAt: DateTime(2026, 10, 3, 9),
      schemaVersion: 2,
      status: 'published',
      hasAuthorizedMedia: true,
    );

const _unsafeIds = <String>[
  '',
  '../private',
  'a/b',
  'a?token=x',
  'a#secret',
  ' a',
  'a ',
  'a\n',
  'a\u0000',
  'żółć',
  'kamil@example.com',
  '+48600100200',
  'https://media.test/x',
];

Widget _app(
  Widget home, {
  Locale locale = const Locale('pl'),
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.darkTheme,
  locale: locale,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  group('profile link (?user=)', () {
    test('is the web app host with exactly one opaque public id', () {
      for (final id in ['A', _uid, 'user_One-7', 'a' * 128]) {
        final link = buildUserLink(id);
        expect(link.toString(), 'https://app.yovoice.app/?user=$id');
        expect(link.queryParametersAll, {
          'user': [id],
        });
        expect(link.hasFragment, isFalse);
        expect(parseUserLink(link), id);
        expect(displayUserLink(link), 'app.yovoice.app/?user=$id');
        expect(
          displayUserLinkBreakable(link),
          'app.yovoice.app/?user=\u200B$id',
        );
      }
    });

    test('never carries an e-mail, a phone number or a malformed id', () {
      for (final id in [..._unsafeIds, 'a' * 129]) {
        expect(isSafeUserLinkId(id), isFalse, reason: id);
        expect(() => buildUserLink(id), throwsArgumentError, reason: id);
        expect(tryBuildUserLink(id), isNull, reason: id);
      }
      expect(tryBuildUserLink(null), isNull);
      expect(tryBuildUserLink(_uid), buildUserLink(_uid));
    });

    test('the parser fails closed on everything but the exact contract', () {
      for (final value in [
        'https://yovoice.app/?user=a',
        'https://www.yovoice.app/?user=a',
        'https://www.app.yovoice.app/?user=a',
        'https://app.yovoice.app.attacker.test/?user=a',
        'https://app.yovoice.app@attacker.test/?user=a',
        'https://user@app.yovoice.app/?user=a',
        'http://app.yovoice.app/?user=a',
        'file:///app.yovoice.app/?user=a',
        'https://app.yovoice.app:8443/?user=a',
        'https://app.yovoice.app/u/a',
        'https://app.yovoice.app/?user=a#token=x',
        'https://app.yovoice.app/?user=a#',
        'https://app.yovoice.app/?user=a&user=b',
        'https://app.yovoice.app/?user=a&user=a',
        'https://app.yovoice.app/?user=a&room=b',
        'https://app.yovoice.app/?user=a&server=b',
        'https://app.yovoice.app/?user=a&page=b',
        'https://app.yovoice.app/?user=a&moment=b',
        'https://app.yovoice.app/?user=a&name=Kamil',
        'https://app.yovoice.app/?user=a&redirect=https%3A%2F%2Fattacker.test',
        'https://app.yovoice.app/?user=',
        'https://app.yovoice.app/?user=%2Fprivate',
        'https://app.yovoice.app/?user=a%0A',
        'https://app.yovoice.app/?user=%FF',
        'https://app.yovoice.app/?user=kamil%40example.com',
        'https://app.yovoice.app/?user=${'x' * 129}',
        'https://app.yovoice.app/?USER=a',
        '/?user=a',
      ]) {
        expect(parseUserLink(Uri.parse(value)), isNull, reason: value);
      }
    });

    test('no other link contract accepts a profile link, and vice versa', () {
      final user = buildUserLink(_uid);
      expect(parseServerLink(user), isNull);
      expect(parseLegacyClubServerLink(user), isNull);
      expect(parsePageLink(user), isNull);
      expect(parseReelLink(user), isNull);
      expect(parseMomentLink(user), isNull);
      expect(parseInitialServerWorkspaceLink(user), isNull);

      for (final other in [
        buildServerLink('srv_1'),
        buildPageLink(_uid),
        buildReelLink('reel_1'),
        buildMomentLink('moment_1'),
        Uri.parse('https://app.yovoice.app/?room=abc'),
      ]) {
        expect(parseUserLink(other), isNull, reason: '$other');
        expect(carriesUserLinkParameters(other), isFalse, reason: '$other');
      }
      expect(carriesUserLinkParameters(user), isTrue);
      expect(
        carriesUserLinkParameters(
          Uri.parse('https://app.yovoice.app/?user=!!&room=abc'),
        ),
        isTrue,
      );
    });
  });

  group('Voice Moment link (?moment=)', () {
    test('is emitted on the web app host, never on the marketing apex', () {
      for (final id in ['A', 'moment_One-7', 'a' * 128]) {
        final link = buildMomentLink(id);
        expect(link.toString(), 'https://app.yovoice.app/?moment=$id');
        expect(link.queryParametersAll, {
          'moment': [id],
        });
        expect(parseMomentLink(link), id);
      }
    });

    test('links shared by older builds on the apex still parse', () {
      for (final host in [
        'app.yovoice.app',
        'yovoice.app',
        'www.yovoice.app',
      ]) {
        expect(
          parseMomentLink(Uri.parse('https://$host/?moment=moment_1')),
          'moment_1',
          reason: host,
        );
      }
    });

    test('invalid ids cannot become share links', () {
      for (final id in [..._unsafeIds, 'a' * 129]) {
        expect(isSafeMomentLinkId(id), isFalse, reason: id);
        expect(() => buildMomentLink(id), throwsArgumentError, reason: id);
      }
    });

    test('the parser fails closed on everything but the exact contract', () {
      for (final value in [
        'https://example.com/?moment=a',
        'https://app.yovoice.app.attacker.test/?moment=a',
        'https://app.yovoice.app@attacker.test/?moment=a',
        'https://user@app.yovoice.app/?moment=a',
        'http://app.yovoice.app/?moment=a',
        'https://app.yovoice.app:8443/?moment=a',
        'https://app.yovoice.app/moments/a',
        'https://app.yovoice.app/?moment=a#token=x',
        'https://app.yovoice.app/?moment=a&moment=b',
        'https://app.yovoice.app/?moment=a&room=b',
        'https://app.yovoice.app/?moment=a&user=b',
        'https://app.yovoice.app/?moment=a&media=https%3A%2F%2Fstorage.test',
        'https://app.yovoice.app/?moment=',
        'https://app.yovoice.app/?moment=%2Fprivate',
        'https://app.yovoice.app/?moment=${'x' * 129}',
        '/?moment=a',
      ]) {
        expect(parseMomentLink(Uri.parse(value)), isNull, reason: value);
      }
      final moment = buildMomentLink('moment_1');
      expect(parseServerLink(moment), isNull);
      expect(parsePageLink(moment), isNull);
      expect(parseReelLink(moment), isNull);
      expect(parseUserLink(moment), isNull);
      expect(carriesMomentLinkParameters(moment), isTrue);
      expect(carriesMomentLinkParameters(buildUserLink(_uid)), isFalse);
    });

    test('sharing a Voice hands over one sentence and the app link', () async {
      const pl = AppLocalizations(Locale('pl'));
      const en = AppLocalizations(Locale('en'));
      const de = AppLocalizations(Locale('de'));
      final moment = _moment();
      expect(
        voiceMomentShareText(pl, moment),
        'Posłuchaj Ola Nowak w YO Voice: '
        'https://app.yovoice.app/?moment=moment_1',
      );
      expect(
        voiceMomentShareText(en, moment),
        'Listen to Ola Nowak on YO Voice: '
        'https://app.yovoice.app/?moment=moment_1',
      );
      expect(
        voiceMomentShareText(de, moment),
        'Hör dir Ola Nowak auf YO Voice an: '
        'https://app.yovoice.app/?moment=moment_1',
      );

      final shared = <ShareParams>[];
      await shareVoiceMoment(
        pl,
        moment,
        shareInvoker: (params) async {
          shared.add(params);
          return const ShareResult('ok', ShareResultStatus.success);
        },
      );
      expect(shared.single.text, voiceMomentShareText(pl, moment));
      expect(shared.single.text, isNot(contains('https://yovoice.app/')));
      expect(shared.single.uri, isNull);
    });

    test('a Voice whose id cannot be a link is never shared', () async {
      const pl = AppLocalizations(Locale('pl'));
      final broken = _moment(id: 'a/b');
      expect(voiceMomentShareText(pl, broken), isNull);
      var calls = 0;
      await shareVoiceMoment(
        pl,
        broken,
        shareInvoker: (params) async {
          calls++;
          return const ShareResult('ok', ShareResultStatus.success);
        },
      );
      expect(calls, 0);
    });
  });

  group('the shell and entry links', () {
    const copy = MyLinkCopy(AppLocalizations(Locale('pl')));

    test('a valid profile or Voice link has nothing to apologise for', () {
      expect(unavailableInitialLinkMessage(buildUserLink(_uid), copy), isNull);
      expect(
        unavailableInitialLinkMessage(buildMomentLink('moment_1'), copy),
        isNull,
      );
    });

    test('an altered profile link is answered honestly and opens nothing', () {
      for (final value in [
        'https://app.yovoice.app/?user=',
        'https://app.yovoice.app/?user=a%2Fb',
        'https://app.yovoice.app/?user=a&room=live_1',
        'https://app.yovoice.app/?user=a&moment=b',
        'https://app.yovoice.app/x?user=a',
      ]) {
        final uri = Uri.parse(value);
        expect(
          unavailableInitialLinkMessage(uri, copy),
          'Ten profil jest niedostępny.',
          reason: value,
        );
        expect(parseUserLink(uri), isNull, reason: value);
        expect(parseMomentLink(uri), isNull, reason: value);
      }
    });

    test('an altered Voice link is answered honestly and opens nothing', () {
      for (final value in [
        'https://app.yovoice.app/?moment=',
        'https://app.yovoice.app/?moment=a%2Fb',
        'https://app.yovoice.app/?moment=a&room=live_1',
        'https://app.yovoice.app/x?moment=a',
      ]) {
        expect(
          unavailableInitialLinkMessage(Uri.parse(value), copy),
          'Ten Moment nie jest już dostępny',
          reason: value,
        );
      }
    });

    test('every other entry URL is left to its own contract', () {
      for (final value in [
        'https://app.yovoice.app/',
        'https://app.yovoice.app/?room=abc',
        'https://app.yovoice.app/?server=srv_1',
        'https://app.yovoice.app/?page=$_uid',
        'https://app.yovoice.app/?reel=reel_1',
      ]) {
        expect(
          unavailableInitialLinkMessage(Uri.parse(value), copy),
          isNull,
          reason: value,
        );
      }
    });

    // A `?user=` link is opened on the shell's first frame — a cold start.
    // The redirect that turns a Page account into its Page ("Obserwuj")
    // reads the cached public badge (or waits 600 ms for it) and this
    // session's Pages answer; neither has landed that early. The shell
    // therefore settles both, bounded, before it opens the profile.
    group('a profile link to an account that runs a Page', () {
      PublicIdentityRepository repository({
        required Future<Map<String, dynamic>> Function(List<String>) fetch,
      }) => PublicIdentityRepository(
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        fetchOverride: fetch,
        flushDelay: Duration.zero,
      );

      test('waits for the badge and then for the Pages answer, so the '
          'redirect finds both', () async {
        final badge = Completer<Map<String, dynamic>>();
        final pages = Completer<bool>();
        final identities = repository(fetch: (_) => badge.future);
        var pagesAsked = 0;
        var settled = false;

        final settle = settlePagesForInitialUserLink(
          userId: _uid,
          resolveIdentity: identities.resolve,
          refreshPages: () {
            pagesAsked++;
            return pages.future;
          },
        ).then((_) => settled = true);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(settled, isFalse, reason: 'the badge has not answered yet');
        expect(pagesAsked, 0);
        expect(identities.peek(_uid), isNull);

        badge.complete(<String, dynamic>{
          _uid: <String, dynamic>{'page': 'business'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(pagesAsked, 1);
        expect(settled, isFalse, reason: 'the Pages answer is still open');

        pages.complete(true);
        await settle;
        expect(settled, isTrue);
        // What the registered redirect reads synchronously afterwards.
        expect(identities.peek(_uid)?.isPage, isTrue);
      });

      test(
        'an ordinary account costs one badge lookup and no Pages wait',
        () async {
          var lookups = 0;
          final identities = repository(
            fetch: (_) async {
              lookups++;
              return const <String, dynamic>{};
            },
          );
          var pagesAsked = 0;
          await settlePagesForInitialUserLink(
            userId: _uid,
            resolveIdentity: identities.resolve,
            refreshPages: () async {
              pagesAsked++;
              return true;
            },
          );
          expect(lookups, 1);
          expect(pagesAsked, 0);
          expect(identities.peek(_uid)?.isPage, isFalse);
        },
      );

      test('a slow or failing badge lookup opens the personal profile '
          'instead of hanging', () async {
        var pagesAsked = 0;
        Future<bool> refreshPages() async {
          pagesAsked++;
          return true;
        }

        final never = Completer<PublicIdentity>();
        await settlePagesForInitialUserLink(
          userId: _uid,
          resolveIdentity: (_) => never.future,
          refreshPages: refreshPages,
          identityBudget: const Duration(milliseconds: 30),
        );
        await settlePagesForInitialUserLink(
          userId: _uid,
          resolveIdentity: (_) =>
              Future<PublicIdentity>.error(StateError('unavailable')),
          refreshPages: refreshPages,
        );
        expect(pagesAsked, 0);
      });

      test('a Pages answer that never arrives is bounded too', () async {
        final never = Completer<bool>();
        await settlePagesForInitialUserLink(
          userId: _uid,
          resolveIdentity: (_) async => const PublicIdentity(
            role: OfficialRole.user,
            isVip: false,
            pageKind: PageKind.community,
          ),
          refreshPages: () => never.future,
          pagesBudget: const Duration(milliseconds: 30),
        );
        await settlePagesForInitialUserLink(
          userId: _uid,
          resolveIdentity: (_) async => const PublicIdentity(
            role: OfficialRole.user,
            isVip: false,
            pageKind: PageKind.community,
          ),
          refreshPages: () => Future<bool>.error(StateError('offline')),
        );
      });

      test('the production budgets stay bounded', () {
        expect(
          initialUserLinkIdentityBudget,
          lessThanOrEqualTo(const Duration(seconds: 5)),
        );
        expect(
          initialUserLinkPagesBudget,
          lessThanOrEqualTo(const Duration(seconds: 8)),
        );
      });
    });

    // On the web the Navigator reports every NAMED top route to the browser
    // and the hash URL strategy writes it into the address. The shell mounts
    // under exactly such routes: `/verify-email` while a new member — the
    // person an invitation link is for — confirms their e-mail address, and
    // `/auth-session` after a sign-out or an account switch.
    group('the address the page was loaded with', () {
      setUp(AppEntryLink.resetForTest);
      tearDown(AppEntryLink.resetForTest);

      const rewritten = <String>[
        'https://app.yovoice.app/?user=$_uid#/verify-email',
        'https://app.yovoice.app/?user=$_uid#/auth-session',
        'https://app.yovoice.app/?moment=moment_1#/verify-email',
      ];

      test('the live address is not the link once a named route is on top: '
          'read then, a valid link would be refused', () {
        for (final value in rewritten) {
          final live = Uri.parse(value);
          expect(parseUserLink(live), isNull, reason: value);
          expect(parseMomentLink(live), isNull, reason: value);
          expect(authEntryLinkOf(live), isNull, reason: value);
        }
      });

      test('a reloaded tab whose address carries the app\'s own route is '
          'not told that the profile is unavailable', () {
        // Still refused (nothing opens, nothing falls through to `room`):
        // the shell returns on the parameter alone. It just says nothing.
        for (final value in [
          ...rewritten,
          'https://app.yovoice.app/?user=$_uid#pages/page/$_uid',
          'https://app.yovoice.app/?moment=a#x',
        ]) {
          final loaded = Uri.parse(value);
          expect(
            unavailableInitialLinkMessage(loaded, copy),
            isNull,
            reason: value,
          );
          expect(
            carriesUserLinkParameters(loaded) ||
                carriesMomentLinkParameters(loaded),
            isTrue,
            reason: value,
          );
        }
      });

      test('the entry link is captured once, before any route exists', () {
        final loaded = buildUserLink(_uid);
        AppEntryLink.capture(loaded);
        // What the address looks like by the time the shell mounts.
        AppEntryLink.capture(Uri.parse(rewritten.first));
        expect(AppEntryLink.pending, loaded);
        expect(parseUserLink(AppEntryLink.pending!), _uid);
        expect(authEntryLinkOf(AppEntryLink.pending!), AuthEntryLink.profile);
      });

      test('the first shell takes it; a later shell in the same tab gets '
          'nothing to open and nothing to apologise for', () {
        AppEntryLink.capture(buildMomentLink('moment_1'));
        final first = AppEntryLink.take();
        expect(parseMomentLink(first!), 'moment_1');
        expect(AppEntryLink.take(), isNull);
        // The sign-in screen stops explaining a link that will not open.
        expect(AppEntryLink.pending, isNull);
      });

      test('the shell and the app are wired to it', () {
        final shell = File(
          'lib/features/home/presentation/screens/main_shell.dart',
        ).readAsStringSync();
        expect(
          shell,
          contains(
            'final entryUri = widget.initialUri ?? AppEntryLink.take();',
          ),
        );
        expect(shell, contains('parseUserLink(entryUri)'));
        expect(shell, contains('parseMomentLink(entryUri)'));
        expect(shell, isNot(contains('parseUserLink(initialUri)')));
        expect(shell, isNot(contains('parseMomentLink(initialUri)')));

        final app = File('lib/app/app.dart').readAsStringSync();
        final capture = app.indexOf('AppEntryLink.capture(Uri.base);');
        expect(capture, greaterThan(0));
        // In the app's first initState, ahead of everything that can push a
        // route.
        expect(capture, lessThan(app.indexOf('_authRouteResetter =')));
        expect(app, contains('AppEntryLink.pending'));
      });
    });

    // The shell also mounts UNDER the pushed "verify your e-mail" route. The
    // profile sheet or the Voice page must not open over that screen (its
    // `popUntil(isFirst)` would discard them unseen); they wait for the
    // shell's own route.
    group('an entry link waits for the shell route', () {
      test('opens at once when the shell route is the visible one', () async {
        final gate = ShellRouteCurrentGate();
        var opened = false;
        await gate.wait(isCurrent: true).then((_) => opened = true);
        expect(opened, isTrue);
        expect(gate.isWaiting, isFalse);
      });

      test(
        'waits under another route and opens when that route closes',
        () async {
          final gate = ShellRouteCurrentGate();
          var opened = 0;
          unawaited(gate.wait(isCurrent: false).then((_) => opened++));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(opened, 0);
          expect(gate.isWaiting, isTrue);

          gate.routeBecameCurrent();
          await Future<void>.delayed(Duration.zero);
          expect(opened, 1);
          expect(gate.isWaiting, isFalse);

          // A later pop (returning from any other route) opens nothing again.
          gate.routeBecameCurrent();
          await Future<void>.delayed(Duration.zero);
          expect(opened, 1);
        },
      );
    });

    test('the Voice link destination is built with the parsed id only', () {
      final id = parseMomentLink(
        Uri.parse('https://app.yovoice.app/?moment=moment_42'),
      );
      expect(initialMomentLinkDestination(id!).momentId, 'moment_42');
    });

    test('a signed-out visitor is told what signing in opens', () {
      expect(authEntryLinkOf(buildUserLink(_uid)), AuthEntryLink.profile);
      expect(
        authEntryLinkOf(buildMomentLink('moment_1')),
        AuthEntryLink.voiceMoment,
      );
      for (final value in [
        'https://app.yovoice.app/',
        'https://app.yovoice.app/?user=a&room=b',
        'https://app.yovoice.app/?server=srv_1',
        'https://evil.test/?user=a',
      ]) {
        expect(authEntryLinkOf(Uri.parse(value)), isNull, reason: value);
      }
      const pl = AppLocalizations(Locale('pl'));
      expect(
        authEntryLinkLine(pl, AuthEntryLink.profile),
        'Zaloguj się, aby zobaczyć ten profil i dodać tę osobę do znajomych.',
      );
      expect(
        authEntryLinkLine(pl, AuthEntryLink.voiceMoment),
        'Zaloguj się, aby posłuchać tego Voice Momentu.',
      );
    });
  });

  group('Voice Moment link destination', () {
    testWidgets('a resolved id opens that Moment', (tester) async {
      final requested = <String>[];
      await tester.pumpWidget(
        _app(
          MomentLinkDestinationScreen(
            momentId: 'moment_1',
            loader: (id) async {
              requested.add(id);
              return _moment();
            },
            detailBuilder: (context, moment) => Scaffold(
              body: Text('detail:${moment.id}:${moment.authorName}'),
            ),
          ),
        ),
      );
      expect(find.text('Ładowanie'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(requested, ['moment_1']);
      expect(find.text('detail:moment_1:Ola Nowak'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-gone')), findsNothing);
    });

    testWidgets('an unknown, private or expired id shows the gone card', (
      tester,
    ) async {
      for (final code in ['not-found', 'permission-denied', 'gone']) {
        await tester.pumpWidget(
          _app(
            MomentLinkDestinationScreen(
              key: ValueKey(code),
              momentId: 'moment_1',
              loader: (id) async =>
                  throw FirebaseFunctionsException(code: code, message: code),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moment-detail-gone')),
          findsOneWidget,
          reason: code,
        );
        expect(find.text('Ten Moment nie jest już dostępny'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('moment-detail-back')),
          findsOneWidget,
        );
        // Nothing to share for a link that did not resolve.
        expect(
          find.byKey(const ValueKey('moment-detail-share-top')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a Moment answered under another id is not shown', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MomentLinkDestinationScreen(
            momentId: 'moment_1',
            loader: (id) async => _moment(id: 'someone_elses'),
            detailBuilder: (context, moment) =>
                const Scaffold(body: Text('detail')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
    });

    testWidgets('a malformed id reads nothing and shows the gone card', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          MomentLinkDestinationScreen(
            momentId: 'a/b',
            loader: (id) async {
              calls++;
              return _moment();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
    });

    testWidgets('a transport failure offers a retry, not a verdict', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _app(
          MomentLinkDestinationScreen(
            momentId: 'moment_1',
            loader: (id) async {
              calls++;
              if (calls == 1) {
                throw FirebaseFunctionsException(
                  code: 'unavailable',
                  message: 'unavailable',
                );
              }
              return _moment();
            },
            detailBuilder: (context, moment) =>
                const Scaffold(body: Text('detail')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('moment-detail-gone')), findsNothing);
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('the gone card fits a 320 px phone at 200 % text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 690);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          textScale: 2,
          MomentLinkDestinationScreen(
            momentId: 'moment_1',
            loader: (id) async => throw FirebaseFunctionsException(
              code: 'not-found',
              message: 'not-found',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
