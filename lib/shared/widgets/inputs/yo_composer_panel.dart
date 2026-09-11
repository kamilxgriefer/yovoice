import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/features/media/data/services/gif_message_controller.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_picker.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_picker.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_recents.dart';

export 'package:yovoice/shared/widgets/inputs/yo_emoji_picker.dart';

/// Which body the composer panel is showing.
///
/// A screen holds `YoComposerPanelTab?` — `null` means closed — instead of one
/// bool per picker. That is the whole point of this widget: with a single
/// nullable enum and a single mounted body, TWO STACKED PANELS ARE
/// STRUCTURALLY IMPOSSIBLE rather than merely prevented by careful code. The
/// widget tests assert that `ValueKey('emoji-picker')` and
/// `ValueKey('gif-picker')` are never simultaneously in the tree.
enum YoComposerPanelTab { emoji, gif }

/// Remembers which tab the panel was last opened on.
///
/// Follows the [AppPreferencesStore] pattern rather than joining
/// [AppPreferences], for the same reason [YoEmojiRecentsStore] does: this is an
/// interaction detail that changes whenever somebody switches tab, not a
/// setting the Settings screen owns, and putting it on the preferences object
/// would rebuild every consumer of `AppPreferences.value` on each switch.
///
/// A failed read or an unknown stored value both mean Emoji — the tab that is
/// always available.
class YoComposerPanelTabStore {
  YoComposerPanelTabStore({AppPreferencesStore? store})
    : _store = store ?? SharedPreferencesAppPreferencesStore();

  static final instance = YoComposerPanelTabStore();

  static const _key = 'composer.panel_tab.v1';

  final AppPreferencesStore _store;
  YoComposerPanelTab _value = YoComposerPanelTab.emoji;
  bool _loaded = false;

  YoComposerPanelTab get value => _value;

  Future<YoComposerPanelTab> load() async {
    if (_loaded) return _value;
    String? stored;
    try {
      stored = await _store.read(_key);
    } catch (_) {
      stored = null;
    }
    _value = YoComposerPanelTab.values.firstWhere(
      (candidate) => candidate.name == stored,
      orElse: () => YoComposerPanelTab.emoji,
    );
    _loaded = true;
    return _value;
  }

  Future<void> remember(YoComposerPanelTab tab) async {
    _value = tab;
    _loaded = true;
    try {
      await _store.write(_key, tab.name);
    } catch (_) {
      // The choice still holds for this session; only persistence is lost.
    }
  }

  @visibleForTesting
  static YoComposerPanelTabStore inMemory({YoComposerPanelTab? initial}) {
    return YoComposerPanelTabStore(store: _InMemoryTabStore(initial?.name));
  }
}

class _InMemoryTabStore implements AppPreferencesStore {
  _InMemoryTabStore(this._value);

  String? _value;

  @override
  Future<String?> read(String key) async => _value;

  @override
  Future<void> write(String key, String value) async => _value = value;
}

/// The panel that takes the system keyboard's place under a composer.
///
/// It is a plain sibling BELOW the composer in a column, never a sheet or an
/// overlay: the composer — and with it the send button — is laid out first and
/// can never be covered. That is a structural guarantee rather than a computed
/// one, which is why it survives text scaling, a short viewport and a long
/// draft message.
///
/// [YoEmojiPicker] is not modified by any of this. It becomes the Emoji tab's
/// body through its existing `height` override, so every surface that has not
/// been migrated keeps working exactly as before.
class YoComposerPanel extends StatelessWidget {
  const YoComposerPanel({
    required this.tab,
    required this.onTabChanged,
    required this.onEmojiSelected,
    super.key,
    this.onBackspace,
    this.emojiRecentsStore,
    this.gifService,
    this.gifRecentsStore,
    this.onGifSelected,
    this.onGifReport,
    this.gifDelivery,
    this.gifUnavailableReason,
    this.gifAutoLoad = true,
    this.height,
    this.compact = false,
  });

  final YoComposerPanelTab tab;
  final ValueChanged<YoComposerPanelTab> onTabChanged;

  final ValueChanged<String> onEmojiSelected;
  final VoidCallback? onBackspace;
  final YoEmojiRecentsStore? emojiRecentsStore;

  /// Omit to render the GIF tab in its disabled state. A composer with no
  /// service is a composer with no GIF path, and offering a working-looking
  /// picker there would be exactly the faked feature CLAUDE.md forbids.
  final GifCatalogService? gifService;
  final YoGifRecentsStore? gifRecentsStore;
  final ValueChanged<GifAsset>? onGifSelected;
  final ValueChanged<GifAsset>? onGifReport;
  final GifMessageController? gifDelivery;

  /// Why the GIF tab is disabled on THIS surface, when it is. Distinct from
  /// the server's reason: a composer whose send path does not exist yet says
  /// so, rather than blaming a missing API key.
  final GifUnavailableReason? gifUnavailableReason;

  final bool gifAutoLoad;

  /// Overrides the computed panel height. Used by the room chat sheet, which
  /// already knows how much room its own panel can spare.
  final double? height;

  /// A short panel: the tab strip shrinks and the GIF picker drops its
  /// recents row rather than compressing everything into an unusable strip.
  final bool compact;

  bool get _gifEnabled => gifService != null && onGifSelected != null;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;

    final panelHeight = height ?? yoComposerPanelHeight(media, scaler);
    final stripHeight = _stripHeight(scaler, panelHeight);
    // The body gets everything the strip does not, so the panel total still
    // matches the keyboard height it replaced and the composer does not jump.
    final bodyHeight = math.max(96.0, panelHeight - stripHeight);

    return DecoratedBox(
      key: const ValueKey('composer-panel'),
      decoration: BoxDecoration(
        color: palette.navigationSurface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: _TabStrip(
                tab: tab,
                height: stripHeight,
                palette: palette,
                copy: copy,
                onTabChanged: onTabChanged,
              ),
            ),
          ),
          // EXACTLY ONE BODY IS EVER MOUNTED. Not an IndexedStack, not two
          // Offstage children — a switch. Anything that keeps both alive
          // reintroduces the stacked-panel state this widget exists to make
          // unrepresentable, and would also leave a GIF grid fetching in the
          // background while somebody browses emoji.
          switch (tab) {
            YoComposerPanelTab.emoji => YoEmojiPicker(
              height: bodyHeight,
              onSelected: onEmojiSelected,
              onBackspace: onBackspace,
              recentsStore: emojiRecentsStore,
            ),
            YoComposerPanelTab.gif =>
              _gifEnabled
                  ? _withDeliveryGate(
                      YoGifPicker(
                        service: gifService!,
                        onSelected: onGifSelected!,
                        onReport: onGifReport,
                        recentsStore: gifRecentsStore,
                        autoLoad: gifAutoLoad,
                        height: bodyHeight,
                        compact: compact,
                      ),
                    )
                  : _DisabledGifBody(
                      height: bodyHeight,
                      palette: palette,
                      copy: copy,
                      reason:
                          gifUnavailableReason ??
                          GifUnavailableReason.notConfigured,
                    ),
          },
        ],
      ),
    );
  }

  Widget _withDeliveryGate(Widget picker) {
    final delivery = gifDelivery;
    if (delivery == null) return picker;
    return ListenableBuilder(
      listenable: delivery,
      builder: (context, child) => ExcludeFocus(
        excluding: !delivery.canSelect,
        child: IgnorePointer(ignoring: !delivery.canSelect, child: child),
      ),
      child: picker,
    );
  }

  static double _stripHeight(TextScaler scaler, double panelHeight) {
    // Scales with text size so the labels stay readable, but never takes more
    // than a fifth of a short panel — the room chat sheet's is 260 px at most
    // and the grid below still has to be usable.
    final scaled = math.min(scaler.scale(40), 56.0);
    return math.min(scaled, math.max(32.0, panelHeight * 0.2));
  }
}

/// Sized to sit where the keyboard was.
///
/// Deliberately the same rule [YoEmojiPicker] applies to itself: when the
/// system keyboard is still up we reuse its exact height, so swapping one for
/// the other does not make the composer jump; otherwise we claim a share of the
/// viewport and cap it so the conversation stays visible on a short screen.
///
/// It lives here rather than being read out of the emoji picker because the
/// PANEL is now the thing that must match the keyboard: the strip plus the
/// body is what the keyboard is being replaced by, and only one of the two can
/// own that number.
double yoComposerPanelHeight(MediaQueryData media, TextScaler scaler) {
  final keyboard = media.viewInsets.bottom;
  final ceiling = math.max(240.0, media.size.height * 0.55);
  if (keyboard > 180 && keyboard < ceiling) return keyboard;
  // Chrome (search row plus the tab strip) and rows both scale with the
  // reader's text size. Leaving the row term unscaled left a 200% panel with
  // one visible row of GIFs above the attribution footer — visible in the
  // first capture at 320 px — because only the chrome grew.
  final desired = math.max(
    scaler.scale(20) + 84 + scaler.scale(44) * 2.6,
    media.size.height * 0.36,
  );
  return desired.clamp(240.0, ceiling);
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tab,
    required this.height,
    required this.palette,
    required this.copy,
    required this.onTabChanged,
  });

  final YoComposerPanelTab tab;
  final double height;
  final AppPalette palette;
  final AppLocalizations copy;
  final ValueChanged<YoComposerPanelTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final candidate in YoComposerPanelTab.values)
            Expanded(
              child: _TabButton(
                candidate: candidate,
                selected: candidate == tab,
                accent: accent,
                palette: palette,
                copy: copy,
                onTap: () => onTabChanged(candidate),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.candidate,
    required this.selected,
    required this.accent,
    required this.palette,
    required this.copy,
    required this.onTap,
  });

  final YoComposerPanelTab candidate;
  final bool selected;
  final Color accent;
  final AppPalette palette;
  final AppLocalizations copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (candidate) {
      YoComposerPanelTab.emoji => copy.text('Emoji', 'Emoji'),
      YoComposerPanelTab.gif => copy.text('GIFs', 'GIF-y'),
    };
    final icon = switch (candidate) {
      YoComposerPanelTab.emoji => Icons.emoji_emotions_outlined,
      YoComposerPanelTab.gif => Icons.gif_box_outlined,
    };

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('composer-panel-tab-${candidate.name}'),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? accent : palette.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : palette.textTertiary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The GIF tab with no GIF path behind it.
///
/// Reached whenever this composer has no send path or no service — visible,
/// disabled and LABELLED, per CLAUDE.md, rather than hidden or faked. The tab
/// stays tappable so the label can be read; there is simply nothing to pick.
class _DisabledGifBody extends StatelessWidget {
  const _DisabledGifBody({
    required this.height,
    required this.palette,
    required this.copy,
    required this.reason,
  });

  final double height;
  final AppPalette palette;
  final AppLocalizations copy;
  final GifUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final (headline, detail) = switch (reason) {
      GifUnavailableReason.surfaceUnsupported => (
        copy.text('GIFs are coming here soon', 'GIF-y pojawią się tu wkrótce'),
        copy.text(
          'This conversation cannot send GIFs yet. Emoji still work.',
          'Ta rozmowa nie obsługuje jeszcze GIF-ów. Emoji nadal działają.',
        ),
      ),
      GifUnavailableReason.disabled => (
        copy.text('GIFs are turned off', 'GIF-y są wyłączone'),
        copy.text(
          'GIFs are unavailable right now. Emoji still work.',
          'GIF-y są chwilowo niedostępne. Emoji nadal działają.',
        ),
      ),
      _ => (
        copy.text("GIFs aren't available yet", 'GIF-y nie są jeszcze dostępne'),
        copy.text(
          'This feature is not switched on for YO Voice yet.',
          'Ta funkcja nie jest jeszcze włączona w YO Voice.',
        ),
      ),
    };

    return Container(
      key: const ValueKey('gif-picker-disabled'),
      height: height,
      color: palette.navigationSurface,
      child: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.gif_box_outlined,
                  size: 30,
                  color: palette.textTertiary,
                ),
                const SizedBox(height: 10),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
