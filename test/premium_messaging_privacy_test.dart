import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/messages/data/models/premium_messaging_privacy.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/settings/data/services/premium_messaging_privacy_service.dart';
import 'package:yovoice/features/settings/presentation/screens/premium_messaging_privacy_screen.dart';

const _uid = 'premium-privacy-owner';

SubscriptionEntitlements _entitlements(bool premium) =>
    SubscriptionEntitlements(
      plan: premium ? PremiumPlan.monthly : PremiumPlan.none,
      status: premium ? 'active' : 'none',
      currentPeriodEnd: premium
          ? DateTime.now().add(const Duration(days: 1))
          : null,
      isPremium: premium,
      creatorEnabled: premium,
      canCreateClubs: premium,
      premiumIdentityEnabled: premium,
      maxOwnedClubs: premium ? 30 : 0,
    );

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(
  PremiumMessagingPrivacyGateway gateway, {
  required bool premium,
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: PremiumMessagingPrivacyScreen(
    service: gateway,
    entitlementStream: Stream.value(_entitlements(premium)),
  ),
);

void main() {
  test('projection distinguishes missing, canonical and malformed state', () {
    expect(
      PremiumMessagingPrivacy.fromMap(null, ownerId: _uid).hideTyping,
      false,
    );
    final canonical = PremiumMessagingPrivacy.fromMap({
      'schemaVersion': 1,
      'ownerId': _uid,
      'hideReadReceipts': true,
      'hideTyping': false,
      'updatedAt': Timestamp.now(),
    }, ownerId: _uid);
    expect(canonical.hideReadReceipts, true);
    expect(
      () => PremiumMessagingPrivacy.fromMap({
        'schemaVersion': 1,
        'ownerId': 'somebody-else',
        'hideReadReceipts': true,
        'hideTyping': true,
        'updatedAt': Timestamp.now(),
      }, ownerId: _uid),
      throwsFormatException,
    );
  });

  test(
    'chat composer uses effective paid state and malformed paid state hides',
    () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _uid),
      );
      final preference = firestore
          .collection('directPrivacyPreferences')
          .doc(_uid);
      final entitlement = firestore.collection('entitlements').doc(_uid);
      await preference.set({
        'schemaVersion': 1,
        'ownerId': _uid,
        'hideReadReceipts': true,
        'hideTyping': true,
        'updatedAt': Timestamp.now(),
      });
      await entitlement.set({
        'isPremium': true,
        'status': 'expired',
        'currentPeriodEnd': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      });
      final service = MessageService(firestore: firestore, auth: auth);
      final expired = await service.watchPremiumMessagingPrivacy().first;
      expect(expired.hideReadReceipts, false);
      expect(expired.hideTyping, false);

      await preference.update({'ownerId': 'somebody-else'});
      await entitlement.set({
        'isPremium': true,
        'status': 'active',
        'currentPeriodEnd': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      });
      final malformedActive = await service
          .watchPremiumMessagingPrivacy()
          .first;
      expect(malformedActive.hideReadReceipts, true);
      expect(malformedActive.hideTyping, true);
      await service.dispose();
    },
  );

  test('service reuses request id after an ambiguous response', () async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid),
    );
    final functions = _PrivacyFunctions(failFirst: true);
    final service = PremiumMessagingPrivacyService(
      firestore: firestore,
      auth: auth,
      functions: functions,
    );
    await service.setPreference(
      PremiumMessagingPrivacyPreference.hideTyping,
      true,
    );
    expect(functions.payloads, hasLength(2));
    expect(
      functions.payloads[0]['requestId'],
      functions.payloads[1]['requestId'],
    );
    expect(functions.payloads[0]['preference'], 'hideTyping');
  });

  test(
    'service rejects a response whose selected switch contradicts enabled',
    () async {
      final service = PremiumMessagingPrivacyService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid)),
        functions: _PrivacyFunctions(contradictSelected: true),
      );
      await expectLater(
        service.setPreference(
          PremiumMessagingPrivacyPreference.hideTyping,
          true,
        ),
        throwsStateError,
      );
    },
  );

  for (final size in [const Size(320, 720), const Size(1100, 820)]) {
    testWidgets(
      'paid privacy remains usable at ${size.width.toInt()} px and 200 percent text',
      (tester) async {
        _surface(tester, size);
        final gateway = _PrivacyGateway();
        await tester.pumpWidget(_app(gateway, premium: true, textScale: 2));
        await tester.pumpAndSettle();
        expect(find.text('Your presence, your choice'), findsOneWidget);
        final typingCard = find.byKey(const ValueKey('hide-typing-control'));
        if (typingCard.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            typingCard,
            240,
            scrollable: find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            ),
          );
        }
        final typingSwitch = find.descendant(
          of: typingCard,
          matching: find.byType(Switch),
        );
        await tester.ensureVisible(typingSwitch);
        await tester.pumpAndSettle();
        await tester.tap(typingSwitch);
        await tester.pumpAndSettle();
        expect(gateway.calls, [
          (PremiumMessagingPrivacyPreference.hideTyping, true),
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('free account sees a clear Premium gate and disabled switches', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    final gateway = _PrivacyGateway();
    await tester.pumpWidget(_app(gateway, premium: false));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('premium-privacy-locked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open-premium-from-privacy')),
      findsOneWidget,
    );
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((control) => control.onChanged == null), true);
  });

  testWidgets('expired Premium shows saved ON as inactive and allows OFF', (
    tester,
  ) async {
    _surface(tester, const Size(390, 844));
    final gateway = _PrivacyGateway()
      ..current = const PremiumMessagingPrivacy(
        hideReadReceipts: true,
        hideTyping: false,
      );
    await tester.pumpWidget(_app(gateway, premium: false));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Saved, but inactive without Premium.'),
      findsOneWidget,
    );
    final readSwitch = find.descendant(
      of: find.byKey(const ValueKey('hide-read-receipts-control')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(readSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(readSwitch).onChanged, isNotNull);
    await tester.tap(readSwitch);
    await tester.pumpAndSettle();
    expect(gateway.calls, [
      (PremiumMessagingPrivacyPreference.hideReadReceipts, false),
    ]);
  });

  test(
    'owner unread projection clears badge without changing public root',
    () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _uid),
      );
      final now = Timestamp.now();
      await firestore.collection('conversations').doc('conversation-1').set({
        'participantIds': [_uid, 'peer'],
        'participantNames': {_uid: 'Owner', 'peer': 'Peer'},
        'participantEmails': {_uid: '', 'peer': ''},
        'participantPhotoUrls': {_uid: '', 'peer': ''},
        'unreadCounts': {_uid: 3, 'peer': 0},
        'lastMessage': 'hello',
        'lastMessageType': 'text',
        'lastMessageSenderId': 'peer',
        'updatedAt': now,
        'createdAt': now,
        'archivedBy': <String>[],
        'mutedBy': <String>[],
      });
      await firestore
          .collection('directConversationUnreadStates')
          .doc('opaque')
          .set({
            'schemaVersion': 1,
            'ownerId': _uid,
            'conversationId': 'conversation-1',
            'unreadCount': 0,
            'updatedAt': now,
          });
      final service = MessageService(firestore: firestore, auth: auth);
      final conversations = await service.watchConversations().first;
      expect(conversations.single.unreadCountFor(_uid), 0);
      final publicRoot = await firestore
          .collection('conversations')
          .doc('conversation-1')
          .get();
      expect((publicRoot.data()!['unreadCounts'] as Map)[_uid], 3);
      await service.dispose();
    },
  );

  test(
    'unavailable unread projection keeps legacy conversation stream usable',
    () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _uid),
      );
      final now = Timestamp.now();
      await firestore.collection('conversations').doc('conversation-1').set({
        'participantIds': [_uid, 'peer'],
        'participantNames': {_uid: 'Owner', 'peer': 'Peer'},
        'participantEmails': {_uid: '', 'peer': ''},
        'participantPhotoUrls': {_uid: '', 'peer': ''},
        'unreadCounts': {_uid: 3, 'peer': 0},
        'lastMessage': 'hello',
        'lastMessageType': 'text',
        'lastMessageSenderId': 'peer',
        'updatedAt': now,
        'createdAt': now,
        'archivedBy': <String>[],
        'mutedBy': <String>[],
      });
      final service = MessageService(
        firestore: firestore,
        auth: auth,
        directUnreadOverridesForTesting: Stream<Map<String, int>>.error(
          StateError('old production rules deny this collection'),
        ),
      );
      final conversations = await service.watchConversations().first;
      expect(conversations.single.unreadCountFor(_uid), 3);
      await service.dispose();
    },
  );

  testWidgets(
    'stream failure has an actionable retry and never renders false switches',
    (tester) async {
      _surface(tester, const Size(390, 844));
      final gateway = _RetryGateway();
      await tester.pumpWidget(_app(gateway, premium: true));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const ValueKey('hide-typing-control')), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hide-typing-control')), findsOneWidget);
    },
  );
}

class _PrivacyGateway implements PremiumMessagingPrivacyGateway {
  final _controller = StreamController<PremiumMessagingPrivacy>.broadcast();
  PremiumMessagingPrivacy current = PremiumMessagingPrivacy.disabled;
  final calls = <(PremiumMessagingPrivacyPreference, bool)>[];

  @override
  Stream<PremiumMessagingPrivacy> watchCurrent() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<void> setPreference(
    PremiumMessagingPrivacyPreference preference,
    bool enabled,
  ) async {
    calls.add((preference, enabled));
    current = PremiumMessagingPrivacy(
      hideReadReceipts:
          preference == PremiumMessagingPrivacyPreference.hideReadReceipts
          ? enabled
          : current.hideReadReceipts,
      hideTyping: preference == PremiumMessagingPrivacyPreference.hideTyping
          ? enabled
          : current.hideTyping,
    );
    _controller.add(current);
  }
}

class _RetryGateway implements PremiumMessagingPrivacyGateway {
  int watches = 0;

  @override
  Stream<PremiumMessagingPrivacy> watchCurrent() {
    watches++;
    return watches == 1
        ? Stream.error(StateError('offline'))
        : Stream.value(PremiumMessagingPrivacy.disabled);
  }

  @override
  Future<void> setPreference(
    PremiumMessagingPrivacyPreference preference,
    bool enabled,
  ) async {}
}

class _PrivacyFunctions implements FirebaseFunctions {
  _PrivacyFunctions({this.failFirst = false, this.contradictSelected = false});

  final bool failFirst;
  final bool contradictSelected;
  final payloads = <Map<String, dynamic>>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable((parameters) async {
        final payload = Map<String, dynamic>.from(parameters as Map);
        payloads.add(payload);
        if (failFirst && payloads.length == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'lost response',
          );
        }
        final selected = payload['preference'] as String;
        final enabled = payload['enabled'] as bool;
        return <Object?, Object?>{
          'preference': selected,
          'enabled': enabled,
          'hideReadReceipts': selected == 'hideReadReceipts' ? enabled : false,
          'hideTyping': selected == 'hideTyping'
              ? (contradictSelected ? !enabled : enabled)
              : false,
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Callable implements HttpsCallable {
  _Callable(this.handler);

  final Future<Object?> Function(Object? parameters) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async =>
      _Result<T>(await handler(parameters) as T);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);

  @override
  final T data;
}
