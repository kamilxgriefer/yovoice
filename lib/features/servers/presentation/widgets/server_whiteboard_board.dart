import 'dart:async';

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
    this.compact = false,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerWhiteboardRepository repository;
  final ServerMemberRole? role;
  final bool compact;

  @override
  State<ServerWhiteboardBoard> createState() => _ServerWhiteboardBoardState();
}

class _ServerWhiteboardBoardState extends State<ServerWhiteboardBoard> {
  static const _maximumStrokes = 180;
  static const _maximumPoints = 64;
  static const _lineWidths = <int>[2, 5, 9];

  late Stream<ServerWhiteboardSnapshot> _board;
  final List<ServerWhiteboardPoint> _draft = [];
  ServerWhiteboardColor _color = ServerWhiteboardColor.ink;
  int _lineWidth = 5;
  bool _busy = false;
  String? _error;

  bool get _canDraw =>
      !widget.server.isHeld &&
      widget.role != null &&
      widget.role != ServerMemberRole.guest &&
      widget.repository.currentUserId.isNotEmpty;

  bool get _canClear =>
      !widget.server.isHeld && (widget.role?.canManage ?? false);

  @override
  void initState() {
    super.initState();
    _board = _watch();
  }

  @override
  void didUpdateWidget(covariant ServerWhiteboardBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.server.id != widget.server.id ||
        oldWidget.channel.id != widget.channel.id) {
      _draft.clear();
      _board = _watch();
    }
  }

  Stream<ServerWhiteboardSnapshot> _watch() =>
      widget.repository.watchWhiteboard(widget.server.id, widget.channel.id);

  void _startStroke(Offset position, Size canvasSize) {
    if (!_canDraw || _busy) return;
    setState(() {
      _error = null;
      _draft
        ..clear()
        ..add(_normalized(position, canvasSize));
    });
  }

  void _continueStroke(Offset position, Size canvasSize) {
    if (!_canDraw || _busy || _draft.isEmpty) return;
    final point = _normalized(position, canvasSize);
    final previous = _draft.last;
    final dx = point.x - previous.x;
    final dy = point.y - previous.y;
    // A small normalized threshold keeps the callable payload bounded while
    // retaining enough detail on both a narrow phone and a wide desktop.
    if (dx * dx + dy * dy < 0.000004) return;
    setState(() {
      if (_draft.length < _maximumPoints) {
        _draft.add(point);
      } else {
        _draft[_maximumPoints - 1] = point;
      }
    });
  }

  void _cancelStroke() {
    if (_draft.isEmpty) return;
    setState(_draft.clear);
  }

  Future<void> _finishStroke() async {
    if (!_canDraw || _busy || _draft.isEmpty) return;
    final points = List<ServerWhiteboardPoint>.of(_draft);
    // A tap is a useful mark too. Two equal round-capped points persist it as
    // a dot while keeping the backend's polyline contract uniform.
    if (points.length == 1) points.add(points.first);
    final color = _color;
    final lineWidth = _lineWidth;
    setState(() {
      _busy = true;
      _draft.clear();
      _error = null;
    });
    try {
      await widget.repository.createWhiteboardStroke(
        serverId: widget.server.id,
        channelId: widget.channel.id,
        points: points,
        color: color,
        lineWidth: lineWidth,
        requestId: widget.repository.newRequestId(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = serverActionFailureCopy(
          error,
          AppLocalizations.of(context),
          fallback: AppLocalizations.of(context).text(
            'The line could not be saved. Try again.',
            'Nie udało się zapisać linii. Spróbuj ponownie.',
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(ServerWhiteboardSnapshot snapshot) async {
    if (_busy) return;
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

  Future<void> _confirmClear(ServerWhiteboardSnapshot snapshot) async {
    if (_busy || !_canClear || snapshot.state.isEmpty) return;
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
      _busy = true;
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
      if (mounted) setState(() => _busy = false);
    }
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
          return SingleChildScrollView(
            key: const ValueKey('server-whiteboard-scroll'),
            padding: EdgeInsets.all(widget.compact ? 12 : AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  count: board.state.strokeCount,
                  compact: widget.compact,
                  colors: colors,
                ),
                const SizedBox(height: AppSpacing.md),
                _Toolbar(
                  color: _color,
                  lineWidth: _lineWidth,
                  busy: _busy,
                  canDraw:
                      _canDraw && board.state.strokeCount < _maximumStrokes,
                  canUndo:
                      !_busy &&
                      _canDraw &&
                      board.lastOwnedBy(widget.repository.currentUserId) !=
                          null,
                  showClear: _canClear,
                  canClear: !_busy && _canClear && !board.state.isEmpty,
                  colors: colors,
                  onColor: (value) => setState(() => _color = value),
                  onLineWidth: (value) => setState(() => _lineWidth = value),
                  onUndo: () => unawaited(_undo(board)),
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
                      child: Text(
                        error,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.dangerForeground,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _Canvas(
                  strokes: board.strokes,
                  draft: List.unmodifiable(_draft),
                  draftColor: _color,
                  draftLineWidth: _lineWidth,
                  enabled:
                      _canDraw &&
                      !_busy &&
                      board.state.strokeCount < _maximumStrokes,
                  compact: widget.compact,
                  palette: palette,
                  onStart: _startStroke,
                  onUpdate: _continueStroke,
                  onEnd: () => unawaited(_finishStroke()),
                  onCancel: _cancelStroke,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AccessNote(
                  canDraw: _canDraw,
                  held: widget.server.isHeld,
                  full: board.state.strokeCount >= _maximumStrokes,
                ),
                if (_busy) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const LinearProgressIndicator(
                    key: ValueKey('server-whiteboard-progress'),
                    minHeight: 2,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.compact,
    required this.colors,
  });

  final int count;
  final bool compact;
  final ServerIdentityVisuals colors;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
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
                      'Draw together during the meeting. Every completed line is saved on this server.',
                      'Rysujcie razem podczas spotkania. Każda ukończona linia zapisuje się na tym serwerze.',
                    ),
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.color,
    required this.lineWidth,
    required this.busy,
    required this.canDraw,
    required this.canUndo,
    required this.showClear,
    required this.canClear,
    required this.colors,
    required this.onColor,
    required this.onLineWidth,
    required this.onUndo,
    required this.onClear,
  });

  final ServerWhiteboardColor color;
  final int lineWidth;
  final bool busy;
  final bool canDraw;
  final bool canUndo;
  final bool showClear;
  final bool canClear;
  final ServerIdentityVisuals colors;
  final ValueChanged<ServerWhiteboardColor> onColor;
  final ValueChanged<int> onLineWidth;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('server-whiteboard-toolbar'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final value in ServerWhiteboardColor.values)
            _ColorButton(
              value: value,
              selected: value == color,
              enabled: canDraw && !busy,
              colors: colors,
              onPressed: () => onColor(value),
            ),
          Container(width: 1, height: 32, color: palette.border),
          for (final value in _ServerWhiteboardBoardState._lineWidths)
            _LineWidthButton(
              value: value,
              selected: value == lineWidth,
              enabled: canDraw && !busy,
              colors: colors,
              onPressed: () => onLineWidth(value),
            ),
          Container(width: 1, height: 32, color: palette.border),
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
        ],
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
    required this.strokes,
    required this.draft,
    required this.draftColor,
    required this.draftLineWidth,
    required this.enabled,
    required this.compact,
    required this.palette,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final List<ServerWhiteboardStroke> strokes;
  final List<ServerWhiteboardPoint> draft;
  final ServerWhiteboardColor draftColor;
  final int draftLineWidth;
  final bool enabled;
  final bool compact;
  final AppPalette palette;
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
              values: {'count': strokes.length},
            );
            final hint = enabled
                ? copy.text(
                    'Drag across the canvas to draw.',
                    'Przeciągnij po obszarze, aby rysować.',
                  )
                : copy.text(
                    'This whiteboard is read only for you.',
                    'Ta tablica jest dla Ciebie tylko do odczytu.',
                  );
            return Semantics(
              container: true,
              image: true,
              label: label,
              hint: hint,
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: const ValueKey('server-whiteboard-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: enabled
                      ? (details) => onStart(details.localPosition, size)
                      : null,
                  onPanUpdate: enabled
                      ? (details) => onUpdate(details.localPosition, size)
                      : null,
                  onPanEnd: enabled ? (_) => onEnd() : null,
                  onPanCancel: enabled ? onCancel : null,
                  onTapUp: enabled
                      ? (details) {
                          onStart(details.localPosition, size);
                          onEnd();
                        }
                      : null,
                  child: SizedBox(
                    height: height,
                    width: width,
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
                        child: CustomPaint(
                          painter: _WhiteboardPainter(
                            strokes: strokes,
                            draft: draft,
                            draftColor: draftColor,
                            draftLineWidth: draftLineWidth,
                            palette: palette,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AccessNote extends StatelessWidget {
  const _AccessNote({
    required this.canDraw,
    required this.held,
    required this.full,
  });

  final bool canDraw;
  final bool held;
  final bool full;

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
        : canDraw
        ? copy.text(
            'Lift your finger or pointer to save a line.',
            'Oderwij palec lub wskaźnik, aby zapisać linię.',
          )
        : copy.text(
            'Guests can follow the whiteboard live. Members can also draw.',
            'Goście mogą śledzić tablicę na żywo. Członkowie mogą też rysować.',
          );
    return Text(
      text,
      key: const ValueKey('server-whiteboard-access-note'),
      style: AppTypography.bodySmall.copyWith(color: palette.textSecondary),
    );
  }
}

class _WhiteboardPainter extends CustomPainter {
  const _WhiteboardPainter({
    required this.strokes,
    required this.draft,
    required this.draftColor,
    required this.draftLineWidth,
    required this.palette,
  });

  final List<ServerWhiteboardStroke> strokes;
  final List<ServerWhiteboardPoint> draft;
  final ServerWhiteboardColor draftColor;
  final int draftLineWidth;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = palette.border.withValues(alpha: .52)
      ..strokeWidth = 1;
    for (var step = 1; step < 8; step++) {
      final x = size.width * step / 8;
      final y = size.height * step / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final stroke in strokes) {
      _draw(
        canvas,
        size,
        stroke.points,
        stroke.color,
        stroke.lineWidth.toDouble(),
      );
    }
    _draw(canvas, size, draft, draftColor, draftLineWidth.toDouble());
  }

  void _draw(
    Canvas canvas,
    Size size,
    List<ServerWhiteboardPoint> points,
    ServerWhiteboardColor color,
    double width,
  ) {
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
          ..color = palette.borderStrong
          ..style = PaintingStyle.fill,
      );
    } else if (needsOutline) {
      canvas.drawPath(
        path,
        Paint()
          ..color = palette.borderStrong
          ..strokeWidth = width + 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
    final paint = Paint()
      ..color = _strokeColor(color, palette)
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

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.draft != draft ||
      oldDelegate.draftColor != draftColor ||
      oldDelegate.draftLineWidth != draftLineWidth ||
      oldDelegate.palette != palette;
}

Color _strokeColor(ServerWhiteboardColor value, AppPalette palette) =>
    switch (value) {
      ServerWhiteboardColor.ink => palette.textPrimary,
      ServerWhiteboardColor.red => const Color(0xFFEF445F),
      ServerWhiteboardColor.orange => const Color(0xFFFF9F43),
      ServerWhiteboardColor.green => const Color(0xFF27B67A),
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
