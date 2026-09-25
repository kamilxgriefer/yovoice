import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/inputs/yo_segmented_pill.dart';

import '../../data/models/server_channel.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';
import 'server_panel.dart';
import 'server_waiting_dot.dart';

/// One local tab of the phone surface.
@immutable
class ServerLocalTab {
  const ServerLocalTab({
    required this.label,
    required this.icon,
    required this.key,
    this.attentionLabel,
    this.attentionKey,
  });
  final String label;
  final IconData icon;

  /// Applied to the tab's tappable region.
  final Key key;

  /// When something behind this tab waits for the viewer (new listener
  /// questions behind `Pytania`), the sentence that says so. The tab then
  /// carries the shared [ServerWaitingDot] — keyed [attentionKey] — and reads
  /// the sentence after its name. It is never drawn on the selected tab: the
  /// person is already looking at what it points to. Null draws nothing.
  final String? attentionLabel;
  final Key? attentionKey;
}

/// The shell's own two local tabs: the channel's scene and the conversation
/// beside it. The five template boards add their own (Wydarzenia, Kalendarz,
/// Wspomnienia…) as their slices land.
/// [conversationLabel] names the second tab when the conversation beside this
/// scene is not the server's ordinary chat — board 05 reads its listeners'
/// questions there, so the tab says so instead of `Czat`.
/// [attentionLabel] puts the shared waiting dot on that second tab (a
/// podcast host's unseen listener questions).
List<ServerLocalTab> serverSceneAndChatTabs(
  BuildContext context,
  ServerChannel channel, {
  String? conversationLabel,
  String? attentionLabel,
}) => [
  ServerLocalTab(
    key: const ValueKey('server-tab-scene'),
    label: channel.name,
    icon: serverChannelIcon(channel.kind),
  ),
  ServerLocalTab(
    key: const ValueKey('server-tab-chat'),
    label: conversationLabel ?? AppLocalizations.of(context).serverChat,
    icon: Icons.forum_outlined,
    attentionLabel: attentionLabel,
    attentionKey: const ValueKey('server-tab-chat-waiting'),
  ),
];

/// The phone's local tabs, always fully on screen.
///
/// Up to three tabs render as the app's segmented pill — the friends board's
/// `Salon | Czat | Wydarzenia`. Four or more render as an icon-over-label row —
/// the family board's `Dom | Kanały | Kalendarz | Wspomnienia` — because four
/// Polish labels cannot share one pill at 320 px without hiding a word.
/// Neither variant scrolls: a tab that is off screen is undiscoverable, which
/// is the defect the immersive chrome already paid for. Label scaling is
/// clamped at [maxTextScale] so a 200 % setting shrinks nothing below its
/// target and hides no tab; an ellipsis is the last resort.
class ServerLocalTabs extends StatelessWidget {
  const ServerLocalTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.colors,
    super.key,
  }) : assert(tabs.length > 0, 'Local tabs need a tab.');

  final List<ServerLocalTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// The template's visuals for the selected icon-over-label tab.
  final ServerIdentityVisuals? colors;

  /// The accessibility specialist's accepted remediation for a control that
  /// must fit: labels grow to 1.6×, targets never shrink.
  static const maxTextScale = 1.6;

  /// A pill segment carries its icon beside the label only with this much
  /// width; below it the label alone is what fits.
  static const iconThreshold = 132.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final perTab = constraints.maxWidth / tabs.length;
      final Widget body;
      if (tabs.length <= 3) {
        final roomy = perTab >= iconThreshold;
        body = YoSegmentedPill(
          width: double.infinity,
          fontSize: 12,
          segments: [
            for (var index = 0; index < tabs.length; index++)
              _segment(tabs[index], roomy, index == selectedIndex),
          ],
          selectedIndex: selectedIndex,
          onSelected: onSelected,
        );
      } else {
        body = _IconLabelRow(
          tabs: tabs,
          selectedIndex: selectedIndex.clamp(0, tabs.length - 1),
          onSelected: onSelected,
          colors: colors,
        );
      }
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: body,
      );
    },
  );

  static YoSegmentedPillSegment _segment(
    ServerLocalTab tab,
    bool roomy,
    bool selected,
  ) {
    final attention = selected ? null : tab.attentionLabel;
    return YoSegmentedPillSegment(
      key: tab.key,
      label: tab.label,
      icon: roomy ? tab.icon : null,
      semanticLabel: attention == null ? null : '${tab.label}, $attention',
      badge: attention == null
          ? null
          : ServerWaitingDot(key: tab.attentionKey, semanticLabel: attention),
    );
  }
}

class _IconLabelRow extends StatelessWidget {
  const _IconLabelRow({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.colors,
  });
  final List<ServerLocalTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ServerIdentityVisuals? colors;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('server-local-tabs-row'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.md,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
              child: _IconLabelTab(
                tab: tabs[index],
                selected: index == selectedIndex,
                colors: colors,
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconLabelTab extends StatefulWidget {
  const _IconLabelTab({
    required this.tab,
    required this.selected,
    required this.colors,
    required this.onTap,
  });
  final ServerLocalTab tab;
  final bool selected;
  final ServerIdentityVisuals? colors;
  final VoidCallback onTap;

  @override
  State<_IconLabelTab> createState() => _IconLabelTabState();
}

class _IconLabelTabState extends State<_IconLabelTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground = selected
        ? (widget.colors?.selectedForeground ?? scheme.primary)
        : palette.textSecondary;
    final wash = widget.colors?.selectedWash ?? scheme.primaryContainer;
    final attention = selected ? null : widget.tab.attentionLabel;
    return Semantics(
      button: true,
      selected: selected,
      label: attention == null
          ? widget.tab.label
          : '${widget.tab.label}, $attention',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: widget.tab.key,
          // The selected tab stays focusable so keyboard traversal never
          // skips a control; activating it again changes nothing.
          onTap: selected ? () {} : widget.onTap,
          borderRadius: AppRadius.sm,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? wash : null,
              borderRadius: AppRadius.sm,
              border: _focused
                  ? Border.all(color: palette.focus, width: 2)
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ServerWaitingDot.on(
                  waiting: attention != null,
                  semanticLabel: attention ?? '',
                  dotKey: widget.tab.attentionKey,
                  child: Icon(widget.tab.icon, size: 20, color: foreground),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
