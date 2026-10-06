import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/inputs/yo_text_field.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';

import '../../data/models/server.dart';
import '../../data/server_links.dart';
import '../server_localized_copy.dart';
import '../servers_board_copy.dart';
import '../theme/server_identity.dart';
import 'server_channel_scene.dart' show ServerLiveLamp;
import 'server_waiting_dot.dart';

/// The numbers of the Servers board (owner's choice 2026-10-03, sheet
/// `2_hub`, option A; ADR-239).
abstract final class ServersBoardMetrics {
  /// A "Twoje serwery" row at 100 % text.
  static const double rowMinHeight = 64;
  static const double rowTile = 44;
  static const double rowPaddingH = 12;
  static const double rowPaddingV = 10;

  /// The divider starts under the name, not under the squircle.
  static const double rowDividerIndent = rowPaddingH + rowTile + 12;

  /// Rows a column shows before "Pokaż wszystkie".
  static const int collapsedRows = 5;

  /// The narrowest a "Twoje serwery" column gets before the list takes one
  /// column fewer (at 100 % text; it grows with the text scale).
  static const double rowColumnMinWidth = 320;

  /// Two columns at most, as on the owner's tablet and desktop frames.
  static const int rowMaxColumns = 2;

  /// A public card: the identity band, the squircle that overlaps it and the
  /// action pill.
  static const double cardBand = 72;
  static const double cardTile = 40;
  static const double cardTileRing = 3;
  static const double cardAction = 36;

  /// Text scale from which rows and cards give their text the full width.
  static const double largeText = 1.3;

  /// The whole board's gap between sibling blocks.
  static const double gap = AppRhythm.item;

  /// Whether a row of [rowWidth] stacks at [textScale]: at enlarged text a
  /// narrow row cannot hold the squircle, the words and the chevron side by
  /// side (the name would be two short lines and an ellipsis), so the words
  /// go under the squircle at the row's full width. One predicate for the
  /// row and for the divider its group draws above it.
  static bool rowStacks(double rowWidth, double textScale) =>
      textScale > largeText &&
      rowWidth - 2 * rowPaddingH - rowTile - 12 - 8 - 40 < 160 * textScale;
}

bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) / 16 >
    ServersBoardMetrics.largeText;

/// A grouped R2 block: the top-lit fill, the hairline edge and the rows
/// inside it separated by hairlines that start under the names.
class ServersBoardGroup extends StatelessWidget {
  const ServersBoardGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Container(
      decoration: AppFinish.blockFill(palette, highContrast: highContrast),
      // The edge is a foreground so a row's hover wash never covers it.
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.block,
        border: AppFinish.blockEdge(palette, highContrast: highContrast),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.block,
        child: Material(
          type: MaterialType.transparency,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The divider starts where the rows' words start: under the
              // name beside the squircle, or — once the rows stack — at the
              // row's own inset, where the words then begin.
              final indent =
                  ServersBoardMetrics.rowStacks(constraints.maxWidth, textScale)
                  ? ServersBoardMetrics.rowPaddingH
                  : ServersBoardMetrics.rowDividerIndent;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: indent,
                        color: highContrast
                            ? palette.borderStrong
                            : palette.hairline,
                      ),
                    children[i],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One of the account's servers on the board: squircle, name, what kind of
/// server it is and how many members it has, then the LIVE lamp or a chevron.
///
/// The lamp is drawn only when [live] is true, and the caller sets it only
/// from the channel documents' liveness projection (`ServerDirectoryLiveness`).
///
/// The row's actions (delete for the owner, leave otherwise) open from a long
/// press, a secondary click, a screen reader's custom action, and — where
/// there is a pointer or a keyboard — from the `…` button that takes the
/// chevron's place while the row is hovered or holds keyboard focus. At rest
/// the row is exactly the chosen frame: no button.
class ServerBoardRow extends StatefulWidget {
  const ServerBoardRow({
    required this.server,
    required this.onTap,
    this.onActions,
    this.live = false,
    this.questionsWaiting = false,
    this.busy = false,
    super.key,
  });

  final Server server;
  final VoidCallback onTap;

  /// Opens the row's action sheet. Null for a read-only repository.
  final VoidCallback? onActions;

  /// A conversation is live in this server right now.
  final bool live;

  /// Listener questions wait for this podcast host: the squircle carries the
  /// shared waiting dot.
  final bool questionsWaiting;

  /// A delete or leave for this row is in flight.
  final bool busy;

  @override
  State<ServerBoardRow> createState() => _ServerBoardRowState();
}

class _ServerBoardRowState extends State<ServerBoardRow> {
  bool _hovered = false;
  bool _focusWithin = false;

  /// The row's own node: the ring follows its PRIMARY focus, so the `…`
  /// button taking focus does not light a second ring around the whole row.
  final FocusNode _focusNode = FocusNode(debugLabel: 'ServerBoardRow');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    final focused = _focusNode.hasPrimaryFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    super.dispose();
  }

  static InteractiveInkFeatureFactory get _splashFactory =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? InkSparkle.splashFactory
      : NoSplash.splashFactory;

  bool get _keyboardFocusWithin =>
      _focusWithin &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// A narrow row at enlarged text stacks — squircle and chevron on the
  /// first line, the words under them at the row's full width (the
  /// directory's contract since `test/server_workspace_test.dart` "large
  /// directory names…"); see [ServersBoardMetrics.rowStacks].
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _row(
      context,
      stacked: ServersBoardMetrics.rowStacks(
        constraints.maxWidth,
        MediaQuery.textScalerOf(context).scale(16) / 16,
      ),
    ),
  );

  Widget _row(BuildContext context, {required bool stacked}) {
    final server = widget.server;
    final busy = widget.busy;
    final actions = widget.onActions;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final large = _largeText(context);
    final name = server.name.isEmpty ? copy.serversTitle : server.name;
    final meta = serverMetaLine(
      copy.serverKindSubtitle(server.type, server.privacy),
      copy.serverMembers(server.memberCount),
    );
    // The lamp's dot and its word say the same thing here ("na żywo"), so
    // a screen reader hears it once, not once for each.
    final lamp = widget.live
        ? Semantics(
            label: copy.serversBoardLive,
            child: ExcludeSemantics(
              child: ServerLiveLamp(
                key: ValueKey('server-directory-live-${server.id}'),
                semanticLabel: copy.serversBoardLive,
                label: copy.serversBoardLive,
                style: AppTypography.labelMedium.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          )
        : null;
    final avatar = ServerWaitingDot.on(
      waiting: widget.questionsWaiting,
      semanticLabel: copy.serverQuestionsWaitingLabel,
      dotKey: ValueKey('server-directory-questions-waiting-${server.id}'),
      child: YoServerTile(
        initial: server.initial,
        type: server.type,
        size: ServersBoardMetrics.rowTile,
      ),
    );
    final details = Column(
      // Stacked, each line takes the row's full width.
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: stacked
              ? 3
              : large
              ? 2
              : 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.rowTitle.copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          meta,
          // Two lines at every text size: one fits Polish and English, but
          // in the longer languages ("Только по приглашению · Участников:
          // 6") a single line cut the member count off the end. The row
          // grows instead; `serverMetaLine` keeps the count whole.
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.rowPreview.copyWith(
            color: palette.textSecondary,
          ),
        ),
        // At enlarged text the lamp takes a line of its own instead of
        // squeezing the name.
        if (lamp != null && large) ...[
          const SizedBox(height: 4),
          Align(alignment: AlignmentDirectional.centerStart, child: lamp),
        ],
      ],
    );

    final showsActions =
        actions != null && !busy && (_hovered || _keyboardFocusWithin);
    final Widget end;
    if (busy) {
      end = const SizedBox.square(
        dimension: 40,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (showsActions) {
      end = IconButton(
        key: ValueKey('server-directory-actions-${server.id}'),
        onPressed: actions,
        tooltip: copy.serverManage,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: palette.textSecondary,
        ),
        icon: const Icon(Icons.more_horiz_rounded),
      );
    } else if (lamp != null && !large) {
      end = lamp;
    } else {
      // The chevron keeps the `…` button's slot, so hover never moves the
      // text beside it.
      end = SizedBox(
        width: actions == null ? null : 40,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          widthFactor: actions == null ? 1 : null,
          child: Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: palette.textTertiary,
          ),
        ),
      );
    }
    final trailing = lamp != null && !large && showsActions
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [lamp, const SizedBox(width: 4), end],
          )
        : end;

    final pressedWash = AppFinish.blockPressedWash(palette);
    final hoverWash = palette.textPrimary.withValues(
      alpha: palette.isDark ? .035 : .03,
    );
    return Semantics(
      customSemanticsActions: actions == null || busy
          ? null
          : {CustomSemanticsAction(label: copy.serverManage): actions},
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) {
          if (_focusWithin != value) setState(() => _focusWithin = value);
        },
        child: Stack(
          children: [
            InkWell(
              key: ValueKey('server-directory-${server.id}'),
              focusNode: _focusNode,
              onTap: busy ? null : widget.onTap,
              onLongPress: busy ? null : actions,
              onSecondaryTap: busy ? null : actions,
              splashFactory: _splashFactory,
              onHover: (value) {
                if (_hovered != value) setState(() => _hovered = value);
              },
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) return pressedWash;
                if (states.contains(WidgetState.hovered)) return hoverWash;
                // Keyboard focus is the ring, not a wash.
                return Colors.transparent;
              }),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ServersBoardMetrics.rowMinHeight,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: ServersBoardMetrics.rowPaddingH,
                    end: ServersBoardMetrics.rowPaddingH,
                    top: ServersBoardMetrics.rowPaddingV,
                    bottom: ServersBoardMetrics.rowPaddingV,
                  ),
                  child: stacked
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [avatar, const Spacer(), trailing]),
                            const SizedBox(height: 10),
                            details,
                          ],
                        )
                      : Row(
                          children: [
                            avatar,
                            const SizedBox(width: 12),
                            Expanded(child: details),
                            const SizedBox(width: 8),
                            trailing,
                          ],
                        ),
                ),
              ),
            ),
            // The keyboard ring: 2 px `focus`, 3 px inside the row so the
            // group's rounded corners never cut it, and never in layout.
            if (_focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.md,
                        border: Border.all(color: palette.focus, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A public server a person can look at and join: the template's identity
/// band, the squircle overlapping it, the name, "Społeczność · 312 osób" and
/// the `Zobacz` pill.
///
/// The whole card is ONE control (one focus stop, one screen-reader button
/// named after the server); the pill is its visible affordance, not a second
/// button. Opening it leads to the workspace's public admission, where the
/// person reads what the server is and decides to join.
class ServerPublicCard extends StatefulWidget {
  const ServerPublicCard({
    required this.server,
    required this.onOpen,
    super.key,
  });

  final Server server;
  final VoidCallback onOpen;

  @override
  State<ServerPublicCard> createState() => _ServerPublicCardState();
}

class _ServerPublicCardState extends State<ServerPublicCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final identity = ServerIdentity.of(server.type);
    final visuals = identity.resolve(Theme.of(context).brightness);
    final name = server.name.isEmpty ? copy.serversTitle : server.name;
    final meta = serverMetaLine(
      copy.serverKindSubtitle(server.type, server.privacy),
      copy.serverMembers(server.memberCount),
    );
    final fill = AppFinish.blockFill(
      palette,
      hovered: _hovered,
      highContrast: highContrast,
    );
    final Border edge = _focused
        ? Border.all(color: palette.focus, width: 2)
        : AppFinish.blockEdge(
            palette,
            hovered: _hovered,
            highContrast: highContrast,
          );
    const band = ServersBoardMetrics.cardBand;
    const tile = ServersBoardMetrics.cardTile;
    const ring = ServersBoardMetrics.cardTileRing;
    final pill = Container(
      constraints: const BoxConstraints(
        minHeight: ServersBoardMetrics.cardAction,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      alignment: Alignment.center,
      decoration: AppFinish.glassDecoration(
        palette,
        radius: AppRadius.pill,
        hovered: _hovered,
        highContrast: highContrast,
      ),
      child: Text(
        copy.serversBoardView,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: .1,
          color: palette.interactiveForeground,
        ),
      ),
    );
    // Two parts pushed apart, so cards stretched to one height in a grid
    // row keep their pills on one line; unbounded, the card shrink-wraps.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: band + tile / 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    top: 0,
                    height: band,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: highContrast ? visuals.iconSurface : null,
                        gradient: highContrast ? null : visuals.unlitGradient,
                      ),
                      child: highContrast
                          ? null
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: AppFinish.liveCorner(
                                  identity.accent,
                                  palette,
                                  shortestSide: band,
                                ),
                              ),
                            ),
                    ),
                  ),
                  PositionedDirectional(
                    start: 12,
                    top: band - tile / 2 - ring,
                    child: Container(
                      padding: const EdgeInsets.all(ring),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(17),
                        ),
                      ),
                      child: YoServerTile(
                        initial: server.initial,
                        type: server.type,
                        size: tile,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.rowTitle.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: pill,
        ),
      ],
    );
    return Semantics(
      container: true,
      button: true,
      label: '$name, $meta. ${copy.serversBoardView}',
      onTap: widget.onOpen,
      child: ExcludeSemantics(
        child: YoPressFeedback(
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.quick),
            curve: AppMotion.standardCurve,
            decoration: BoxDecoration(
              borderRadius: AppRadius.block,
              boxShadow: fill.boxShadow,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: AppRadius.block,
              border: edge,
            ),
            child: Material(
              key: ValueKey('server-public-${server.id}'),
              color: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.block,
              ),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(
                  color: fill.color,
                  gradient: fill.gradient,
                  borderRadius: AppRadius.block,
                ),
                child: InkWell(
                  onTap: widget.onOpen,
                  splashFactory: NoSplash.splashFactory,
                  onHover: (value) {
                    if (_hovered != value) setState(() => _hovered = value);
                  },
                  onFocusChange: (value) {
                    if (_focused != value) setState(() => _focused = value);
                  },
                  overlayColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.pressed)
                        ? AppFinish.blockPressedWash(palette)
                        : Colors.transparent,
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first-run invitation that takes "Twoje serwery"'s place for an
/// account with no server: the real logo, one line, and the two ways in.
class ServersNewcomerBlock extends StatelessWidget {
  const ServersNewcomerBlock({
    required this.onCreate,
    required this.onJoinLink,
    this.lifted = true,
    super.key,
  });

  final VoidCallback onCreate;

  /// Null hides "Dołącz z linku".
  final VoidCallback? onJoinLink;

  /// Whether "Stwórz serwer" is this screen's one lifted action. False where
  /// the desktop rail's own "Stwórz serwer" already owns the lift.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return Container(
      key: const ValueKey('servers-newcomer'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: AppFinish.block(palette, highContrast: highContrast),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const YoBrandMark(key: ValueKey('servers-empty-logo'), size: 56),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              copy.serversBoardNewcomerTitle,
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            // The gradient CTA is 44 px tall and the tonal button's target
            // 48: on one line they share a centre, not a top edge.
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              YoGradientFilledButton(
                buttonKey: const ValueKey('servers-empty-create'),
                onPressed: onCreate,
                emphasis: lifted
                    ? YoActionEmphasis.lifted
                    : YoActionEmphasis.flat,
                icon: const Icon(Icons.add_rounded),
                child: Text(copy.serversBoardCreate),
              ),
              if (onJoinLink != null)
                OutlinedButton.icon(
                  key: const ValueKey('servers-empty-join-link'),
                  onPressed: onJoinLink,
                  style:
                      AppFinish.tonalNeutral(
                        palette,
                        highContrast: highContrast,
                      ).merge(
                        OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(copy.serversBoardJoinLink),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The board's "+": the brand disc that opens "Stwórz serwer / Dołącz z
/// linku".
class ServersAddButton extends StatefulWidget {
  const ServersAddButton({
    required this.onPressed,
    this.size = 40,
    this.lifted = true,
    super.key,
  });

  final VoidCallback onPressed;
  final double size;

  /// Whether the disc carries this screen's one CTA lift.
  final bool lifted;

  @override
  State<ServersAddButton> createState() => _ServersAddButtonState();
}

class _ServersAddButtonState extends State<ServersAddButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).serversBoardAdd;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: AccessibleTapRegion(
        key: const ValueKey('servers-add'),
        semanticLabel: label,
        onTap: widget.onPressed,
        circular: true,
        // The disc draws its own hover and focus.
        paintsIndicators: false,
        onHover: (value) {
          if (_hovered != value) setState(() => _hovered = value);
        },
        onFocusChange: (value) {
          if (_focused != value) setState(() => _focused = value);
        },
        child: ExcludeSemantics(
          child: YoPressFeedback(
            scale: YoPressFeedback.disc,
            child: YoGradientDisc(
              size: widget.size,
              icon: Icons.add_rounded,
              emphasis: widget.lifted
                  ? YoDiscEmphasis.lift
                  : YoDiscEmphasis.rest,
              gloss: true,
              hovered: _hovered,
              focused: _focused,
            ),
          ),
        ),
      ),
    );
  }
}

/// What the "+" sheet can start. `Nadaj LIVE` joins this list with the LIVE
/// wave; an action exists here only when the app can really do it.
enum ServersAddAction { create, joinLink }

/// The "+" sheet: one row per action that exists today.
Future<ServersAddAction?> showServersAddSheet(
  BuildContext context, {
  bool joinLink = true,
}) => showModalBottomSheet<ServersAddAction>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
  builder: (sheetContext) {
    final copy = AppLocalizations.of(sheetContext);
    final scheme = Theme.of(sheetContext).colorScheme;
    final palette = sheetContext.appPalette;
    final highContrast = MediaQuery.highContrastOf(sheetContext);
    Widget row(ServersAddAction action, IconData icon, String label) =>
        ListTile(
          key: ValueKey(switch (action) {
            ServersAddAction.create => 'servers-create',
            ServersAddAction.joinLink => 'servers-join-link',
          }),
          minTileHeight: 60,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Container(
            width: 40,
            height: 40,
            decoration: AppFinish.glyphBox(scheme, highContrast: highContrast),
            child: Icon(icon, size: 20, color: palette.interactiveForeground),
          ),
          title: Text(
            label,
            style: AppTypography.rowTitle.copyWith(color: palette.textPrimary),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: palette.textTertiary,
          ),
          onTap: () => Navigator.of(sheetContext).pop(action),
        );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          key: const ValueKey('servers-add-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              ServersAddAction.create,
              Icons.add_rounded,
              copy.serversBoardCreate,
            ),
            if (joinLink)
              row(
                ServersAddAction.joinLink,
                Icons.link_rounded,
                copy.serversBoardJoinLink,
              ),
            const SizedBox(height: AppRhythm.tight),
          ],
        ),
      ),
    );
  },
);

/// Reads a pasted server link with the same parsers the app's entry URL goes
/// through (`MainShell`): the canonical `?server=` contract first, the
/// historic `?club=` one second. Anything else is not a server link.
///
/// The only leniency is for how people paste: surrounding whitespace, and a
/// link copied without its scheme.
ServerLinkTarget? parsePastedServerLink(String input) {
  var text = input.trim();
  if (text.isEmpty || text.length > 512 || text.contains(RegExp(r'\s'))) {
    return null;
  }
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  final current = parseServerLink(uri);
  if (current != null) return current;
  final legacy = parseLegacyClubServerLink(uri);
  return legacy == null ? null : ServerLinkTarget(serverId: legacy);
}

/// "Dołącz z linku": paste a server link, get the server it points at.
///
/// It only resolves the link. Opening the server — and, for a public one,
/// joining it — is the workspace's own admission, exactly as when the same
/// link is the app's entry URL.
Future<ServerLinkTarget?> showServerJoinLinkSheet(BuildContext context) =>
    showModalBottomSheet<ServerLinkTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: const _ServerJoinLinkSheet(),
      ),
    );

class _ServerJoinLinkSheet extends StatefulWidget {
  const _ServerJoinLinkSheet();

  @override
  State<_ServerJoinLinkSheet> createState() => _ServerJoinLinkSheetState();
}

class _ServerJoinLinkSheetState extends State<_ServerJoinLinkSheet> {
  final _link = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _submit() {
    final target = parsePastedServerLink(_link.text);
    if (target == null) {
      setState(
        () => _error = AppLocalizations.of(context).serversJoinLinkInvalid,
      );
      return;
    }
    Navigator.of(context).pop(target);
  }

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      // A clipboard the platform refuses to read is an empty clipboard.
      text = null;
    }
    if (!mounted || text == null || text.trim().isEmpty) return;
    setState(() {
      _link.text = text!.trim();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    return SingleChildScrollView(
      key: const ValueKey('servers-join-link-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              copy.serversBoardJoinLink,
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            copy.serversJoinLinkBody,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // The label is a sibling `Text`; merging gives the input its name
          // (see `ServerCreateChannelSheet`).
          MergeSemantics(
            child: YoTextField(
              key: const ValueKey('servers-join-link-field'),
              controller: _link,
              label: copy.serversJoinLinkLabel,
              hint: 'https://$serverLinkHost/?server=…',
              errorText: _error,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              maxLength: 512,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('servers-join-link-paste'),
                onPressed: _paste,
                style:
                    AppFinish.tonalNeutral(
                      palette,
                      highContrast: highContrast,
                    ).merge(
                      OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(copy.serversJoinLinkPaste),
              ),
              FilledButton(
                key: const ValueKey('servers-join-link-open'),
                onPressed: _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(copy.serversJoinLinkOpen),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
