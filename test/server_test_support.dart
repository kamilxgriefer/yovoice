import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

class TestServerRepository implements ServerRepository {
  final requests = <ServerCreationRequest>[];
  Completer<ServerCreationResult>? pending;
  bool failNext = false;
  int allocated = 0;
  List<Server> servers = [];
  List<ServerChannel> channels = [];
  Stream<Server?>? serverStream;
  Stream<List<ServerChannel>>? channelStream;
  @override
  String get currentUserId => 'owner';
  @override
  String newRequestId() => 'request-${++allocated}';
  @override
  Future<ServerCreationResult> createServer(
    ServerCreationRequest request,
  ) async {
    requests.add(request);
    if (failNext) {
      failNext = false;
      throw FirebaseFunctionsException(code: 'unavailable', message: 'Offline');
    }
    return pending?.future ??
        const ServerCreationResult(
          serverId: 'saved',
          defaultChannelId: 'general',
          channelIds: ['general'],
          alreadyExisted: false,
        );
  }

  @override
  Stream<List<Server>> watchMyServers() => Stream.value(servers);
  @override
  Stream<Server?> watchServer(String serverId) =>
      serverStream ??
      Stream.value(
        servers.where((server) => server.id == serverId).firstOrNull,
      );
  @override
  Stream<List<ServerChannel>> watchChannels(String serverId) =>
      channelStream ??
      Stream.value(
        channels.where((channel) => channel.serverId == serverId).toList(),
      );
}

Future<void> pumpServers(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool light = false,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('pl'),
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: child,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
