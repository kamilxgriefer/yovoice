import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/theme/server_identity.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

/// A server's face: its initial on the server identity's icon surface, in a
/// squircle with the servers' radius (`AppRadius.md`, 14) at every size.
///
/// Colours come from one source, `ServerIdentity.of(type).resolve(...)`, so
/// the face is the same in the rail, a list or a header. The initial stays a
/// plain [Text] (tests find it by text) and its text scale is clamped to
/// [maxTextScale] so a fixed-size squircle never clips its own glyph.
class YoServerTile extends StatelessWidget {
  const YoServerTile({
    required this.initial,
    required this.type,
    this.size = 44,
    this.bordered = true,
    this.textStyle,
    super.key,
  });

  /// `Server.initial` — already uppercased, `YO` for an unnamed server.
  final String initial;
  final ServerType type;
  final double size;

  /// Draws the identity's 1 px `iconBorder` around the surface.
  final bool bordered;

  /// Defaults to `titleMedium` at w800 in the identity's foreground; a
  /// caller overriding it keeps the foreground unless it sets a colour.
  final TextStyle? textStyle;

  static const double maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final identity = ServerIdentity.of(
      type,
    ).resolve(Theme.of(context).brightness);
    final style =
        (textStyle ??
                AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w800))
            .copyWith(color: textStyle?.color ?? identity.foreground);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: identity.iconSurface,
        borderRadius: AppRadius.md,
        border: bordered ? Border.all(color: identity.iconBorder) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
        textScaler: MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: maxTextScale),
        style: style,
      ),
    );
  }
}

/// One server in a server rail: a 44 px [YoServerTile] squircle inside a
/// 48 px target, with a selection pill on the rail's start edge.
///
/// The pill is the only selected / hover mark (the tap region's own selected
/// ring is suppressed); it animates through [AppMotion.quick], which resolves
/// to zero under Reduce Motion. Selection is exposed to assistive technology
/// through the region's `selected` flag and [semanticLabel] (localized by the
/// caller, typically the server name).
///
/// There is deliberately no unread badge or counter: server channels have no
/// read cursor, so any such mark would be invented (ADR-209). The one mark it
/// can carry is [attention], which the caller builds only from a real cursor
/// — a podcast host's unseen listener questions (ADR "listener questions
/// dot") — and which is absent otherwise.
/// The caller keys the item (`server-rail-<id>`) and owns the list, the
/// selected id and the navigation.
class YoServerRailItem extends StatefulWidget {
  const YoServerRailItem({
    required this.initial,
    required this.type,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
    this.tooltip,
    this.focusNode,
    this.attention,
    super.key,
  });

  final String initial;
  final ServerType type;
  final String semanticLabel;
  final bool selected;
  final VoidCallback? onTap;

  /// A small "somebody is waiting" mark pinned to the squircle's top end
  /// corner, carrying its own spoken label. Null (the default, and the only
  /// value without a cursor behind it) draws nothing.
  final Widget? attention;

  /// Hover label on pointer platforms; defaults to [semanticLabel].
  final String? tooltip;
  final FocusNode? focusNode;

  /// The squircle.
  static const double tileSize = 44;

  /// The target around it (≥ 44 in both axes).
  static const double targetSize = 48;

  /// The slot a rail column reserves per item (brief: 64–68).
  static const double railWidth = 64;

  static const double pillWidth = 4;
  static const double pillSelectedHeight = 32;
  static const double pillHoverHeight = 16;

  @override
  State<YoServerRailItem> createState() => _YoServerRailItemState();
}

class _YoServerRailItemState extends State<YoServerRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final pillHeight = widget.selected
        ? YoServerRailItem.pillSelectedHeight
        : _hovered && widget.onTap != null
        ? YoServerRailItem.pillHoverHeight
        : 0.0;
    return SizedBox(
      width: YoServerRailItem.railWidth,
      height: YoServerRailItem.targetSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedContainer(
                key: const ValueKey('yo-server-rail-item-pill'),
                duration: AppMotion.resolve(context, AppMotion.quick),
                curve: AppMotion.standardCurve,
                width: YoServerRailItem.pillWidth,
                height: pillHeight,
                decoration: BoxDecoration(
                  color: palette.textPrimary,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
          ),
          AccessibleTapRegion(
            onTap: widget.onTap,
            semanticLabel: widget.semanticLabel,
            tooltip: widget.tooltip ?? widget.semanticLabel,
            selected: widget.selected,
            selectedBorderColor: Colors.transparent,
            borderRadius: 14,
            minimumSize: const Size.square(YoServerRailItem.targetSize),
            focusNode: widget.focusNode,
            onHover: (hovered) {
              if (_hovered != hovered) setState(() => _hovered = hovered);
            },
            child: widget.attention == null
                ? YoServerTile(initial: widget.initial, type: widget.type)
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      YoServerTile(initial: widget.initial, type: widget.type),
                      PositionedDirectional(
                        top: -2,
                        end: -2,
                        child: widget.attention!,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
