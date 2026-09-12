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
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

class TestServerRepository implements ServerRepository {
  final requests = <ServerCreationRequest>[];
  Completer<ServerCreationResult>? pending;
  bool failNext = false;

  /// Thrown on every attempt, for failures that do not clear by retrying —
  /// an unregistered callable being the one this stage cares about.
  Object? alwaysFailWith;
  int allocated = 0;
  List<Server> servers = [];
  List<ServerChannel> channels = [];
  Stream<Server?>? serverStream;
  Stream<List<ServerChannel>>? channelStream;

  /// In-memory stand-in for the durable pending-creation store, scoped by
  /// owner and template exactly as the SharedPreferences store scopes it.
  final pendingCreations = <String, ServerCreationRequest>{};

  /// Makes every store call throw, to prove the store is a safety net and
  /// never a gate in front of creating a server.
  bool failPendingStore = false;
  @override
  String get currentUserId => 'owner';
  @override
  String newRequestId() => 'request-${++allocated}';
  String _scope(ServerType type) => '$currentUserId/${type.name}';
  @override
  Future<ServerCreationRequest?> pendingCreation(ServerType type) async {
    if (failPendingStore) throw StateError('store unavailable');
    return pendingCreations[_scope(type)];
  }

  @override
  Future<ServerCreationRequest> rememberPendingCreation(
    ServerCreationRequest request,
  ) async {
    if (failPendingStore) throw StateError('store unavailable');
    return pendingCreations.putIfAbsent(
      _scope(request.serverType),
      () => request,
    );
  }

  @override
  Future<void> forgetPendingCreation(ServerCreationRequest request) async {
    if (failPendingStore) throw StateError('store unavailable');
    final scope = _scope(request.serverType);
    if (pendingCreations[scope]?.requestId == request.requestId) {
      pendingCreations.remove(scope);
    }
  }

  @override
  Future<ServerCreationResult> createServer(
    ServerCreationRequest request,
  ) async {
    requests.add(request);
    final persistent = alwaysFailWith;
    if (persistent != null) throw persistent;
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
