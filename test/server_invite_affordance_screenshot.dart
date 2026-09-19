// Developer-only visual QA harness for who is offered `Zaproś`.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/server_invite_affordance_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

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
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_template.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_panel.dart';

final _capture = GlobalKey();

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
  await (FontLoader('Inter')..addFont(
        Future.value(
          ByteData.view(
            Uint8List.fromList(
              File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
            ).buffer,
          ),
        ),
      ))
      .load();
}

Server _server(ServerType type, ServerPrivacy privacy) => Server(
  id: 's',
  name: 'Po godzinach',
  description: '',
  ownerId: 'owner',
  type: type,
  privacy: privacy,
  memberCount: 12,
  schemaVersion: 1,
  activationState: 'active',
);

List<ServerChannel> _channels(ServerType type) {
  final seeds = serverTemplateChannelsFor(type);
  return [
    for (var i = 0; i < seeds.length; i++)
      ServerChannel(
        id: seeds[i].seedKey,
        serverId: 's',
        name: seeds[i].polishName,
        kind: seeds[i].kind,
        position: i,
        access: seeds[i].restricted
            ? ServerChannelAccess.restricted
            : ServerChannelAccess.members,
        mediaMode: seeds[i].mediaMode,
        schemaVersion: 1,
      ),
  ];
}

Widget _host(
  Server server,
  ServerMemberRole role, {
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: SafeArea(
        child: ServerPanel(
          server: server,
          channels: _channels(server.type),
          selectedId: _channels(server.type).first.id,
          role: role,
          onSelected: (_) {},
          onInvite: () {},
        ),
      ),
    ),
  ),
);

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
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
  setUpAll(_loadFonts);

  const publicCommunity = 'member-public-community';
  const privateCommunity = 'member-private-community';

  final cases = <(String, Server, ServerMemberRole)>[
    (
      publicCommunity,
      _server(ServerType.community, ServerPrivacy.public),
      ServerMemberRole.member,
    ),
    (
      privateCommunity,
      _server(ServerType.community, ServerPrivacy.private),
      ServerMemberRole.member,
    ),
    (
      'member-friends',
      _server(ServerType.friends, ServerPrivacy.inviteOnly),
      ServerMemberRole.member,
    ),
    (
      'moderator-friends',
      _server(ServerType.friends, ServerPrivacy.inviteOnly),
      ServerMemberRole.moderator,
    ),
  ];

  // CLAUDE.md requires mobile, tablet AND desktop to be verified for a
  // user-facing change, and the widened invite affordance lives on the
  // tablet/desktop rail button (`server-invite-action`) as much as in the
  // phone sheet. 360/420 alone proved nothing about the rail, so the two
  // widths the rail actually runs at are captured here as well.
  const widths = <double>[360, 420, 834, 1400];

  for (final case_ in cases) {
    for (final width in widths) {
      testWidgets('${case_.$1} at ${width.toInt()}', (tester) async {
        await _capturePanel(
          tester,
          server: case_.$2,
          role: case_.$3,
          width: width,
          name: 'server-invite-${case_.$1}-${width.toInt()}',
        );
      });
    }
  }

  // The presence of the button on a public Server and its ABSENCE on a private
  // one are the two frames the review turns on, so those two are also captured
  // at the largest text the app supports and in English — the size and the
  // language that break a rail label if anything does.
  for (final name in const [publicCommunity, privateCommunity]) {
    final case_ = cases.firstWhere((entry) => entry.$1 == name);
    for (final width in const <double>[834, 1400]) {
      testWidgets('$name at ${width.toInt()} at 200% text', (tester) async {
        await _capturePanel(
          tester,
          server: case_.$2,
          role: case_.$3,
          width: width,
          textScale: 2,
          name: 'server-invite-$name-${width.toInt()}-text200',
        );
      });

      testWidgets('$name at ${width.toInt()} in English', (tester) async {
        await _capturePanel(
          tester,
          server: case_.$2,
          role: case_.$3,
          width: width,
          locale: const Locale('en'),
          name: 'server-invite-$name-${width.toInt()}-en',
        );
      });
    }
  }
}

Future<void> _capturePanel(
  WidgetTester tester, {
  required Server server,
  required ServerMemberRole role,
  required double width,
  required String name,
  double textScale = 1,
  Locale locale = const Locale('pl'),
}) async {
  tester.view.devicePixelRatio = 1;
  // A rail at 200 % text needs the height a tablet actually has; 760 clipped
  // the last channel row and made the frame unreadable as evidence.
  tester.view.physicalSize = Size(width, textScale > 1 ? 1100 : 760);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _host(server, role, textScale: textScale, locale: locale),
  );
  await tester.pumpAndSettle();
  await _shoot(tester, name);
}
