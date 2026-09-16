import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_type.dart';
import '../../data/models/server_whiteboard.dart';
import '../../data/services/server_whiteboard_live_transport.dart';
import '../../data/services/server_whiteboard_repository.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

/// Realtime, server-persisted canvas for a Company whiteboard channel.
///
/// Positions are stored as normalized coordinates, so the same drawing keeps
/// its layout on a phone, tablet and desktop. Each completed gesture becomes
/// one immutable polyline. The backend owns authorization, ordering, undo and
/// clear; the role checks here only avoid offering controls that cannot work.
class ServerWhiteboardBoard extends StatefulWidget {
  const ServerWhiteboardBoard({
    required this.server,
    required this.channel,
    required this.repository,
    required this.role,
    this.liveTransport,
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerWhiteboardRepository repository;
  final ServerWhiteboardLiveTransport? liveTransport;
  final ServerMemberRole? role;
  final bool compact;

  @override
  State<ServerWhiteboardBoard> createState() => _ServerWhiteboardBoardState();
}

enum _WhiteboardInteraction { draw, line, rectangle, arrow, navigate }

class _LiveDraftPublication {
  const _LiveDraftPublication({
    required this.draftId,
    required this.generation,
    required this.points,
    required this.color,
    required this.lineWidth,
  });

  final String draftId;
  final int generation;
  final List<ServerWhiteboardPoint> points;
  final ServerWhiteboardColor color;
  final int lineWidth;
}

class _ServerWhiteboardBoardState extends State<ServerWhiteboardBoard> {
  static const _maximumStrokes = 180;
  static const _maximumPoints = 64;
  // Eight previews per second feel continuous while bounding data-channel work
  // and remaining comfortably below the receiver's abuse budget.
  static const _draftPublishInterval = Duration(milliseconds: 120);
  static const _draftHandoffDelay = Duration(milliseconds: 450);
  static const _lineWidths = <int>[2, 5, 9, 14];

  late Stream<ServerWhiteboardSnapshot> _board;
  final ValueNotifier<List<ServerWhiteboardLiveDraft>> _remoteDrafts =
      ValueNotifier(const []);
  StreamSubscription<List<ServerWhiteboardLiveDraft>>? _liveDraftSubscription;
  int _draftSubscriptionEpoch = 0;
  final List<ServerWhiteboardPoint> _draft = [];
  final ValueNotifier<int> _draftRepaint = ValueNotifier(0);
  final List<ServerWhiteboardLocalStroke> _localStrokes = [];
  final Set<String> _inFlightRequestIds = {};
  final Map<String, ServerWhiteboardLocalStroke> _failedStrokes = {};
  final Set<String> _pendingUndoRequestIds = {};
  final Set<String> _scheduledReconciliations = {};
  final Map<String, ServerWhiteboardStroke> _scheduledConfirmedStrokes = {};
  final Set<String> _hiddenPersistedStrokeIds = {};
  final Map<String, int> _outstandingLiveDrafts = {};
  final Map<String, Timer> _draftCleanupTimers = {};
  final TransformationController _transformationController =
      TransformationController();
  ServerWhiteboardColor _color = ServerWhiteboardColor.ink;
  int _lineWidth = 5;
  _WhiteboardInteraction _interaction = _WhiteboardInteraction.draw;
  ServerWhiteboardPoint? _gestureOrigin;
  String? _activeDraftId;
  _LiveDraftPublication? _queuedDraftPublication;
  Future<bool>? _draftPublishInFlight;
  String? _inFlightDraftId;
  Timer? _draftPublishTimer;
  bool _showGrid = true;
  bool _operationBusy = false;
  bool _disposed = false;
  String? _error;

  bool get _canDraw =>
      !widget.server.isHeld &&
      widget.role != null &&
      widget.role != ServerMemberRole.guest &&
      widget.repository.currentUserId.isNotEmpty;

  bool get _canClear =>
      !widget.server.isHeld && (widget.role?.canManage ?? false);

  bool get _isDrawing => _draft.isNotEmpty;

  bool get _allowsLiveDrafts =>
      widget.channel.access == ServerChannelAccess.members;

  bool get _liveAvailable =>
      _allowsLiveDrafts &&
      (widget.liveTransport?.isAvailableFor(widget.server.id) ?? false);

  @override
  void initState() {
    super.initState();
    _board = _watch();
    widget.liveTransport?.addListener(_onLiveTransportChanged);
    _subscribeToLiveDrafts();
  }

  @override
  void didUpdateWidget(covariant ServerWhiteboardBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.liveTransport, widget.liveTransport)) {
      oldWidget.liveTransport?.removeListener(_onLiveTransportChanged);
      widget.liveTransport?.addListener(_onLiveTransportChanged);
    }
    if (!identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.liveTransport, widget.liveTransport) ||
        oldWidget.server.id != widget.server.id ||
        oldWidget.channel.id != widget.channel.id ||
        oldWidget.channel.access != widget.channel.access) {
      _cleanupOutstandingDrafts(
        transport: oldWidget.liveTransport,
        serverId: oldWidget.server.id,
        channelId: oldWidget.channel.id,
      );
      _draftPublishTimer?.cancel();
      for (final timer in _draftCleanupTimers.values) {
        timer.cancel();
      }
      _draftCleanupTimers.clear();
      _draftPublishTimer = null;
      _queuedDraftPublication = null;
      _activeDraftId = null;
      _gestureOrigin = null;
      _draft.clear();
      _localStrokes.clear();
      _inFlightRequestIds.clear();
      _failedStrokes.clear();
      _pendingUndoRequestIds.clear();
      _scheduledReconciliations.clear();
      _scheduledConfirmedStrokes.clear();
      _hiddenPersistedStrokeIds.clear();
      _outstandingLiveDrafts.clear();
      _transformationController.value = Matrix4.identity();
      _board = _watch();
      _subscribeToLiveDrafts();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.liveTransport?.removeListener(_onLiveTransportChanged);
    _draftSubscriptionEpoch++;
    unawaited(_liveDraftSubscription?.cancel());
    _draftPublishTimer?.cancel();
    for (final timer in _draftCleanupTimers.values) {
      timer.cancel();
    }
    _draftCleanupTimers.clear();
    _cleanupOutstandingDrafts(
      transport: widget.liveTransport,
      serverId: widget.server.id,
      channelId: widget.channel.id,
    );
    _draftRepaint.dispose();
    _remoteDrafts.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Stream<ServerWhiteboardSnapshot> _watch() =>
      widget.repository.watchWhiteboard(widget.server.id, widget.channel.id);

  Stream<List<ServerWhiteboardLiveDraft>> _watchDrafts() => _allowsLiveDrafts
      ? widget.liveTransport?.whiteboardLiveDrafts ?? Stream.value(const [])
      : Stream.value(const []);

  void _onLiveTransportChanged() {
    if (!_disposed && mounted) setState(() {});
  }

  void _subscribeToLiveDrafts() {
    final epoch = ++_draftSubscriptionEpoch;
    unawaited(_liveDraftSubscription?.cancel());
    _remoteDrafts.value = const [];
    _liveDraftSubscription = _watchDrafts().listen(
      (drafts) {
        if (_disposed || epoch != _draftSubscriptionEpoch) return;
        if (!_allowsLiveDrafts) {
          _remoteDrafts.value = const [];
          return;
        }
        _remoteDrafts.value = List.unmodifiable(
          drafts.where(
            (draft) =>
                draft.serverId == widget.server.id &&
                draft.channelId == widget.channel.id,
          ),
        );
      },
      onError: (Object _, StackTrace __) {
        if (_disposed || epoch != _draftSubscriptionEpoch) return;
        _remoteDrafts.value = const [];
      },
    );
  }

  void _startStroke(Offset position, Size canvasSize, int generation) {
    if (!_canDraw ||
        _operationBusy ||
        _interaction == _WhiteboardInteraction.navigate) {
      return;
    }
    final origin = _normalized(position, canvasSize);
    final draftId = widget.repository.newRequestId();
    setState(() {
      _error = _failedStrokes.isEmpty ? null : _error;
      _gestureOrigin = origin;
      _activeDraftId = draftId;
      _draft
        ..clear()
        ..add(origin);
    });
    _queueLiveDraft(generation);
    _draftRepaint.value++;
  }

  void _continueStroke(Offset position, Size canvasSize, int generation) {
    if (!_canDraw ||
        _operationBusy ||
        _interaction == _WhiteboardInteraction.navigate ||
        _draft.isEmpty) {
      return;
    }
    final point = _normalized(position, canvasSize);
    if (_interaction == _WhiteboardInteraction.draw) {
      final previous = _draft.last;
      final dx = point.x - previous.x;
      final dy = point.y - previous.y;
      // Sampling threshold limits redundant pointer noise. The complete
      // accepted path remains local; only the wire/persistence copy is later
      // simplified to the 64-point backend contract.
      if (dx * dx + dy * dy < 0.000004) return;
      _draft.add(point);
    } else {
      final origin = _gestureOrigin;
      if (origin == null) return;
      _draft
        ..clear()
        ..addAll(_shapePoints(_interaction, origin, point));
    }
    _queueLiveDraft(generation);
    // Repaint only the live-ink layer at pointer rate. Saved/grid and pending
    // layers sit in separate repaint boundaries below.
    _draftRepaint.value++;
  }

  void _cancelStroke() {
    if (_draft.isEmpty && _activeDraftId == null) return;
    final draftId = _activeDraftId;
    setState(() {
      _draft.clear();
      _gestureOrigin = null;
      _activeDraftId = null;
    });
    _draftRepaint.value++;
    if (draftId != null) _scheduleLiveDraftCleanup(draftId);
  }

  Future<void> _finishStroke({
    required int observedGeneration,
    required int minimumSequence,
  }) async {
    if (!_canDraw ||
        _operationBusy ||
        _interaction == _WhiteboardInteraction.navigate ||
        _draft.isEmpty) {
      return;
    }
    final draftId = _activeDraftId ?? widget.repository.newRequestId();
    var points = simplifyServerWhiteboardPoints(
      List<ServerWhiteboardPoint>.of(_draft),
      maximumPoints: _maximumPoints,
    );
    // A tap is a useful mark too. Two equal round-capped points persist it as
    // a dot while keeping the backend's polyline contract uniform.
    if (points.length == 1) points = [points.first, points.first];
    final stroke = ServerWhiteboardLocalStroke(
      requestId: draftId,
      observedGeneration: observedGeneration,
      minimumSequence: minimumSequence,
      points: points,
      color: _color,
      lineWidth: _lineWidth,
    );
    setState(() {
      _draft.clear();
      _gestureOrigin = null;
      _activeDraftId = null;
      _localStrokes.add(stroke);
      _inFlightRequestIds.add(stroke.requestId);
      _failedStrokes.remove(stroke.requestId);
      if (_failedStrokes.isEmpty) _error = null;
    });
    _draftRepaint.value++;
    final saved = await _persistStroke(stroke);
    _scheduleLiveDraftCleanup(
      draftId,
      delay: saved ? _draftHandoffDelay : Duration.zero,
    );
  }

  Future<bool> _persistStroke(ServerWhiteboardLocalStroke stroke) async {
    try {
      await widget.repository.createWhiteboardStroke(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        points: stroke.points,
        color: stroke.color,
        lineWidth: stroke.lineWidth,
        requestId: stroke.requestId,
      );
      if (mounted) {
        setState(() => _failedStrokes.remove(stroke.requestId));
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        final wasStillLocal = _localStrokes.any(
          (candidate) => candidate.requestId == stroke.requestId,
        );
        if (_pendingUndoRequestIds.remove(stroke.requestId)) {
          _localStrokes.removeWhere(
            (candidate) => candidate.requestId == stroke.requestId,
          );
          _failedStrokes.remove(stroke.requestId);
        } else if (wasStillLocal) {
          _failedStrokes[stroke.requestId] = stroke;
          _error = serverActionFailureCopy(
            error,
            AppLocalizations.of(context),
            fallback: AppLocalizations.of(context).text(
              'The line could not be saved. Try again.',
              'Nie udało się zapisać linii. Spróbuj ponownie.',
            ),
          );
        }
      });
      return false;
    } finally {
      if (mounted) {
        setState(() => _inFlightRequestIds.remove(stroke.requestId));
      }
    }
  }

  Future<void> _retryStroke(String requestId) async {
    final stroke = _failedStrokes[requestId];
    if (stroke == null || _operationBusy) return;
    setState(() {
      _failedStrokes.remove(requestId);
      _inFlightRequestIds.add(stroke.requestId);
      if (_failedStrokes.isEmpty) _error = null;
    });
    await _persistStroke(stroke);
  }

  Future<void> _retryAllStrokes() async {
    if (_failedStrokes.isEmpty || _operationBusy) return;
    final requestIds = List<String>.of(_failedStrokes.keys);
    await Future.wait([
      for (final requestId in requestIds) _retryStroke(requestId),
    ]);
  }

  void _removeFailedStroke(String requestId) {
    if (!_failedStrokes.containsKey(requestId)) return;
    setState(() {
      _failedStrokes.remove(requestId);
      _localStrokes.removeWhere((stroke) => stroke.requestId == requestId);
      if (_failedStrokes.isEmpty) _error = null;
    });
    _scheduleLiveDraftCleanup(requestId);
  }

  void _scheduleReconciliation(ServerWhiteboardReconciliation result) {
    if (result.confirmedRequestIds.isEmpty) return;
    for (final requestId in result.confirmedRequestIds) {
      if (_scheduledReconciliations.add(requestId)) {
        final stroke = result.confirmedStrokes[requestId];
        if (stroke != null) _scheduledConfirmedStrokes[requestId] = stroke;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledReconciliations.isEmpty) return;
      final reconciled = Set<String>.of(_scheduledReconciliations);
      final confirmedStrokes = Map<String, ServerWhiteboardStroke>.of(
        _scheduledConfirmedStrokes,
      );
      _scheduledReconciliations.clear();
      _scheduledConfirmedStrokes.clear();
      final before = _localStrokes.length;
      final undo = <ServerWhiteboardStroke>[];
      for (final requestId in reconciled) {
        if (_pendingUndoRequestIds.remove(requestId)) {
          final stroke = confirmedStrokes[requestId];
          if (stroke != null) {
            undo.add(stroke);
            _hiddenPersistedStrokeIds.add(stroke.id);
          }
        }
      }
      _localStrokes.removeWhere(
        (stroke) => reconciled.contains(stroke.requestId),
      );
      _inFlightRequestIds.removeAll(reconciled);
      for (final requestId in reconciled) {
        _failedStrokes.remove(requestId);
      }
      if (_localStrokes.length != before) setState(() {});
      for (final stroke in undo) {
        unawaited(_undoConfirmedOptimistic(stroke));
      }
    });
  }

  Future<void> _undoLatest(ServerWhiteboardSnapshot snapshot) async {
    if (_operationBusy) return;
    if (_draft.isNotEmpty) {
      _cancelStroke();
      return;
    }
    for (final stroke in _localStrokes.reversed) {
      if (_pendingUndoRequestIds.contains(stroke.requestId)) continue;
      final failed = _failedStrokes.remove(stroke.requestId) != null;
      setState(() {
        if (failed) {
          _localStrokes.removeWhere(
            (candidate) => candidate.requestId == stroke.requestId,
          );
        } else {
          // Hide it immediately. If the create is already committed, the
          // reconciliation path resolves its authoritative id and issues the
          // own-only callable undo as soon as the echo arrives.
          _pendingUndoRequestIds.add(stroke.requestId);
        }
        if (_failedStrokes.isEmpty) _error = null;
      });
      _scheduleLiveDraftCleanup(stroke.requestId);
      return;
    }
    final stroke = snapshot.lastOwnedBy(widget.repository.currentUserId);
    if (stroke == null) return;
    await _run(
      () => widget.repository.undoWhiteboardStroke(
        stroke: stroke,
        requestId: widget.repository.newRequestId(),
      ),
      fallback: AppLocalizations.of(context).text(
        'Your last line could not be undone.',
        'Nie udało się cofnąć Twojej ostatniej linii.',
      ),
    );
  }

  Future<void> _undoConfirmedOptimistic(ServerWhiteboardStroke stroke) async {
    try {
      await widget.repository.undoWhiteboardStroke(
        stroke: stroke,
        requestId: widget.repository.newRequestId(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hiddenPersistedStrokeIds.remove(stroke.id);
        _error = serverActionFailureCopy(
          error,
          AppLocalizations.of(context),
          fallback: AppLocalizations.of(context).text(
            'The saved line could not be undone. Try Undo again.',
            'Nie udało się cofnąć zapisanej linii. Spróbuj ponownie.',
          ),
        );
      });
    }
  }

  Future<void> _confirmClear(ServerWhiteboardSnapshot snapshot) async {
    if (_operationBusy || !_canClear || snapshot.state.isEmpty) return;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(copy.text('Clear the whiteboard?', 'Wyczyścić tablicę?')),
        content: Text(
          copy.text(
            'This removes every saved line for everyone in this channel.',
            'To usunie wszystkie zapisane linie u każdej osoby na tym kanale.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(copy.serverCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(copy.text('Clear', 'Wyczyść')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(
      () => widget.repository.clearWhiteboard(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        expectedRevision: snapshot.state.revision,
        requestId: widget.repository.newRequestId(),
      ),
      fallback: copy.text(
        'The whiteboard could not be cleared. Refresh and try again.',
        'Nie udało się wyczyścić tablicy. Odśwież i spróbuj ponownie.',
      ),
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String fallback,
  }) async {
    setState(() {
      _operationBusy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = serverActionFailureCopy(
          error,
          AppLocalizations.of(context),
          fallback: fallback,
        );
      });
    } finally {
      if (mounted) setState(() => _operationBusy = false);
    }
  }

  void _queueLiveDraft(int generation) {
    final draftId = _activeDraftId;
    final transport = widget.liveTransport;
    if (draftId == null ||
        _draft.isEmpty ||
        transport == null ||
        !_liveAvailable) {
      return;
    }
    _outstandingLiveDrafts[draftId] = generation;
    var points = simplifyServerWhiteboardPoints(
      _draft,
      maximumPoints: _maximumPoints,
    );
    if (points.length == 1) points = [points.first, points.first];
    _queuedDraftPublication = _LiveDraftPublication(
      draftId: draftId,
      generation: generation,
      points: points,
      color: _color,
      lineWidth: _lineWidth,
    );
    _pumpDraftPublisher();
  }

  void _pumpDraftPublisher() {
    if (_disposed ||
        _draftPublishInFlight != null ||
        _queuedDraftPublication == null ||
        _draftPublishTimer != null) {
      return;
    }
    final publication = _queuedDraftPublication!;
    _queuedDraftPublication = null;
    final transport = widget.liveTransport;
    if (transport == null || !_liveAvailable) {
      _inFlightDraftId = null;
      return;
    }
    _inFlightDraftId = publication.draftId;
    _draftPublishTimer = Timer(_draftPublishInterval, () {
      _draftPublishTimer = null;
      _pumpDraftPublisher();
    });
    final operation = transport.publishWhiteboardLiveDraft(
      serverId: widget.server.id,
      channelId: widget.channel.id,
      draftId: publication.draftId,
      generation: publication.generation,
      points: publication.points,
      color: publication.color,
      lineWidth: publication.lineWidth,
    );
    _draftPublishInFlight = operation;
    unawaited(
      operation
          .then<void>((_) {}, onError: (Object _, StackTrace __) {})
          .whenComplete(() {
            if (!identical(_draftPublishInFlight, operation)) return;
            _draftPublishInFlight = null;
            _inFlightDraftId = null;
            _pumpDraftPublisher();
          }),
    );
  }

  void _scheduleLiveDraftCleanup(
    String draftId, {
    Duration delay = Duration.zero,
  }) {
    if (_queuedDraftPublication?.draftId == draftId) {
      _queuedDraftPublication = null;
      _draftPublishTimer?.cancel();
      _draftPublishTimer = null;
    }
    final pending = _inFlightDraftId == draftId ? _draftPublishInFlight : null;
    final transport = widget.liveTransport;
    final serverId = widget.server.id;
    final channelId = widget.channel.id;
    final generation = _outstandingLiveDrafts[draftId];
    Future<void> clearAfterPendingWrite() async {
      try {
        await pending;
      } catch (_) {
        // Continue to the reliable clear after a failed lossy update.
      }
      try {
        if (transport != null && generation != null) {
          await transport.clearWhiteboardLiveDraft(
            serverId: serverId,
            channelId: channelId,
            draftId: draftId,
            generation: generation,
          );
        }
      } catch (_) {
        // Best effort: receivers evict the preview after its short lifetime.
      } finally {
        _outstandingLiveDrafts.remove(draftId);
      }
    }

    if (delay > Duration.zero && !_disposed) {
      _draftCleanupTimers[draftId]?.cancel();
      _draftCleanupTimers[draftId] = Timer(delay, () {
        _draftCleanupTimers.remove(draftId);
        unawaited(clearAfterPendingWrite());
      });
      return;
    }
    unawaited(clearAfterPendingWrite());
  }

  void _cleanupOutstandingDrafts({
    required ServerWhiteboardLiveTransport? transport,
    required String serverId,
    required String channelId,
  }) {
    final drafts = Map<String, int>.of(_outstandingLiveDrafts);
    final pending = _draftPublishInFlight;
    if (drafts.isEmpty || transport == null) return;
    unawaited(() async {
      try {
        await pending;
      } catch (_) {
        // Continue to cleanup even when the last preview write failed.
      }
      for (final entry in drafts.entries) {
        try {
          await transport.clearWhiteboardLiveDraft(
            serverId: serverId,
            channelId: channelId,
            draftId: entry.key,
            generation: entry.value,
          );
        } catch (_) {
          // Receiver-side expiry bounds disconnect and disposal races.
        }
      }
    }());
  }

  List<ServerWhiteboardPoint> _shapePoints(
    _WhiteboardInteraction interaction,
    ServerWhiteboardPoint start,
    ServerWhiteboardPoint end,
  ) => switch (interaction) {
    _WhiteboardInteraction.line => [start, end],
    _WhiteboardInteraction.rectangle => [
      start,
      ServerWhiteboardPoint(end.x, start.y),
      end,
      ServerWhiteboardPoint(start.x, end.y),
      start,
    ],
    _WhiteboardInteraction.arrow => _arrowPoints(start, end),
    _ => [start, end],
  };

  List<ServerWhiteboardPoint> _arrowPoints(
    ServerWhiteboardPoint start,
    ServerWhiteboardPoint end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < .0001) return [start, end];
    final head = (length * .24).clamp(.025, .075).toDouble();
    final ux = dx / length;
    final uy = dy / length;
    final baseX = end.x - ux * head;
    final baseY = end.y - uy * head;
    final wing = head * .52;
    ServerWhiteboardPoint point(double x, double y) => ServerWhiteboardPoint(
      x.clamp(0.0, 1.0).toDouble(),
      y.clamp(0.0, 1.0).toDouble(),
    );
    final firstWing = point(baseX - uy * wing, baseY + ux * wing);
    final secondWing = point(baseX + uy * wing, baseY - ux * wing);
    return [start, end, firstWing, end, secondWing];
  }

  void _setInteraction(_WhiteboardInteraction value) {
    if (_interaction == value) return;
    _cancelStroke();
    setState(() => _interaction = value);
  }

  void _setZoom(double scale, Size canvasSize) {
    final target = scale.clamp(1.0, 4.0).toDouble();
    final matrix = Matrix4.diagonal3Values(target, target, 1)
      ..setTranslationRaw(
        (1 - target) * canvasSize.width / 2,
        (1 - target) * canvasSize.height / 2,
        0,
      );
    _transformationController.value = matrix;
  }

  void _changeZoom(double factor, Size canvasSize) {
    final current = _transformationController.value.getMaxScaleOnAxis();
    _setZoom(current * factor, canvasSize);
  }

  ServerWhiteboardPoint _normalized(Offset position, Size size) {
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;
    return ServerWhiteboardPoint(
      (position.dx / width).clamp(0.0, 1.0).toDouble(),
      (position.dy / height).clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      widget.server.type,
    ).resolve(Theme.of(context).brightness);
    if (widget.server.type != ServerType.company ||
        widget.channel.kind != ServerChannelKind.whiteboard) {
      return Center(child: Text(copy.serverActionUnavailable));
    }
    return Material(
      color: Colors.transparent,
      child: StreamBuilder<ServerWhiteboardSnapshot>(
        stream: _board,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Semantics(
                liveRegion: true,
                child: Padding(
                  key: const ValueKey('server-whiteboard-load-error'),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    serverActionFailureCopy(
                      snapshot.error!,
                      copy,
                      fallback: copy.text(
                        'The whiteboard is unavailable.',
                        'Tablica jest niedostępna.',
                      ),
                    ),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.dangerForeground,
                    ),
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
              child: Semantics(
                label: copy.text(
                  'Loading the shared whiteboard',
                  'Wczytywanie wspólnej tablicy',
                ),
                child: const CircularProgressIndicator(
                  key: ValueKey('server-whiteboard-loading'),
                ),
              ),
            );
          }
          final board = snapshot.data!;
          final reconciliation = board.reconcileLocal(
            userId: widget.repository.currentUserId,
            localStrokes: _localStrokes,
          );
          _scheduleReconciliation(reconciliation);
          final pendingUndoStrokeIds = <String>{
            for (final entry in reconciliation.confirmedStrokes.entries)
              if (_pendingUndoRequestIds.contains(entry.key)) entry.value.id,
          };
          final authoritativeIds = board.strokes
              .map((stroke) => stroke.id)
              .toSet();
          _hiddenPersistedStrokeIds.retainAll(authoritativeIds);
          final hiddenPersisted = {
            ..._hiddenPersistedStrokeIds,
            ...pendingUndoStrokeIds,
          };
          final visibleSaved = board.strokes
              .where((stroke) => !hiddenPersisted.contains(stroke.id))
              .toList(growable: false);
          final visibleLocal = reconciliation.unmatchedLocal
              .where(
                (stroke) => !_pendingUndoRequestIds.contains(stroke.requestId),
              )
              .toList(growable: false);
          final effectiveStrokeCount =
              board.state.strokeCount + visibleLocal.length;
          final boardHasCapacity = effectiveStrokeCount < _maximumStrokes;
          return SingleChildScrollView(
            key: const ValueKey('server-whiteboard-scroll'),
            padding: EdgeInsets.all(widget.compact ? 12 : AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  count: board.state.strokeCount,
                  pendingCount: visibleLocal.length,
                  isDrawing: _isDrawing,
                  compact: widget.compact,
                  colors: colors,
                ),
                const SizedBox(height: AppSpacing.md),
                _Toolbar(
                  color: _color,
                  lineWidth: _lineWidth,
                  interaction: _interaction,
                  showGrid: _showGrid,
                  busy: _operationBusy,
                  canDraw: _canDraw && boardHasCapacity,
                  canUndo:
                      !_operationBusy &&
                      _canDraw &&
                      (_draft.isNotEmpty ||
                          visibleLocal.isNotEmpty ||
                          board.lastOwnedBy(widget.repository.currentUserId) !=
                              null),
                  showClear: _canClear,
                  canClear:
                      !_operationBusy && _canClear && !board.state.isEmpty,
                  colors: colors,
                  onInteraction: _setInteraction,
                  onGrid: () => setState(() => _showGrid = !_showGrid),
                  onColor: (value) => setState(() => _color = value),
                  onLineWidth: (value) => setState(() => _lineWidth = value),
                  onUndo: () => unawaited(_undoLatest(board)),
                  onClear: () => unawaited(_confirmClear(board)),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('server-whiteboard-error'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.dangerSurface,
                        borderRadius: AppRadius.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            error,
                            style: AppTypography.bodySmall.copyWith(
                              color: palette.dangerForeground,
                            ),
                          ),
                          if (_failedStrokes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              key: const ValueKey(
                                'server-whiteboard-retry-all',
                              ),
                              onPressed: () => unawaited(_retryAllStrokes()),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                copy.template(
                                  'Retry all ({count})',
                                  'Ponów wszystkie ({count})',
                                  values: {'count': _failedStrokes.length},
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry
                                    in _failedStrokes.entries.indexed)
                                  _FailedStrokeActions(
                                    number: entry.$1 + 1,
                                    requestId: entry.$2.key,
                                    onRetry: () =>
                                        unawaited(_retryStroke(entry.$2.key)),
                                    onRemove: () =>
                                        _removeFailedStroke(entry.$2.key),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _Canvas(
                  serverId: widget.server.id,
                  channelId: widget.channel.id,
                  strokes: visibleSaved,
                  localStrokes: visibleLocal,
                  liveDrafts: _remoteDrafts,
                  generation: board.state.generation,
                  draft: _draft,
                  draftRepaint: _draftRepaint,
                  draftColor: _color,
                  draftLineWidth: _lineWidth,
                  interaction: _interaction,
                  showGrid: _showGrid,
                  transformationController: _transformationController,
                  enabled: _canDraw && !_operationBusy && boardHasCapacity,
                  compact: widget.compact,
                  palette: palette,
                  onZoomOut: (size) => _changeZoom(.8, size),
                  onZoomReset: (size) => _setZoom(1, size),
                  onZoomIn: (size) => _changeZoom(1.25, size),
                  onStart: (position, size) =>
                      _startStroke(position, size, board.state.generation),
                  onUpdate: (position, size) =>
                      _continueStroke(position, size, board.state.generation),
                  onEnd: () => unawaited(
                    _finishStroke(
                      observedGeneration: board.state.generation,
                      minimumSequence: board.state.nextSequence,
                    ),
                  ),
                  onCancel: _cancelStroke,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AccessNote(
                  canDraw: _canDraw,
                  held: widget.server.isHeld,
                  full: !boardHasCapacity,
                  realtimeAvailable: _liveAvailable,
                ),
                if (_operationBusy || _inFlightRequestIds.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    label: copy.text(
                      'Saving whiteboard changes',
                      'Zapisywanie zmian na tablicy',
                    ),
                    child: const LinearProgressIndicator(
                      key: ValueKey('server-whiteboard-progress'),
                      minHeight: 2,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FailedStrokeActions extends StatelessWidget {
  const _FailedStrokeActions({
    required this.number,
    required this.requestId,
    required this.onRetry,
    required this.onRemove,
  });

  final int number;
  final String requestId;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: copy.template(
        'Unsaved line {number}',
        'Niezapisana linia {number}',
        values: {'number': number},
      ),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: context.appPalette.surface.withValues(alpha: .72),
          borderRadius: AppRadius.pill,
          border: Border.all(color: context.appPalette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$number',
              style: AppTypography.labelMedium.copyWith(
                color: context.appPalette.textSecondary,
              ),
            ),
            IconButton(
              key: ValueKey('server-whiteboard-retry-$requestId'),
              onPressed: onRetry,
              tooltip: copy.text('Retry this line', 'Ponów tę linię'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              key: ValueKey('server-whiteboard-remove-$requestId'),
              onPressed: onRemove,
              tooltip: copy.text('Remove this line', 'Usuń tę linię'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.pendingCount,
    required this.isDrawing,
    required this.compact,
    required this.colors,
  });

  final int count;
  final int pendingCount;
  final bool isDrawing;
  final bool compact;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    if (compact) {
      return Semantics(
        header: true,
        child: Container(
          key: const ValueKey('server-whiteboard-header'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.cardWash,
            borderRadius: AppRadius.lg,
            border: Border.all(color: colors.iconBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.iconSurface,
                      borderRadius: AppRadius.sm,
                      border: Border.all(color: colors.iconBorder),
                    ),
                    child: Icon(
                      Icons.draw_outlined,
                      size: 22,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      copy.text('Shared whiteboard', 'Wspólna tablica'),
                      style: AppTypography.titleMedium.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                copy.text(
                  'Draw together. Changes appear live.',
                  'Rysujcie razem. Zmiany pojawiają się na żywo.',
                ),
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _BoardStatusPill(
                    pendingCount: pendingCount,
                    isDrawing: isDrawing,
                    colors: colors,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: AppRadius.pill,
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      '$count/${_ServerWhiteboardBoardState._maximumStrokes}',
                      key: const ValueKey('server-whiteboard-count'),
                      style: AppTypography.labelMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      header: true,
      child: Container(
        key: const ValueKey('server-whiteboard-header'),
        padding: EdgeInsets.all(compact ? 16 : 20),
        decoration: BoxDecoration(
          color: colors.cardWash,
          borderRadius: AppRadius.xl,
          border: Border.all(color: colors.iconBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.iconSurface,
                borderRadius: AppRadius.md,
                border: Border.all(color: colors.iconBorder),
              ),
              child: Icon(Icons.draw_outlined, color: colors.foreground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    copy.text('Shared whiteboard', 'Wspólna tablica'),
                    style:
                        (compact
                                ? AppTypography.titleLarge
                                : AppTypography.headlineSmall)
                            .copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy.text(
                      'Draw together during the meeting. Ink appears instantly and stays synchronized with this server.',
                      'Rysujcie razem podczas spotkania. Linie pojawiają się natychmiast i synchronizują z tym serwerem.',
                    ),
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _BoardStatusPill(
                    pendingCount: pendingCount,
                    isDrawing: isDrawing,
                    colors: colors,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: AppRadius.pill,
                border: Border.all(color: palette.border),
              ),
              child: Text(
                '$count/${_ServerWhiteboardBoardState._maximumStrokes}',
                key: const ValueKey('server-whiteboard-count'),
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardStatusPill extends StatelessWidget {
  const _BoardStatusPill({
    required this.pendingCount,
    required this.isDrawing,
    required this.colors,
  });

  final int pendingCount;
  final bool isDrawing;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final (icon, label, key) = isDrawing
        ? (
            Icons.gesture_rounded,
            copy.text('Drawing live', 'Rysujesz na żywo'),
            const ValueKey('server-whiteboard-drawing-live'),
          )
        : pendingCount > 0
        ? (
            Icons.sync_rounded,
            copy.template(
              'Synchronizing {count}',
              'Synchronizacja: {count}',
              values: {'count': pendingCount},
            ),
            const ValueKey('server-whiteboard-sync-status'),
          )
        : (
            Icons.cloud_done_outlined,
            copy.text('Up to date', 'Aktualna'),
            const ValueKey('server-whiteboard-synced'),
          );
    return Semantics(
      liveRegion: isDrawing || pendingCount > 0,
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colors.selectedWash,
          borderRadius: AppRadius.pill,
          border: Border.all(color: colors.iconBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.color,
    required this.lineWidth,
    required this.interaction,
    required this.showGrid,
    required this.busy,
    required this.canDraw,
    required this.canUndo,
    required this.showClear,
    required this.canClear,
    required this.colors,
    required this.onInteraction,
    required this.onGrid,
    required this.onColor,
    required this.onLineWidth,
    required this.onUndo,
    required this.onClear,
  });

  final ServerWhiteboardColor color;
  final int lineWidth;
  final _WhiteboardInteraction interaction;
  final bool showGrid;
  final bool busy;
  final bool canDraw;
  final bool canUndo;
  final bool showClear;
  final bool canClear;
  final ServerIdentityVisuals colors;
  final ValueChanged<_WhiteboardInteraction> onInteraction;
  final VoidCallback onGrid;
  final ValueChanged<ServerWhiteboardColor> onColor;
  final ValueChanged<int> onLineWidth;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    // Every control stays in view at every width: a strip wraps onto another
    // run instead of scrolling, so no tool is cut off behind an edge with no
    // scroll affordance (Bugs.md F1, phone width 402 pt).
    Widget controlStrip({required Key key, required List<Widget> children}) {
      return Wrap(
        key: key,
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }

    final drawingControls = <Widget>[
      _ToolButton(
        key: const ValueKey('server-whiteboard-tool-draw'),
        icon: Icons.draw_rounded,
        label: copy.text('Draw', 'Rysuj'),
        selected: interaction == _WhiteboardInteraction.draw,
        enabled: canDraw && !busy,
        colors: colors,
        onPressed: () => onInteraction(_WhiteboardInteraction.draw),
      ),
      _ToolButton(
        key: const ValueKey('server-whiteboard-tool-navigate'),
        icon: Icons.pan_tool_alt_outlined,
        label: copy.text('Move canvas', 'Przesuwaj'),
        selected: interaction == _WhiteboardInteraction.navigate,
        enabled: true,
        colors: colors,
        onPressed: () => onInteraction(_WhiteboardInteraction.navigate),
      ),
      _ToolButton(
        key: const ValueKey('server-whiteboard-tool-line'),
        icon: Icons.horizontal_rule_rounded,
        label: copy.text('Straight line', 'Linia prosta'),
        selected: interaction == _WhiteboardInteraction.line,
        enabled: canDraw && !busy,
        colors: colors,
        onPressed: () => onInteraction(_WhiteboardInteraction.line),
      ),
      _ToolButton(
        key: const ValueKey('server-whiteboard-tool-rectangle'),
        icon: Icons.rectangle_outlined,
        label: copy.text('Rectangle', 'Prostokąt'),
        selected: interaction == _WhiteboardInteraction.rectangle,
        enabled: canDraw && !busy,
        colors: colors,
        onPressed: () => onInteraction(_WhiteboardInteraction.rectangle),
      ),
      _ToolButton(
        key: const ValueKey('server-whiteboard-tool-arrow'),
        icon: Icons.arrow_forward_rounded,
        label: copy.text('Arrow', 'Strzałka'),
        selected: interaction == _WhiteboardInteraction.arrow,
        enabled: canDraw && !busy,
        colors: colors,
        onPressed: () => onInteraction(_WhiteboardInteraction.arrow),
      ),
      _ToolButton(
        key: const ValueKey('server-whiteboard-grid'),
        icon: Icons.grid_4x4_rounded,
        label: copy.text('Grid', 'Siatka'),
        selected: showGrid,
        enabled: true,
        colors: colors,
        onPressed: onGrid,
      ),
    ];
    final actionControls = <Widget>[
      IconButton.outlined(
        key: const ValueKey('server-whiteboard-undo'),
        onPressed: canUndo ? onUndo : null,
        tooltip: copy.text('Undo your last line', 'Cofnij swoją linię'),
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        icon: const Icon(Icons.undo_rounded),
      ),
      if (showClear)
        IconButton.outlined(
          key: const ValueKey('server-whiteboard-clear'),
          onPressed: canClear ? onClear : null,
          tooltip: copy.text('Clear whiteboard', 'Wyczyść tablicę'),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: canClear ? palette.dangerForeground : null,
          ),
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
    ];
    final colorControls = <Widget>[
      for (final value in ServerWhiteboardColor.values)
        _ColorButton(
          value: value,
          selected: value == color,
          enabled: canDraw && !busy,
          colors: colors,
          onPressed: () => onColor(value),
        ),
    ];
    final widthControls = <Widget>[
      for (final value in _ServerWhiteboardBoardState._lineWidths)
        _LineWidthButton(
          value: value,
          selected: value == lineWidth,
          enabled: canDraw && !busy,
          colors: colors,
          onPressed: () => onLineWidth(value),
        ),
    ];
    return Container(
      key: const ValueKey('server-whiteboard-toolbar'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text('Tools', 'Narzędzia'),
            style: AppTypography.labelMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          controlStrip(
            key: const ValueKey('server-whiteboard-tools-strip'),
            children: [...drawingControls, ...actionControls],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 10),
          Text(
            copy.text('Ink color', 'Kolor linii'),
            style: AppTypography.labelMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          controlStrip(
            key: const ValueKey('server-whiteboard-colors-strip'),
            children: colorControls,
          ),
          const SizedBox(height: 10),
          Text(
            copy.text('Line width', 'Grubość linii'),
            style: AppTypography.labelMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          controlStrip(
            key: const ValueKey('server-whiteboard-widths-strip'),
            children: widthControls,
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.colors,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final ServerIdentityVisuals colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: enabled ? onPressed : null,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: selected ? colors.foreground : null,
            backgroundColor: selected ? colors.selectedWash : null,
            side: BorderSide(
              color: selected ? colors.iconBorder : Colors.transparent,
            ),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.colors,
    required this.onPressed,
  });

  final ServerWhiteboardColor value;
  final bool selected;
  final bool enabled;
  final ServerIdentityVisuals colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = _colorLabel(copy, value);
    final swatch = _strokeColor(value, palette);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: 48,
          child: Material(
            color: selected ? colors.selectedWash : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.md,
              side: BorderSide(
                color: selected ? colors.foreground : Colors.transparent,
                width: selected ? 2 : 1,
              ),
            ),
            child: InkWell(
              key: ValueKey('server-whiteboard-color-${value.name}'),
              onTap: enabled ? onPressed : null,
              borderRadius: AppRadius.md,
              child: Center(
                child: Container(
                  width: 23,
                  height: 23,
                  decoration: BoxDecoration(
                    color: enabled ? swatch : palette.surfaceSunken,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.borderStrong),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineWidthButton extends StatelessWidget {
  const _LineWidthButton({
    required this.value,
    required this.selected,
    required this.enabled,
    required this.colors,
    required this.onPressed,
  });

  final int value;
  final bool selected;
  final bool enabled;
  final ServerIdentityVisuals colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final label = copy.template(
      'Line width {value}',
      'Grubość linii {value}',
      values: {'value': value},
    );
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: 48,
          child: Material(
            color: selected ? colors.selectedWash : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.md,
              side: BorderSide(
                color: selected ? colors.foreground : Colors.transparent,
                width: selected ? 2 : 1,
              ),
            ),
            child: InkWell(
              key: ValueKey('server-whiteboard-width-$value'),
              onTap: enabled ? onPressed : null,
              borderRadius: AppRadius.md,
              child: Center(
                child: Container(
                  width: 26,
                  height: value.toDouble(),
                  decoration: BoxDecoration(
                    color: enabled ? palette.textPrimary : palette.textTertiary,
                    borderRadius: AppRadius.pill,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.serverId,
    required this.channelId,
    required this.strokes,
    required this.localStrokes,
    required this.liveDrafts,
    required this.generation,
    required this.draft,
    required this.draftRepaint,
    required this.draftColor,
    required this.draftLineWidth,
    required this.interaction,
    required this.showGrid,
    required this.transformationController,
    required this.enabled,
    required this.compact,
    required this.palette,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onZoomIn,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final String serverId;
  final String channelId;
  final List<ServerWhiteboardStroke> strokes;
  final List<ServerWhiteboardLocalStroke> localStrokes;
  final ValueListenable<List<ServerWhiteboardLiveDraft>> liveDrafts;
  final int generation;
  final List<ServerWhiteboardPoint> draft;
  final Listenable draftRepaint;
  final ServerWhiteboardColor draftColor;
  final int draftLineWidth;
  final _WhiteboardInteraction interaction;
  final bool showGrid;
  final TransformationController transformationController;
  final bool enabled;
  final bool compact;
  final AppPalette palette;
  final ValueChanged<Size> onZoomOut;
  final ValueChanged<Size> onZoomReset;
  final ValueChanged<Size> onZoomIn;
  final void Function(Offset position, Size size) onStart;
  final void Function(Offset position, Size size) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = compact
                ? (width * .72).clamp(260.0, 520.0).toDouble()
                : (width * .58).clamp(320.0, 600.0).toDouble();
            final size = Size(width, height);
            final label = copy.template(
              'Shared whiteboard with {count} saved lines.',
              'Wspólna tablica z {count} zapisanymi liniami.',
              values: {'count': strokes.length + localStrokes.length},
            );
            final hint = interaction == _WhiteboardInteraction.navigate
                ? copy.text(
                    'Drag to move the canvas and pinch to zoom.',
                    'Przeciągnij, aby przesunąć tablicę, i zbliż palce, aby zmienić powiększenie.',
                  )
                : enabled
                ? copy.text(
                    'Drag across the canvas. Ink appears immediately.',
                    'Przeciągnij po obszarze. Linia pojawi się natychmiast.',
                  )
                : copy.text(
                    'This whiteboard is read only for you.',
                    'Ta tablica jest dla Ciebie tylko do odczytu.',
                  );
            final drawingEnabled =
                enabled && interaction != _WhiteboardInteraction.navigate;
            return SizedBox(
              height: height,
              width: width,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      container: true,
                      image: true,
                      label: label,
                      hint: hint,
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.surfaceRaised,
                            borderRadius: AppRadius.lg,
                            border: Border.all(color: palette.borderStrong),
                            boxShadow: [
                              BoxShadow(
                                color: palette.shadow.withValues(alpha: .12),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: AppRadius.lg,
                            child: InteractiveViewer(
                              transformationController:
                                  transformationController,
                              minScale: 1,
                              maxScale: 4,
                              panEnabled:
                                  interaction ==
                                  _WhiteboardInteraction.navigate,
                              scaleEnabled:
                                  interaction ==
                                  _WhiteboardInteraction.navigate,
                              child: GestureDetector(
                                key: const ValueKey('server-whiteboard-canvas'),
                                dragStartBehavior: DragStartBehavior.down,
                                behavior: HitTestBehavior.opaque,
                                onPanStart: drawingEnabled
                                    ? (details) =>
                                          onStart(details.localPosition, size)
                                    : null,
                                onPanUpdate: drawingEnabled
                                    ? (details) =>
                                          onUpdate(details.localPosition, size)
                                    : null,
                                onPanEnd: drawingEnabled
                                    ? (_) => onEnd()
                                    : null,
                                onPanCancel: drawingEnabled ? onCancel : null,
                                onTapUp: drawingEnabled
                                    ? (details) {
                                        onStart(details.localPosition, size);
                                        onEnd();
                                      }
                                    : null,
                                child: SizedBox(
                                  height: height,
                                  width: width,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      RepaintBoundary(
                                        key: const ValueKey(
                                          'server-whiteboard-static-layer',
                                        ),
                                        child: CustomPaint(
                                          isComplex: true,
                                          painter: _WhiteboardStaticPainter(
                                            strokes: strokes,
                                            showGrid: showGrid,
                                            palette: palette,
                                          ),
                                        ),
                                      ),
                                      RepaintBoundary(
                                        key: const ValueKey(
                                          'server-whiteboard-pending-layer',
                                        ),
                                        child: CustomPaint(
                                          painter: _WhiteboardLocalPainter(
                                            strokes: localStrokes,
                                            palette: palette,
                                          ),
                                        ),
                                      ),
                                      _RemoteDraftLayer(
                                        drafts: liveDrafts,
                                        serverId: serverId,
                                        channelId: channelId,
                                        generation: generation,
                                        palette: palette,
                                      ),
                                      RepaintBoundary(
                                        key: const ValueKey(
                                          'server-whiteboard-live-ink-layer',
                                        ),
                                        child: CustomPaint(
                                          willChange: true,
                                          painter: _WhiteboardDraftPainter(
                                            draft: draft,
                                            repaint: draftRepaint,
                                            color: draftColor,
                                            lineWidth: draftLineWidth,
                                            palette: palette,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _ZoomControls(
                      controller: transformationController,
                      palette: palette,
                      onZoomOut: () => onZoomOut(size),
                      onReset: () => onZoomReset(size),
                      onZoomIn: () => onZoomIn(size),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.controller,
    required this.palette,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final TransformationController controller;
  final AppPalette palette;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    // Opaque, so strokes under the corner never show through the zoom
    // buttons or the percentage label (Bugs.md F6).
    return Material(
      key: const ValueKey('server-whiteboard-zoom-controls'),
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
        side: BorderSide(color: palette.borderStrong),
      ),
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: controller,
        builder: (context, matrix, _) {
          final percent = (matrix.getMaxScaleOnAxis() * 100).round();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('server-whiteboard-zoom-out'),
                onPressed: percent > 100 ? onZoomOut : null,
                tooltip: copy.text('Zoom out', 'Pomniejsz'),
                icon: const Icon(Icons.remove_rounded),
              ),
              Semantics(
                button: true,
                label: copy.template(
                  'Reset zoom, currently {value} percent',
                  'Resetuj powiększenie, obecnie {value} procent',
                  values: {'value': percent},
                ),
                onTap: onReset,
                excludeSemantics: true,
                child: TextButton(
                  key: const ValueKey('server-whiteboard-zoom-reset'),
                  onPressed: onReset,
                  style: TextButton.styleFrom(minimumSize: const Size(56, 48)),
                  child: Text('$percent%'),
                ),
              ),
              IconButton(
                key: const ValueKey('server-whiteboard-zoom-in'),
                onPressed: percent < 400 ? onZoomIn : null,
                tooltip: copy.text('Zoom in', 'Powiększ'),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccessNote extends StatelessWidget {
  const _AccessNote({
    required this.canDraw,
    required this.held,
    required this.full,
    required this.realtimeAvailable,
  });

  final bool canDraw;
  final bool held;
  final bool full;
  final bool realtimeAvailable;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final text = held
        ? copy.serverHeldBody
        : full
        ? copy.text(
            'The board is full. A manager can clear it to keep drawing.',
            'Tablica jest pełna. Osoba zarządzająca może ją wyczyścić, aby kontynuować rysowanie.',
          )
        : canDraw && realtimeAvailable
        ? copy.text(
            'Your team sees the line while you draw. It saves automatically when you lift your finger or pointer.',
            'Zespół widzi linię podczas rysowania. Zapisuje się automatycznie po oderwaniu palca lub wskaźnika.',
          )
        : canDraw
        ? copy.text(
            'The line appears here immediately and saves when you finish. Join the Company meeting to share its movement live.',
            'Linia pojawia się tutaj od razu i zapisuje po zakończeniu. Dołącz do spotkania firmowego, aby inni widzieli jej ruch na żywo.',
          )
        : realtimeAvailable
        ? copy.text(
            'You can follow the whiteboard live. Members can also draw.',
            'Możesz śledzić tablicę na żywo. Członkowie mogą też rysować.',
          )
        : copy.text(
            'Saved lines stay available here. Join the Company meeting to follow drawing motion live.',
            'Zapisane linie pozostają tutaj dostępne. Dołącz do spotkania firmowego, aby śledzić ruch rysowania na żywo.',
          );
    return Text(
      text,
      key: const ValueKey('server-whiteboard-access-note'),
      style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
    );
  }
}

class _RemoteDraftLayer extends StatelessWidget {
  const _RemoteDraftLayer({
    required this.drafts,
    required this.serverId,
    required this.channelId,
    required this.generation,
    required this.palette,
  });

  final ValueListenable<List<ServerWhiteboardLiveDraft>> drafts;
  final String serverId;
  final String channelId;
  final int generation;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ServerWhiteboardLiveDraft>>(
      valueListenable: drafts,
      builder: (context, currentDrafts, _) {
        final visible = currentDrafts
            .where(
              (draft) => draft.isVisibleAt(
                DateTime.now(),
                expectedServerId: serverId,
                expectedChannelId: channelId,
                boardGeneration: generation,
              ),
            )
            .toList(growable: false);
        return RepaintBoundary(
          key: const ValueKey('server-whiteboard-remote-draft-layer'),
          child: CustomPaint(
            key: ValueKey(
              'server-whiteboard-remote-draft-paint-${visible.length}',
            ),
            willChange: visible.isNotEmpty,
            painter: _WhiteboardRemoteDraftPainter(
              drafts: visible,
              palette: palette,
            ),
          ),
        );
      },
    );
  }
}

class _WhiteboardStaticPainter extends CustomPainter {
  const _WhiteboardStaticPainter({
    required this.strokes,
    required this.showGrid,
    required this.palette,
  });

  final List<ServerWhiteboardStroke> strokes;
  final bool showGrid;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      final grid = Paint()
        ..color = palette.border.withValues(alpha: .52)
        ..strokeWidth = 1;
      for (var step = 1; step < 8; step++) {
        final x = size.width * step / 8;
        final y = size.height * step / 8;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
    for (final stroke in strokes) {
      _paintWhiteboardStroke(
        canvas,
        size,
        stroke.points,
        stroke.color,
        stroke.lineWidth.toDouble(),
        palette,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardStaticPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.palette != palette;
}

class _WhiteboardLocalPainter extends CustomPainter {
  const _WhiteboardLocalPainter({required this.strokes, required this.palette});

  final List<ServerWhiteboardLocalStroke> strokes;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintWhiteboardStroke(
        canvas,
        size,
        stroke.points,
        stroke.color,
        stroke.lineWidth.toDouble(),
        palette,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardLocalPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.palette != palette;
}

class _WhiteboardRemoteDraftPainter extends CustomPainter {
  const _WhiteboardRemoteDraftPainter({
    required this.drafts,
    required this.palette,
  });

  final List<ServerWhiteboardLiveDraft> drafts;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    for (final draft in drafts) {
      _paintWhiteboardStroke(
        canvas,
        size,
        draft.points,
        draft.color,
        draft.lineWidth.toDouble(),
        palette,
        opacity: .82,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WhiteboardRemoteDraftPainter oldDelegate) =>
      oldDelegate.drafts != drafts || oldDelegate.palette != palette;
}

class _WhiteboardDraftPainter extends CustomPainter {
  _WhiteboardDraftPainter({
    required this.draft,
    required Listenable repaint,
    required this.color,
    required this.lineWidth,
    required this.palette,
  }) : super(repaint: repaint);

  final List<ServerWhiteboardPoint> draft;
  final ServerWhiteboardColor color;
  final int lineWidth;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWhiteboardStroke(
      canvas,
      size,
      draft,
      color,
      lineWidth.toDouble(),
      palette,
    );
  }

  @override
  bool shouldRepaint(covariant _WhiteboardDraftPainter oldDelegate) =>
      oldDelegate.draft != draft ||
      oldDelegate.color != color ||
      oldDelegate.lineWidth != lineWidth ||
      oldDelegate.palette != palette;
}

void _paintWhiteboardStroke(
  Canvas canvas,
  Size size,
  List<ServerWhiteboardPoint> points,
  ServerWhiteboardColor color,
  double width,
  AppPalette palette, {
  double opacity = 1,
}) {
  if (points.isEmpty) return;
  final offsets = [
    for (final point in points)
      Offset(point.x * size.width, point.y * size.height),
  ];
  final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
  for (final point in offsets.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  final needsOutline =
      color == ServerWhiteboardColor.white &&
      ThemeData.estimateBrightnessForColor(palette.surfaceRaised) ==
          Brightness.light;
  final isDot =
      offsets.length == 1 || offsets.every((point) => point == offsets.first);
  if (needsOutline && isDot) {
    canvas.drawCircle(
      offsets.first,
      width / 2 + 1,
      Paint()
        ..color = palette.borderStrong.withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );
  } else if (needsOutline) {
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.borderStrong.withValues(alpha: opacity)
        ..strokeWidth = width + 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }
  final paint = Paint()
    ..color = _strokeColor(color, palette).withValues(alpha: opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (isDot) {
    canvas.drawCircle(
      offsets.first,
      width / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  canvas.drawPath(path, paint);
}

Color _strokeColor(ServerWhiteboardColor value, AppPalette palette) =>
    switch (value) {
      ServerWhiteboardColor.ink => palette.textPrimary,
      ServerWhiteboardColor.red => const Color(0xFFEF445F),
      ServerWhiteboardColor.orange =>
        ThemeData.estimateBrightnessForColor(palette.surfaceRaised) ==
                Brightness.light
            ? const Color(0xFFA44700)
            : const Color(0xFFFF9F43),
      ServerWhiteboardColor.green =>
        ThemeData.estimateBrightnessForColor(palette.surfaceRaised) ==
                Brightness.light
            ? const Color(0xFF08784E)
            : const Color(0xFF27B67A),
      ServerWhiteboardColor.blue => const Color(0xFF3289F5),
      ServerWhiteboardColor.purple => const Color(0xFFA855F7),
      ServerWhiteboardColor.white => Colors.white,
    };

String _colorLabel(AppLocalizations copy, ServerWhiteboardColor value) =>
    switch (value) {
      ServerWhiteboardColor.ink => copy.text('Ink', 'Atrament'),
      ServerWhiteboardColor.red => copy.text('Red', 'Czerwony'),
      ServerWhiteboardColor.orange => copy.text('Orange', 'Pomarańczowy'),
      ServerWhiteboardColor.green => copy.text('Green', 'Zielony'),
      ServerWhiteboardColor.blue => copy.text('Blue', 'Niebieski'),
      ServerWhiteboardColor.purple => copy.text('Purple', 'Fioletowy'),
      ServerWhiteboardColor.white => copy.text('White', 'Biały'),
    };
