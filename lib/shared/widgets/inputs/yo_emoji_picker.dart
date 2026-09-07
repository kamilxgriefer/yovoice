import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_catalog.dart';
import 'package:yovoice/shared/widgets/inputs/yo_emoji_recents.dart';

export 'package:yovoice/shared/widgets/inputs/yo_emoji_catalog.dart';
export 'package:yovoice/shared/widgets/inputs/yo_emoji_recents.dart';

/// Emoji glyphs must not inherit the app's primary font family.
///
/// `InterVariable` ships flat monochrome glyphs for several base codepoints
/// (❤ ✔ ✂ ★ ☹ ℹ and friends), and a primary family always wins over
/// `fontFamilyFallback` regardless of the U+FE0F variation selector. Left
/// alone, those few would render as grey outlines in a grid where everything
/// around them is in colour. Naming the platform colour-emoji families as the
/// *primary* family fixes it, and on a platform where none of them resolve the
/// engine falls back to its own default — which is that platform's colour
/// emoji font anyway.
const yoEmojiFontFamily = 'Apple Color Emoji';
const yoEmojiFontFamilyFallback = <String>[
  'Noto Color Emoji',
  'Segoe UI Emoji',
  'Twemoji Mozilla',
];

/// The text style every emoji glyph in the picker is drawn with.
TextStyle yoEmojiGlyphStyle(double fontSize) => TextStyle(
  fontSize: fontSize,
  fontFamily: yoEmojiFontFamily,
  fontFamilyFallback: yoEmojiFontFamilyFallback,
  height: 1.2,
);

/// Replaces the current selection with [emoji] and leaves the caret directly
/// after it, so a run of taps composes left to right instead of stacking up.
///
/// Mirrors the behaviour the room chat sheet's quick-emoji row already had —
/// this is that logic lifted out so all three composers share one
/// implementation rather than three drifting copies.
void yoInsertEmojiAtCaret(TextEditingController controller, String emoji) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid) {
    final text = value.text + emoji;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return;
  }
  controller.value = value.copyWith(
    text: value.text.replaceRange(selection.start, selection.end, emoji),
    selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    composing: TextRange.empty,
  );
}

/// Deletes one *grapheme cluster* before the caret.
///
/// Emoji are routinely several code units long — a flag is two, a keycap
/// three, a ZWJ sequence more — so deleting by code unit would leave half a
/// glyph behind. The picker owns a backspace because it hides the system
/// keyboard, and the user has to be able to take an emoji back.
void yoDeleteBackAtCaret(TextEditingController controller) {
  final value = controller.value;
  final selection = value.selection;
  if (value.text.isEmpty) return;

  if (selection.isValid && !selection.isCollapsed) {
    controller.value = value.copyWith(
      text: value.text.replaceRange(selection.start, selection.end, ''),
      selection: TextSelection.collapsed(offset: selection.start),
      composing: TextRange.empty,
    );
    return;
  }

  final caret = selection.isValid ? selection.start : value.text.length;
  if (caret == 0) return;
  final before = value.text.substring(0, caret);
  final characters = before.characters;
  if (characters.isEmpty) return;
  final trimmed = characters.skipLast(1).toString();
  controller.value = value.copyWith(
    text: trimmed + value.text.substring(caret),
    selection: TextSelection.collapsed(offset: trimmed.length),
    composing: TextRange.empty,
  );
}

/// Localized display name for a catalogue entry, used as its semantic label.
String yoEmojiName(YoEmoji emoji, AppLocalizations copy) =>
    copy.isPolish ? emoji.namePolish : emoji.name;

/// Localized category name.
String yoEmojiCategoryLabel(YoEmojiCategory category, AppLocalizations copy) {
  return switch (category) {
    YoEmojiCategory.smileys => copy.text('Smileys & emotion', 'Buźki i emocje'),
    YoEmojiCategory.people => copy.text('People & body', 'Ludzie i ciało'),
    YoEmojiCategory.animals => copy.text(
      'Animals & nature',
      'Zwierzęta i natura',
    ),
    YoEmojiCategory.food => copy.text('Food & drink', 'Jedzenie i napoje'),
    YoEmojiCategory.activity => copy.text('Activity', 'Aktywność'),
    YoEmojiCategory.travel => copy.text('Travel & places', 'Podróże i miejsca'),
    YoEmojiCategory.objects => copy.text('Objects', 'Przedmioty'),
    YoEmojiCategory.symbols => copy.text('Symbols', 'Symbole'),
    YoEmojiCategory.flags => copy.text('Flags', 'Flagi'),
  };
}

IconData _categoryIcon(YoEmojiCategory category) => switch (category) {
  YoEmojiCategory.smileys => Icons.sentiment_satisfied_alt_outlined,
  YoEmojiCategory.people => Icons.emoji_people_outlined,
  YoEmojiCategory.animals => Icons.pets_outlined,
  YoEmojiCategory.food => Icons.restaurant_outlined,
  YoEmojiCategory.activity => Icons.sports_basketball_outlined,
  YoEmojiCategory.travel => Icons.directions_car_outlined,
  YoEmojiCategory.objects => Icons.lightbulb_outline,
  YoEmojiCategory.symbols => Icons.emoji_symbols_outlined,
  YoEmojiCategory.flags => Icons.flag_outlined,
};

/// The full, categorised emoji picker that takes the system keyboard's place
/// underneath a message composer.
///
/// It is deliberately a plain panel rather than a sheet or an overlay: placed
/// as the sibling *below* the composer in a column, the composer — and with it
/// the send button — is laid out first and can never be covered. That is a
/// structural guarantee rather than a computed one, which is why it survives
/// text scaling, a short viewport and a long draft message.
class YoEmojiPicker extends StatefulWidget {
  const YoEmojiPicker({
    required this.onSelected,
    super.key,
    this.onBackspace,
    this.recentsStore,
    this.height,
  });

  /// Called with the chosen emoji character.
  final ValueChanged<String> onSelected;

  /// Called when the picker's backspace is pressed. Omit to hide it.
  final VoidCallback? onBackspace;

  /// Defaults to [YoEmojiRecentsStore.instance]; inject an in-memory store in
  /// tests.
  final YoEmojiRecentsStore? recentsStore;

  /// Overrides the computed panel height. Used by the room chat sheet, which
  /// already knows how much room its own panel can spare.
  final double? height;

  @override
  State<YoEmojiPicker> createState() => _YoEmojiPickerState();
}

class _YoEmojiPickerState extends State<YoEmojiPicker> {
  static const _glyphSize = 26.0;

  final TextEditingController _search = TextEditingController();
  final ScrollController _grid = ScrollController();

  late YoEmojiRecentsStore _recents;
  YoEmojiCategory _category = YoEmojiCategory.smileys;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _recents = widget.recentsStore ?? YoEmojiRecentsStore.instance;
    _recents.addListener(_onRecentsChanged);
    unawaitedLoad();
  }

  void unawaitedLoad() {
    // Fire and forget: the grid is usable before recents resolve, and a
    // failure to read them is handled inside the store.
    _recents.load();
  }

  void _onRecentsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant YoEmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.recentsStore ?? YoEmojiRecentsStore.instance;
    if (!identical(next, _recents)) {
      _recents.removeListener(_onRecentsChanged);
      _recents = next..addListener(_onRecentsChanged);
      unawaitedLoad();
    }
  }

  @override
  void dispose() {
    _recents.removeListener(_onRecentsChanged);
    _search.dispose();
    _grid.dispose();
    super.dispose();
  }

  void _select(YoEmoji emoji) {
    widget.onSelected(emoji.char);
    _recents.register(emoji.char);
  }

  void _setCategory(YoEmojiCategory category) {
    setState(() {
      _category = category;
      if (_query.isNotEmpty) {
        _query = '';
        _search.clear();
      }
    });
    if (_grid.hasClients) _grid.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;

    // The glyph grows with the user's text size, and the cell grows *with the
    // glyph* rather than by a fixed number of pixels. A constant padding looks
    // generous at 100% and clips at 200%, because Apple Color Emoji and Noto
    // Color Emoji both draw taller than their nominal point size. The cap
    // keeps a 200% setting from collapsing a 320px grid to three columns —
    // emoji are pictograms, so the accessible minimum that has to scale is the
    // touch target, and that is enforced by [_minimumTarget] below.
    final glyphSize = math.min(scaler.scale(_glyphSize), _maxGlyphSize);
    final cellExtent = math.max(_minimumTarget, glyphSize * _cellToGlyphRatio);
    final panelHeight =
        widget.height ?? _panelHeight(media, scaler, cellExtent);

    final searching = _query.trim().isNotEmpty;
    final results = searching
        ? yoSearchEmoji(_query)
        : yoEmojiByCategory[_category]!;
    final recents = _recents.emoji;

    return Container(
      key: const ValueKey('emoji-picker'),
      height: panelHeight,
      decoration: BoxDecoration(
        color: palette.navigationSurface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            // Desktop is not a stretched phone: a 1440px-wide wall of emoji is
            // unreadable and unreachable, so the content keeps a comfortable
            // measure and centres in the extra space.
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                _SearchRow(
                  controller: _search,
                  palette: palette,
                  copy: copy,
                  onChanged: (value) => setState(() => _query = value),
                  onBackspace: widget.onBackspace,
                ),
                if (!searching)
                  _CategoryStrip(
                    selected: _category,
                    palette: palette,
                    copy: copy,
                    onSelected: _setCategory,
                  ),
                Expanded(
                  child: results.isEmpty
                      ? _EmptyResults(palette: palette, copy: copy)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = math.max(
                              1,
                              ((constraints.maxWidth - 16) / cellExtent)
                                  .floor(),
                            );
                            return FocusTraversalGroup(
                              policy: ReadingOrderTraversalPolicy(),
                              child: CustomScrollView(
                                controller: _grid,
                                slivers: [
                                  if (!searching && recents.isNotEmpty) ...[
                                    _SectionHeader(
                                      label: copy.text(
                                        'Recently used',
                                        'Ostatnio używane',
                                      ),
                                      palette: palette,
                                    ),
                                    _EmojiSliverGrid(
                                      key: const ValueKey('emoji-recents'),
                                      emoji: recents,
                                      columns: columns,
                                      cellExtent: cellExtent,
                                      glyphSize: glyphSize,
                                      palette: palette,
                                      copy: copy,
                                      keyPrefix: 'recent',
                                      onSelected: _select,
                                    ),
                                    _SectionHeader(
                                      label: yoEmojiCategoryLabel(
                                        _category,
                                        copy,
                                      ),
                                      palette: palette,
                                    ),
                                  ],
                                  _EmojiSliverGrid(
                                    emoji: results,
                                    columns: columns,
                                    cellExtent: cellExtent,
                                    glyphSize: glyphSize,
                                    palette: palette,
                                    copy: copy,
                                    keyPrefix: 'cell',
                                    onSelected: _select,
                                  ),
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 8),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _minimumTarget = 44.0;
  static const _maxGlyphSize = 34.0;
  static const _cellToGlyphRatio = 1.7;

  /// Sized to sit where the keyboard was.
  ///
  /// When the system keyboard is still up we reuse its exact height, so
  /// swapping one for the other does not make the composer jump. Otherwise we
  /// ask for roughly three rows of cells and cap the result at half the
  /// viewport, which keeps the conversation visible on a short screen and at a
  /// large text size.
  static double _panelHeight(
    MediaQueryData media,
    TextScaler scaler,
    double cellExtent,
  ) {
    final keyboard = media.viewInsets.bottom;
    final chrome = scaler.scale(20) + 84;
    // Three rows of cells plus the search field and strip is the floor. On a
    // tall viewport that floor leaves the grid squeezed into a sliver once the
    // recents row and its two section headers are in — which is the normal
    // state after any use — so the panel also claims a share of the height.
    final desired = math.max(
      chrome + cellExtent * 3.2,
      media.size.height * 0.32,
    );
    final ceiling = math.max(200.0, media.size.height * 0.55);
    if (keyboard > 180 && keyboard < ceiling) return keyboard;
    return desired.clamp(200.0, ceiling);
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.controller,
    required this.palette,
    required this.copy,
    required this.onChanged,
    this.onBackspace,
  });

  final TextEditingController controller;
  final AppPalette palette;
  final AppLocalizations copy;
  final ValueChanged<String> onChanged;
  final VoidCallback? onBackspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('emoji-picker-search'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: palette.textTertiary,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                hintText: copy.text('Search emoji', 'Szukaj emoji'),
                hintStyle: TextStyle(color: palette.textTertiary, fontSize: 14),
                filled: true,
                fillColor: palette.surfaceSunken,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: palette.border),
                ),
              ),
            ),
          ),
          if (onBackspace != null) ...[
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('emoji-picker-backspace'),
              onPressed: onBackspace,
              tooltip: copy.text('Delete', 'Usuń'),
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Icon(
                Icons.backspace_outlined,
                size: 20,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.selected,
    required this.palette,
    required this.copy,
    required this.onSelected,
  });

  final YoEmojiCategory selected;
  final AppPalette palette;
  final AppLocalizations copy;
  final ValueChanged<YoEmojiCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          for (final category in YoEmojiCategory.values)
            Builder(
              builder: (context) {
                final isSelected = category == selected;
                final label = yoEmojiCategoryLabel(category, copy);
                return Semantics(
                  label: label,
                  button: true,
                  selected: isSelected,
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      key: ValueKey('emoji-category-${category.name}'),
                      onTap: () => onSelected(category),
                      borderRadius: BorderRadius.circular(12),
                      focusColor: palette.focus.withValues(alpha: 0.28),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isSelected
                              ? accent.withValues(alpha: 0.16)
                              : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? accent.withValues(alpha: 0.55)
                                : Colors.transparent,
                          ),
                        ),
                        child: ExcludeSemantics(
                          child: Icon(
                            _categoryIcon(category),
                            size: 20,
                            color: isSelected ? accent : palette.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: palette.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _EmojiSliverGrid extends StatelessWidget {
  const _EmojiSliverGrid({
    required this.emoji,
    required this.columns,
    required this.cellExtent,
    required this.glyphSize,
    required this.palette,
    required this.copy,
    required this.keyPrefix,
    required this.onSelected,
    super.key,
  });

  final List<YoEmoji> emoji;
  final int columns;
  final double cellExtent;
  final double glyphSize;
  final AppPalette palette;
  final AppLocalizations copy;
  final String keyPrefix;
  final ValueChanged<YoEmoji> onSelected;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverGrid(
        // Columns follow the available width rather than a device label, so
        // the same grid gives six cells at 320px and more at 768px without any
        // breakpoint branching. The count is floored rather than handed to
        // `maxCrossAxisExtent`, which divides the width by a *ceiling* and so
        // would hand back 43.4px cells at 320px — just under the 44px target.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: cellExtent,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = emoji[index];
          final label = yoEmojiName(entry, copy);
          return Semantics(
            label: label,
            button: true,
            child: Tooltip(
              message: label,
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                key: ValueKey('emoji-$keyPrefix-${entry.char}'),
                onTap: () => onSelected(entry),
                borderRadius: BorderRadius.circular(10),
                focusColor: palette.focus.withValues(alpha: 0.3),
                child: Center(
                  child: ExcludeSemantics(
                    child: Text(
                      entry.char,
                      style: yoEmojiGlyphStyle(glyphSize),
                    ),
                  ),
                ),
              ),
            ),
          );
        }, childCount: emoji.length),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.palette, required this.copy});

  final AppPalette palette;
  final AppLocalizations copy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          copy.text(
            'No emoji match that search.',
            'Brak emoji dla tego wyszukiwania.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}

/// The composer affordance that opens and closes [YoEmojiPicker].
///
/// Shared so the direct-message composer, the room chat sheet and the club
/// composer present one control with one tooltip and one icon language,
/// instead of three near-identical buttons that drift apart.
class YoEmojiComposerButton extends StatelessWidget {
  const YoEmojiComposerButton({
    required this.open,
    required this.onPressed,
    super.key,
    this.size = 48,
    this.iconSize = 22,
    this.color,
    this.activeColor,
  });

  final bool open;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final accent = activeColor ?? Theme.of(context).colorScheme.primary;

    return IconButton(
      key: const ValueKey('emoji-picker-toggle'),
      onPressed: onPressed,
      tooltip: open
          ? copy.text('Close emoji picker', 'Zamknij emoji')
          : copy.text('Open emoji picker', 'Otwórz emoji'),
      constraints: BoxConstraints.tightFor(
        width: math.max(44, size),
        height: math.max(44, size),
      ),
      padding: EdgeInsets.zero,
      icon: Icon(
        open ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
        size: iconSize,
        color: open ? accent : (color ?? palette.textSecondary),
      ),
    );
  }
}

/// Asks the platform to put the system keyboard away without dropping focus.
///
/// The composer's [FocusNode] deliberately stays focused: the caret has to stay
/// where it is for insertion to land in the right place, and the send button
/// must keep working. Only the on-screen keyboard goes away, because the
/// picker is taking its place.
Future<void> yoHideSystemKeyboard() {
  return SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}
