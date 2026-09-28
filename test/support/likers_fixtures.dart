import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/likers/data/services/likers_access_service.dart';
import 'package:yovoice/features/likers/data/services/likers_service.dart';
import 'package:yovoice/features/likers/presentation/likers_launcher.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// A valid 43-character opaque cursor.
const String kTestCursor = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String kTestCursor2 = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

Map<String, Object?> likerWire(String uid, String name, {String? reaction}) =>
    <String, Object?>{
      'userId': uid,
      'displayName': name,
      'photoUrl': null,
      'reaction': reaction,
    };

Map<String, Object?> pageWire(
  List<Map<String, Object?>> likers, {
  String? cursor,
}) => <String, Object?>{
  'schemaVersion': 1,
  'likers': likers,
  'nextCursor': cursor,
  'hasMore': cursor != null,
};

FirebaseFunctionsException functionsError(String code, {String? reason}) =>
    FirebaseFunctionsException(
      message: code,
      code: code,
      details: reason == null ? null : <String, Object?>{'reason': reason},
    );

/// One recorded callable invocation.
class LikersCall {
  const LikersCall(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

/// A scripted [LikersCallableInvoker]: each call takes the next response —
/// a response map, an exception to throw, or a [Completer] to await.
class ScriptedLikers {
  ScriptedLikers(List<Object?> responses) : _responses = [...responses];

  final List<Object?> _responses;
  final List<LikersCall> calls = <LikersCall>[];

  void add(Object? response) => _responses.add(response);

  Future<Object?> call(String name, Map<String, Object?> payload) async {
    calls.add(LikersCall(name, Map<String, Object?>.of(payload)));
    if (_responses.isEmpty) {
      throw StateError('No scripted likers response for call ${calls.length}');
    }
    final next = _responses.removeAt(0);
    if (next is Completer<Object?>) return next.future;
    if (next is Exception || next is Error) throw next as Object;
    return next;
  }

  LikersService get service => LikersService(invoker: call);
}

PublicIdentityRepository identityRepository({Set<String> vip = const {}}) =>
    PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids)
          uid: <String, dynamic>{
            'uid': uid,
            'staffRole': 'user',
            'isVip': vip.contains(uid),
          },
      },
      flushDelay: const Duration(milliseconds: 1),
    );

Widget likersHost(
  Widget child, {
  bool pearl = false,
  Locale locale = const Locale('en'),
  double textScale = 1,
  TextDirection? direction,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, inner) {
    Widget result = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: inner!,
    );
    if (direction != null) {
      result = Directionality(textDirection: direction, child: result);
    }
    return result;
  },
  home: child,
);

/// A pre-gate that answers [allowed] from both the cached stream and the
/// fresh re-read, with no Firebase behind it.
class FakeLikersAccess extends LikersAccessService {
  FakeLikersAccess(this.allowed);

  final bool allowed;

  @override
  Stream<bool> watchCanSeeLikers() => Stream<bool>.value(allowed);

  @override
  Future<bool> canSeeLikers() async => allowed;
}

/// A [LikersLauncher] for a host surface's own widget tests: [allowed]
/// decides list (VIP) or upsell (U1); [script] answers the list callable.
LikersLauncher testLikersLauncher({
  required bool allowed,
  required ScriptedLikers script,
}) => LikersLauncher(
  access: FakeLikersAccess(allowed),
  service: script.service,
  viewerId: 'me',
  identityRepository: identityRepository(),
);

/// The list sheet (owner variant B) is on screen.
const ValueKey<String> kLikersListSurface = ValueKey<String>(
  'likers-sheet-surface',
);

/// The non-VIP upsell (owner variant U1) is on screen.
const ValueKey<String> kLikersUpsellSurface = ValueKey<String>(
  'likers-upsell-surface',
);
