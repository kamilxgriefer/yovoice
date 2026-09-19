// Developer-only VISUAL capture for server deletion: the directory's row
// actions and action sheet, the type-the-name confirmation (plain and with a
// live conversation), the management sheet's danger zone and the labelled
// settings entry, Dark and Pearl, pl, phone / tablet / desktop.
//
// Not a golden test. Run explicitly:
//
//   flutter test test/server_delete_capture.dart --concurrency=1
//
// PNGs land in yovoice-evidence/2026-09-19/server-delete-frames/.
// Layout exceptions are recorded in _exceptions.log next to the frames.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/server_workspace_screen.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';

import 'server_test_support.dart';

const _outputDirectory =
    '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-19/'
    'server-delete-frames';

final _exceptions = File('$_outputDirectory/_exceptions.log');

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

ByteData _read(String path) =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadRealFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(Future.value(_read('assets/fonts/InterVariable.ttf')));
  await inter.load();
  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(Future.value(_read('$_fontRoot/$face')));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(_read('$_fontRoot/MaterialIcons-Regular.otf')));
  await icons.load();
}

Server _server(
  String id,
  String name,
  ServerType type, {
  int members = 8,
  String description = '',
  ServerMemberRole role = ServerMemberRole.owner,
}) => Server(
  id: id,
  name: name,
  description: description,
  ownerId: role == ServerMemberRole.owner ? 'owner' : 'someone-else',
  type: type,
  privacy: ServerPrivacy.private,
  memberCount: members,
  schemaVersion: 1,
  activationState: 'active',
  status: 'active',
  directoryRole: role,
);

List<Server> _servers() => [
  _server('s', 'Ekipa z podwórka', ServerType.friends, members: 12),
  _server(
    'k',
    'Klub książki',
    ServerType.community,
    members: 184,
    description: 'Co miesiąc jedna książka i jedna długa rozmowa o niej.',
    role: ServerMemberRole.member,
  ),
  _server('r', 'Rodzina Nowaków', ServerType.family, members: 6),
];

TestServerRepository _repository({bool live = false}) => TestServerRepository()
  ..servers = _servers()
  ..members = const [
    ServerMember(
      id: 'owner',
      displayName: 'Kamil',
      role: ServerMemberRole.owner,
      authorizationRevision: 1,
    ),
  ]
  ..channels = [
    const ServerChannel(
      id: 'general',
      serverId: 's',
      name: 'ogólny',
      kind: ServerChannelKind.text,
      schemaVersion: 1,
    ),
    ServerChannel(
      id: 'voice',
      serverId: 's',
      name: 'Pokój',
      kind: ServerChannelKind.voice,
      schemaVersion: 1,
      activeSessionId: live ? 'gen-1' : null,
      liveness: live
          ? ServerChannelLiveness(
              isLive: true,
              startedAt: DateTime(2026, 9, 19, 19, 40),
            )
          : const ServerChannelLiveness(),
    ),
  ];

Future<void> _render(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required Size size,
  required Widget child,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('pl'),
        theme: theme,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(size: size, disableAnimations: true),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle();
  } on Object {
    for (var pump = 0; pump < 6; pump++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }
}

Future<void> _shoot(
  WidgetTester tester, {
  required GlobalKey captureKey,
  required String name,
  required double width,
}) async {
  final failure = tester.takeException();
  if (failure != null) {
    final headline = failure.toString().split('\n').take(2).join(' | ');
    _exceptions.writeAsStringSync(
      '$name :: $headline\n',
      mode: FileMode.append,
    );
  }
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: width <= 768 ? 2 : 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDirectory/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await _loadRealFonts();
    Directory(_outputDirectory).createSync(recursive: true);
    if (_exceptions.existsSync()) _exceptions.deleteSync();
  });

  for (final (width, height) in const [
    (390.0, 844.0),
    (768.0, 1024.0),
    (1440.0, 900.0),
  ]) {
    for (final (themeLabel, light) in const [
      ('dark', false),
      ('pearl', true),
    ]) {
      final suffix = '${width.toInt()}x${height.toInt()}-$themeLabel-pl';
      final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;

      testWidgets('directory $suffix', (tester) async {
        final captureKey = GlobalKey();
        await _render(
          tester,
          captureKey: captureKey,
          size: Size(width, height),
          theme: theme,
          child: ServersScreen(
            isRootTab: true,
            repository: _repository(live: true),
            onOpenServer: (_) {},
          ),
        );
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'directory-$suffix',
          width: width,
        );
        await tester.tap(
          find.byKey(const ValueKey('server-directory-actions-s')),
        );
        await _settle(tester);
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'directory-sheet-owner-$suffix',
          width: width,
        );
        await tester.tap(find.byKey(const ValueKey('server-directory-delete')));
        await _settle(tester);
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'delete-dialog-live-$suffix',
          width: width,
        );
        await tester.enterText(
          find.byKey(const ValueKey('server-delete-confirm-field')),
          'Ekipa z podwórka',
        );
        await _settle(tester);
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'delete-dialog-typed-$suffix',
          width: width,
        );
        await tester.tap(find.byKey(const ValueKey('server-delete-cancel')));
        await _settle(tester);
        await tester.tap(
          find.byKey(const ValueKey('server-directory-actions-k')),
        );
        await _settle(tester);
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'directory-sheet-member-$suffix',
          width: width,
        );
      });

      testWidgets('workspace settings $suffix', (tester) async {
        final captureKey = GlobalKey();
        await _render(
          tester,
          captureKey: captureKey,
          size: Size(width, height),
          theme: theme,
          child: ServerWorkspaceScreen(
            serverId: 's',
            repository: _repository(),
            isRootTab: true,
            channelBuilder: (_, _, _) => const SizedBox(),
          ),
        );
        if (width < 768) {
          await tester.tap(find.byKey(const ValueKey('server-open-channels')));
          await _settle(tester);
        }
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'panel-settings-$suffix',
          width: width,
        );
        await tester.tap(find.byKey(const ValueKey('server-manage-action')));
        await _settle(tester);
        final zone = find.byKey(const ValueKey('server-danger-zone'));
        await tester.scrollUntilVisible(
          zone,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('server-management-overview')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _settle(tester);
        await _shoot(
          tester,
          captureKey: captureKey,
          name: 'danger-zone-$suffix',
          width: width,
        );
      });
    }
  }
}
