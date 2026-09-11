import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club_channel.dart';
import 'package:yovoice/features/clubs/presentation/screens/club_chat_screen.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_message_controller.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_chat_sheet.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/inputs/yo_composer_panel.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_picker.dart';
import 'package:yovoice/shared/widgets/media/yo_gif_view.dart';

import 'support/fake_gif_transport.dart';

const _capture = bool.fromEnvironment('CAPTURE_GIF');
final _boundary = GlobalKey();

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late PublicIdentityRepository identities;
  late AppPreferencesController preferences;
  late GifCatalogService catalog;
  late MessageService messages;

  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))
      ..addFont(rootBundle.load('assets/fonts/InterVariable-Italic.ttf'));
    await inter.load();
    final unicode = File(
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    if (unicode.existsSync()) {
      await (FontLoader('Arial Unicode MS')..addFont(
            Future.value(ByteData.sublistView(unicode.readAsBytesSync())),
          ))
          .load();
    }
    if (!_capture) return;
    var directory = File(Platform.resolvedExecutable).parent;
    while (directory.parent.path != directory.path) {
      final path =
          '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
      if (File(path).existsSync()) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          );
        await icons.load();
        break;
      }
      directory = directory.parent;
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await YoComposerPanelTabStore.instance.remember(YoComposerPanelTab.emoji);
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', isEmailVerified: true),
    );
    identities = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth,
      fetchOverride: (uids) async => {
        for (final uid in uids)
          uid: {'uid': uid, 'staffRole': 'user', 'isVip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
    preferences = AppPreferencesController(
      store: SharedPreferencesAppPreferencesStore(),
      initialValue: const AppPreferences(gifAutoLoadEnabled: false),
    );
    catalog = GifCatalogService(transport: FakeGifTransport());
    messages = _Messages(db, auth);
    await db.doc('clubs/club').set({'ownerId': 'me', 'name': 'Club'});
    await db.doc('clubs/club/members/me').set({
      'userId': 'me',
      'role': 'owner',
    });
  });

  tearDown(() async {
    PublicIdentityRepository.instance = identities;
    catalog.dispose();
    preferences.dispose();
    await messages.dispose();
  });

  String path(String surface) => switch (surface) {
    'direct' => 'conversations/chat/messages/received',
    'room' => 'rooms/room/messages/received',
    _ => 'clubs/club/channels/general/messages/received',
  };
  Map<String, Object?> wire({bool deleted = false}) => {
    'conversationId': 'chat',
    'type': 'gif',
    'gif': FakeGifTransport.defaultAssets.first.toWire(),
    'senderId': 'other',
    'senderName': 'A member',
    'content': 'GIF: Happy cat',
    'text': 'GIF: Happy cat',
    'sentAt': Timestamp.now(),
    'createdAt': Timestamp.now(),
    'isDeleted': deleted,
    'readBy': ['me'],
    'reactions': <String, String>{},
  };

  Widget host(
    String surface, {
    GifMessageInvoker? invoke,
    bool light = false,
    double textScale = 1,
    Locale locale = const Locale('en'),
  }) {
    final Widget screen = switch (surface) {
      'direct' => ChatScreen(
        conversationId: 'chat',
        otherUserId: 'other',
        otherDisplayName: 'A member',
        otherEmail: '',
        otherPhotoUrl: '',
        messageService: messages,
        firestore: db,
        auth: auth,
        gifService: catalog,
        gifMessageInvoker: invoke,
      ),
      'room' => Scaffold(
        body: RoomChatPanel(
          roomId: 'room',
          isHost: true,
          accent: Colors.purple,
          currentUserId: 'me',
          service: RoomService(firestore: db, auth: auth),
          gifService: catalog,
          gifMessageInvoker: invoke,
        ),
      ),
      _ => ClubChatScreen(
        clubId: 'club',
        clubName: 'Club',
        channel: const ClubChannel(
          id: 'general',
          clubId: 'club',
          name: 'General',
          type: ClubChannelType.chat,
          position: 0,
          isPrivate: false,
          createdBy: 'me',
          createdAt: null,
        ),
        firestore: db,
        auth: auth,
        gifService: catalog,
        gifMessageInvoker: invoke,
      ),
    };
    return AppPreferencesScope(
      controller: preferences,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: RepaintBoundary(key: _boundary, child: screen),
      ),
    );
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      final boundary =
          _boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/gif-integration-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final surface in ['direct', 'room', 'club']) {
    testWidgets(
      '$surface receives canonical GIFs without provider contact when auto-load is off',
      (tester) async {
        await db.doc(path(surface)).set(wire());
        for (final light in [false, true]) {
          for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0]) {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpWidget(host(surface, light: light));
            await tester.pumpAndSettle();
            expect(find.byType(YoGifView), findsOneWidget);
            expect(find.byKey(const ValueKey('gif-view-load')), findsOneWidget);
            expect(
              find.byWidgetPredicate(
                (w) => w is Image && w.image is NetworkImage,
              ),
              findsNothing,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$surface $width $light',
            );
            if (width == 320 || width == 1440) {
              await shot(
                tester,
                '$surface-${width.toInt()}-${light ? 'pearl' : 'dark'}',
              );
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
        tester.view.reset();
      },
    );

    testWidgets('$surface tombstone cannot load a retained GIF', (
      tester,
    ) async {
      await db.doc(path(surface)).set(wire(deleted: true));
      await tester.pumpWidget(host(surface));
      await tester.pumpAndSettle();
      expect(find.byType(YoGifView), findsNothing);
      expect(find.text('Message deleted'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '$surface picker sends, shows pending and retries the identical request',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 900);
        addTearDown(tester.view.reset);
        final attempts = <Map<String, Object?>>[];
        final first = Completer<Object?>();
        final target = switch (surface) {
          'direct' => {'conversationId': 'chat'},
          'room' => {'roomId': 'room'},
          _ => {'clubId': 'club', 'channelId': 'general'},
        };
        await tester.pumpWidget(
          host(
            surface,
            invoke: (name, payload) async {
              expect(name, switch (surface) {
                'direct' => 'sendDirectMessage',
                'room' => 'sendRoomMessage',
                _ => 'sendClubMessage',
              });
              attempts.add(payload);
              if (attempts.length == 1) return first.future;
              await db.doc(path(surface)).set(wire());
              return {...target, 'messageId': 'received'};
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('composer-panel-tab-gif')));
        await tester.pumpAndSettle();
        expect(find.byType(YoGifPicker), findsOneWidget);
        // Exercise the installed picker's selection callback; privacy-off tiles
        // deliberately reserve their first tap for opting into the CDN request.
        tester
            .widget<YoGifPicker>(find.byType(YoGifPicker))
            .onSelected(FakeGifTransport.defaultAssets.first);
        await tester.pump();
        expect(find.byKey(const ValueKey('gif-send-status')), findsOneWidget);
        expect(find.textContaining('Sending…'), findsOneWidget);
        expect(attempts.single.keys.toSet(), {
          ...target.keys,
          'requestId',
          'gif',
        });
        first.completeError(TimeoutException('offline'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Retry'), findsOneWidget);
        await shot(tester, '$surface-retry');
        await tester.tap(find.byTooltip('Retry'));
        await tester.pumpAndSettle();
        expect(attempts, hasLength(2));
        expect(attempts[1], attempts[0]);
        expect(find.byKey(const ValueKey('gif-send-status')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('$surface received GIF fits 200 percent text and RTL', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.reset);
      await db.doc(path(surface)).set(wire());
      await tester.pumpWidget(
        host(surface, textScale: 2, locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(YoGifView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, '$surface-rtl-large');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('ranked caught-up state fits each layout at 200 percent text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [320.0, 768.0, 1440.0]) {
      for (final light in [false, true]) {
        tester.view.physicalSize = Size(width, 900);
        final service = ReelService(
          auth: auth,
          callableInvoker: (_, payload) async => {
            'schemaVersion': 2,
            'nextCursor': null,
            'items': [
              if (payload['includeSeen'] == true)
                {
                  'id': 'seen',
                  'authorId': 'other',
                  'authorName': 'A member',
                  'media': {
                    'kind': 'video',
                    'contentType': 'video/mp4',
                    'size': 4096,
                    'generation': '7',
                    'durationMs': 10000,
                  },
                  'backingAudio': null,
                  'composition': const ReelComposition(
                    trimStartMs: 0,
                    trimEndMs: 10000,
                  ).toWire(),
                  'publishedAtMillis': 1725000000000,
                  'sortKey': '1725000000000_seen',
                  'availability': {
                    'schemaVersion': 1,
                    'availabilityHours': 'permanent',
                    'expiresAtMillis': null,
                  },
                },
            ],
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: _boundary,
              child: ReelsFeedScreen(service: service),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('You’re all caught up'), findsOneWidget);
        expect(find.text('Watch again'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shot(
          tester,
          'reels-caught-up-${width.toInt()}-${light ? 'pearl' : 'dark'}',
        );
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
    'unconfigured GIF service remains honest in localized chat panels',
    (tester) async {
      catalog.dispose();
      catalog = GifCatalogService(
        transport: FakeGifTransport(
          catalogResult: const GifCatalog.unavailable(
            GifUnavailableReason.notConfigured,
          ),
        ),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      for (final surface in ['direct', 'room', 'club']) {
        for (final locale in [const Locale('pl'), const Locale('ar')]) {
          await YoComposerPanelTabStore.instance.remember(
            YoComposerPanelTab.gif,
          );
          await tester.pumpWidget(host(surface, textScale: 2, locale: locale));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('emoji-picker-toggle')));
          await tester.pumpAndSettle();
          final copy = AppLocalizations(locale);
          if (surface == 'direct') {
            final header = find.byKey(const ValueKey('chat-header'));
            final name = find.descendant(
              of: header,
              matching: find.text('A member'),
            );
            final paragraph = tester.renderObject<RenderParagraph>(name);
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: 'identity must remain readable beside call actions',
            );
            for (final label in [
              copy.text('USER', 'UŻYTKOWNIK'),
              copy.text('Offline', 'Nieaktywny'),
            ]) {
              final metadata = find.descendant(
                of: header,
                matching: find.text(label),
              );
              expect(
                tester
                    .renderObject<RenderParagraph>(metadata)
                    .didExceedMaxLines,
                isFalse,
                reason:
                    'ordinary role and presence must remain readable: $label',
              );
            }
            for (final tooltip in [
              copy.text('Back to chats', 'Wróć do czatów'),
              copy.text('Start voice call', 'Rozpocznij połączenie głosowe'),
              copy.text('Start video call', 'Rozpocznij połączenie wideo'),
              copy.text('Conversation options', 'Opcje rozmowy'),
            ]) {
              final action = find.byTooltip(tooltip);
              expect(action.hitTestable(), findsOneWidget);
              expect(
                tester.getSize(action).shortestSide,
                greaterThanOrEqualTo(44),
              );
            }
          }
          expect(
            find.text(
              copy.text(
                "GIFs aren't available yet",
                'GIF-y nie są jeszcze dostępne',
              ),
            ),
            findsOneWidget,
          );
          expect(find.byType(YoGifView), findsNothing);
          await shot(
            tester,
            '$surface-unconfigured-${locale.languageCode}-large',
          );
          expect(tester.takeException(), isNull, reason: '$surface $locale');
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
}

class _Messages extends MessageService {
  _Messages(this.db, MockFirebaseAuth auth) : super(firestore: db, auth: auth);
  final FakeFirebaseFirestore db;
  @override
  Stream<List<Message>> watchMessages(String conversationId) => db
      .collection('conversations/chat/messages')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Message.fromFirestore).toList());
  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream.value(false);
  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream.value(const ChatPresence(isOnline: false, lastSeen: null));
  @override
  Future<void> markConversationRead(String conversationId) async {}
  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
