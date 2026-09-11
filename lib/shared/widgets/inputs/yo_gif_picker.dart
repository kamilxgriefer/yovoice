import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_recents.dart';
import 'package:yovoice/shared/widgets/media/yo_gif_view.dart';

/// The GIF tab's body: search, trending, recents, and every failure state.
///
/// It is a sibling of [YoEmojiPicker] inside one [YoComposerPanel], sized by
/// the panel rather than by itself, so the two can never both be mounted.
///
/// ## Responsive by width, never by device
///
/// Columns are computed from the available width — two narrow, three at
/// 520 px, four at 760 px — and every cell keeps a 44 px minimum touch target.
/// Row height is FIXED, so the grid never measures a remote image to lay
/// itself out; that is what keeps a picker on a slow connection from
/// reflowing under a scrolling thumb.
class YoGifPicker extends StatefulWidget {
  const YoGifPicker({
    required this.service,
    required this.onSelected,
    required this.height,
    super.key,
    this.recentsStore,
    this.autoLoad = true,
    this.onReport,
    this.reportContextPath,
    this.compact = false,
  });

  final GifCatalogService service;

  /// Called with the chosen GIF. The host composer decides what "chosen"
  /// means for its surface — staging an attachment, or sending directly.
  final ValueChanged<GifAsset> onSelected;

  /// Panel-supplied. The picker never computes its own height, so the panel
  /// stays exactly as tall as the keyboard it replaced.
  final double height;

  final YoGifRecentsStore? recentsStore;

  /// `AppPreferences.gifAutoLoadEnabled`. False means the grid shows
  /// tap-to-load placeholders and contacts the provider for nothing.
  final bool autoLoad;

  /// Overrides the long-press action. Omit it and the picker opens its own
  /// "Report this GIF" sheet, which files through
  /// [GifCatalogService.report] into the moderation queue that already exists
  /// — so every surface that enables GIFs gets reporting without wiring it.
  final ValueChanged<GifAsset>? onReport;

  /// Where the reporter saw it, recorded on the report so a moderator has
  /// context. Optional and bounded server-side.
  final String? reportContextPath;

  /// Set by the room chat sheet, whose panel is already short: it drops the
  /// suggestion chips and the recents row rather than compressing everything
  /// into an unusable strip.
  final bool compact;

  @override
  State<YoGifPicker> createState() => _YoGifPickerState();
}

class _YoGifPickerState extends State<YoGifPicker> {
  late final TextEditingController _search;
  final ScrollController _grid = ScrollController();
  late YoGifRecentsStore _recents;

  @override
  void initState() {
    super.initState();
    // The tab body is deliberately unmounted when Emoji is selected, while
    // its service survives. Keep the visible input paired with those results.
    _search = TextEditingController(text: widget.service.state.query);
    _recents = widget.recentsStore ?? YoGifRecentsStore.instance;
    _recents.addListener(_onChanged);
    widget.service.addListener(_onChanged);
    _recents.load();
    // Availability is fetched on the first open of this tab, not at app
    // start: nothing should pay for a feature nobody has asked for.
    widget.service.start();
    _grid.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant YoGifPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      oldWidget.service.removeListener(_onChanged);
      _search.value = TextEditingValue(
        text: widget.service.state.query,
        selection: TextSelection.collapsed(
          offset: widget.service.state.query.length,
        ),
      );
      widget.service.addListener(_onChanged);
      widget.service.start();
    }
    final next = widget.recentsStore ?? YoGifRecentsStore.instance;
    if (!identical(next, _recents)) {
      _recents.removeListener(_onChanged);
      _recents = next..addListener(_onChanged);
      _recents.load();
    }
  }

  @override
  void dispose() {
    _grid.removeListener(_onScroll);
    _grid.dispose();
    _search.dispose();
    _recents.removeListener(_onChanged);
    widget.service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_grid.hasClients) return;
    final remaining = _grid.position.maxScrollExtent - _grid.position.pixels;
    if (remaining < 240) widget.service.loadMore();
  }

  void _select(GifAsset asset) {
    widget.onSelected(asset);
    _recents.register(asset);
  }

  Future<void> _report(GifAsset asset) async {
    final override = widget.onReport;
    if (override != null) {
      override(asset);
      return;
    }
    final reason = await showGifReportSheet(context, asset: asset);
    if (reason == null || !mounted) return;
    final copy = AppLocalizations.of(context);
    final filed = await widget.service.report(
      asset: asset,
      reason: reason,
      contextPath: widget.reportContextPath,
    );
    // The thing somebody just objected to should not be waiting for them the
    // next time they open the picker.
    if (filed) await _recents.forget(asset);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            filed
                ? copy.text(
                    'Thanks — our moderators will take a look.',
                    'Dziękujemy — moderatorzy to sprawdzą.',
                  )
                : copy.text(
                    "Couldn't send that report. Please try again.",
                    'Nie udało się wysłać zgłoszenia. Spróbuj ponownie.',
                  ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final state = widget.service.state;

    return Container(
      key: const ValueKey('gif-picker'),
      height: widget.height,
      color: palette.navigationSurface,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            // Desktop is not a stretched phone: a 1440 px-wide wall of GIFs is
            // unreadable and unreachable, so the content keeps a comfortable
            // measure and centres in the extra space.
            constraints: const BoxConstraints(maxWidth: 620),
            child: state.status == GifQueryStatus.unavailable
                ? _GifUnavailable(
                    reason:
                        state.unavailableReason ??
                        GifUnavailableReason.notConfigured,
                    palette: palette,
                    copy: copy,
                  )
                : Column(
                    children: [
                      _GifSearchRow(
                        controller: _search,
                        palette: palette,
                        copy: copy,
                        onChanged: widget.service.query,
                      ),
                      if (state.rateLimitedRetrySeconds != null)
                        _GifBanner(
                          key: const ValueKey('gif-rate-limited'),
                          palette: palette,
                          icon: Icons.hourglass_bottom_rounded,
                          // The grid is deliberately still behind this line.
                          message: copy.text(
                            'Slow down for a moment — too many searches.',
                            'Zwolnij na chwilę — zbyt wiele wyszukiwań.',
                          ),
                        ),
                      if (state.degraded)
                        _GifBanner(
                          key: const ValueKey('gif-degraded'),
                          palette: palette,
                          icon: Icons.trending_up_rounded,
                          message: copy.text(
                            'Showing popular GIFs.',
                            'Pokazujemy popularne GIF-y.',
                          ),
                        ),
                      Expanded(child: _body(state, palette, copy)),
                      _GifAttributionFooter(
                        text: state.catalog?.attribution?.text,
                        rating: state.catalog?.ratingLabel ?? 'g',
                        palette: palette,
                        copy: copy,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _body(GifQueryState state, AppPalette palette, AppLocalizations copy) {
    // A spinner only when there is nothing to look at. Once results are on
    // screen, a refetch leaves them there — replacing a populated grid with a
    // spinner on every keystroke is the worst version of this UI.
    if (state.status == GifQueryStatus.loading && !state.hasResults) {
      return const Center(
        key: ValueKey('gif-loading'),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (state.status == GifQueryStatus.error && !state.hasResults) {
      return _GifRetry(
        palette: palette,
        copy: copy,
        onRetry: widget.service.retry,
      );
    }
    if (!state.hasResults) {
      return _GifEmpty(
        palette: palette,
        copy: copy,
        searching: state.query.isNotEmpty,
      );
    }

    final recents = _recents.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        final cellWidth =
            (constraints.maxWidth - 16 - (columns - 1) * 6) / columns;
        // A fixed row height, from the width and a 4:3-ish ratio. Nothing here
        // asks a remote image how tall it is.
        final rowHeight = math.max(72.0, cellWidth * 0.78);
        // THE RECENTS ROW IS GATED ON THE HEIGHT THERE ACTUALLY IS.
        //
        // It costs a full row plus two section headers, and on a panel sized
        // to a keyboard that is most of the body: the first captures of this
        // screen showed the recents row with the TRENDING header directly
        // underneath it and a grid of literally zero height. Recents are a
        // convenience; the grid is the feature, so the grid wins whenever both
        // do not fit. Gated on available height rather than a device label,
        // which is also what makes it correct inside the room chat sheet.
        final showRecents =
            !widget.compact &&
            recents.isNotEmpty &&
            state.isTrending &&
            constraints.maxHeight >= rowHeight * 2.6 + 48;

        return CustomScrollView(
          controller: _grid,
          slivers: [
            if (showRecents) ...[
              _GifSectionHeader(
                label: copy.text('Recently used', 'Ostatnio używane'),
                palette: palette,
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  key: const ValueKey('gif-recents'),
                  height: rowHeight + 20,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: recents.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final asset = recents[index];
                      return _GifCell(
                        asset: asset,
                        width: cellWidth,
                        height: rowHeight,
                        palette: palette,
                        copy: copy,
                        autoLoad: widget.autoLoad,
                        onTap: () => _select(asset),
                        onReport: _report,
                        keyPrefix: 'recent',
                      );
                    },
                  ),
                ),
              ),
              _GifSectionHeader(
                label: copy.text('Trending', 'Na czasie'),
                palette: palette,
              ),
            ],
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: rowHeight,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final asset = state.items[index];
                  return _GifCell(
                    asset: asset,
                    width: cellWidth,
                    height: rowHeight,
                    palette: palette,
                    copy: copy,
                    autoLoad: widget.autoLoad,
                    onTap: () => _select(asset),
                    onReport: _report,
                    keyPrefix: 'cell',
                  );
                }, childCount: state.items.length),
              ),
            ),
            if (state.status == GifQueryStatus.loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Columns from the AVAILABLE WIDTH, never a device label.
  ///
  /// The breakpoints are deliberately inside the 620 px content measure this
  /// picker shares with the emoji grid, not at raw viewport widths: on a
  /// 1440 px window the grid is 620 px wide, so a "four columns at 760 px"
  /// rule would never fire and a desktop would show phone-sized cells forever.
  /// Found by test/gif_picker_test.dart. The 44 px floor is the accessible
  /// touch target and binds before the column count does.
  static int _columnsFor(double width) {
    final byBreakpoint = width >= 560
        ? 4
        : width >= 380
        ? 3
        : 2;
    final byTarget = math.max(1, ((width - 16) / 50).floor());
    return math.max(1, math.min(byBreakpoint, byTarget));
  }
}

/// The reasons a GIF can be reported for.
///
/// Deliberately the SAME closed set as every other report surface in the
/// product (`ReportReason`, and `GIF_REPORT_REASONS` server-side), so triage
/// filters keep working and a reporter cannot use the field as a message
/// channel. `selfHarm` is included because a third-party asset can depict it.
const yoGifReportReasons = <String>[
  'sexual',
  'violence',
  'hate',
  'harassment',
  'selfHarm',
  'spam',
  'other',
];

/// Asks which reason, and returns it — or null if the person backed out.
///
/// A sheet rather than a one-tap report: a report with no reason is a report a
/// moderator cannot triage, and a single "Report" tap is far too easy to hit
/// by accident on a long-press affordance.
Future<String?> showGifReportSheet(
  BuildContext context, {
  required GifAsset asset,
}) {
  final copy = AppLocalizations.of(context);
  final palette = context.appPalette;
  String label(String reason) => switch (reason) {
    'sexual' => copy.text('Sexual content', 'Treści seksualne'),
    'violence' => copy.text('Violence or gore', 'Przemoc lub drastyczność'),
    'hate' => copy.text('Hate or symbols', 'Nienawiść lub symbole'),
    'harassment' => copy.text('Harassment', 'Nękanie'),
    'selfHarm' => copy.text('Self-harm', 'Samookaleczenie'),
    'spam' => copy.text('Spam or misleading', 'Spam lub wprowadzanie w błąd'),
    _ => copy.text('Something else', 'Coś innego'),
  };

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: palette.surfaceRaised,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              copy.text('Report this GIF', 'Zgłoś ten GIF'),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              // Said plainly: nobody in YO Voice is accused by this report.
              copy.text(
                'This reports the GIF itself, not the person who sent it.',
                'To zgłoszenie dotyczy samego GIF-a, nie osoby, która go '
                    'wysłała.',
              ),
              style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
            ),
          ),
          // Seven reasons plus a header do not fit a default bottom sheet on a
          // short phone, and they certainly do not at 200% text scale — where
          // an unscrollable Column silently hides the last reasons behind an
          // overflow stripe. Found by test/gif_picker_test.dart.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in yoGifReportReasons)
                    ListTile(
                      key: ValueKey('gif-report-$reason'),
                      title: Text(
                        label(reason),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(reason),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _GifCell extends StatelessWidget {
  const _GifCell({
    required this.asset,
    required this.width,
    required this.height,
    required this.palette,
    required this.copy,
    required this.autoLoad,
    required this.onTap,
    required this.keyPrefix,
    this.onReport,
  });

  final GifAsset asset;
  final double width;
  final double height;
  final AppPalette palette;
  final AppLocalizations copy;
  final bool autoLoad;
  final VoidCallback onTap;
  final ValueChanged<GifAsset>? onReport;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    // copy.template, not copy.text: a catalog lookup has to start with a
    // STABLE LITERAL key, so the title is substituted after localization
    // rather than baked into the key. Enforced by
    // test/localization_source_guard_test.dart, which caught this.
    final label = copy.template(
      'GIF: {title}',
      'GIF: {title}',
      values: <String, Object>{'title': asset.title},
    );
    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: asset.title,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          key: ValueKey('gif-$keyPrefix-${asset.id}'),
          onTap: onTap,
          onLongPress: onReport == null ? null : () => onReport!(asset),
          borderRadius: BorderRadius.circular(10),
          focusColor: palette.focus.withValues(alpha: 0.3),
          child: ExcludeSemantics(
            child: SizedBox(
              width: width,
              height: height,
              child: YoGifView(
                asset: asset,
                height: height,
                maxWidth: width,
                autoLoad: autoLoad,
                retryOnTap: false,
                borderRadius: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GifSearchRow extends StatelessWidget {
  const _GifSearchRow({
    required this.controller,
    required this.palette,
    required this.copy,
    required this.onChanged,
  });

  final TextEditingController controller;
  final AppPalette palette;
  final AppLocalizations copy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: TextField(
        key: const ValueKey('gif-picker-search'),
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
          hintText: copy.text('Search GIFs', 'Szukaj GIF-ów'),
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
    );
  }
}

class _GifSectionHeader extends StatelessWidget {
  const _GifSectionHeader({required this.label, required this.palette});

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

class _GifBanner extends StatelessWidget {
  const _GifBanner({
    required this.palette,
    required this.icon,
    required this.message,
    super.key,
  });

  final AppPalette palette;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: palette.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: palette.textTertiary, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The disabled state, with a reason.
///
/// The GIF tab is never hidden and never silently broken: CLAUDE.md's rule is
/// that something without a backend ships disabled and LABELLED, and a
/// different sentence for each reason is what makes the label worth reading.
class _GifUnavailable extends StatelessWidget {
  const _GifUnavailable({
    required this.reason,
    required this.palette,
    required this.copy,
  });

  final GifUnavailableReason reason;
  final AppPalette palette;
  final AppLocalizations copy;

  @override
  Widget build(BuildContext context) {
    final (headline, detail) = switch (reason) {
      GifUnavailableReason.surfaceUnsupported => (
        copy.text('GIFs are coming here soon', 'GIF-y pojawią się tu wkrótce'),
        copy.text(
          'This conversation cannot send GIFs yet.',
          'Ta rozmowa nie obsługuje jeszcze wysyłania GIF-ów.',
        ),
      ),
      GifUnavailableReason.disabled => (
        copy.text('GIFs are turned off', 'GIF-y są wyłączone'),
        copy.text(
          'GIFs are unavailable right now. Emoji still work.',
          'GIF-y są chwilowo niedostępne. Emoji nadal działają.',
        ),
      ),
      GifUnavailableReason.providerUnavailable => (
        copy.text('GIFs are unavailable', 'GIF-y są niedostępne'),
        copy.text(
          'The GIF service is not responding. Please try again later.',
          'Usługa GIF nie odpowiada. Spróbuj ponownie później.',
        ),
      ),
      GifUnavailableReason.unreachable => (
        copy.text('GIFs are unavailable', 'GIF-y są niedostępne'),
        copy.text(
          'Could not reach the GIF service. Check your connection.',
          'Nie udało się połączyć z usługą GIF. Sprawdź połączenie.',
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

    return Center(
      key: const ValueKey('gif-unavailable'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gif_box_outlined, size: 30, color: palette.textTertiary),
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
    );
  }
}

class _GifEmpty extends StatelessWidget {
  const _GifEmpty({
    required this.palette,
    required this.copy,
    required this.searching,
  });

  final AppPalette palette;
  final AppLocalizations copy;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('gif-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          searching
              // Neutral on purpose. A denylisted query lands here too, and
              // saying which word tripped the filter is a map of the filter.
              ? copy.text(
                  'No GIFs match that search.',
                  'Brak GIF-ów dla tego wyszukiwania.',
                )
              : copy.text('No GIFs to show yet.', 'Brak GIF-ów do pokazania.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textTertiary, fontSize: 13),
        ),
      ),
    );
  }
}

class _GifRetry extends StatelessWidget {
  const _GifRetry({
    required this.palette,
    required this.copy,
    required this.onRetry,
  });

  final AppPalette palette;
  final AppLocalizations copy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('gif-error'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.text("Couldn't load GIFs.", 'Nie udało się wczytać GIF-ów.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('gif-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(copy.text('Try again', 'Spróbuj ponownie')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Attribution plus the rating promise.
///
/// GIPHY's terms make the mark MANDATORY wherever search or browse results are
/// shown, so there is no code path that hides it while results are on screen.
/// The rating line sits beside it because a person deserves to know the filter
/// exists — and because it is the honest bound on what this grid can contain.
class _GifAttributionFooter extends StatelessWidget {
  const _GifAttributionFooter({
    required this.text,
    required this.rating,
    required this.palette,
    required this.copy,
  });

  final String? text;
  final String rating;
  final AppPalette palette;
  final AppLocalizations copy;

  @override
  Widget build(BuildContext context) {
    final mark = text;
    if (mark == null || mark.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    final ratingLabel = rating == 'g'
        ? copy.text('Rated G only', 'Tylko ocena G')
        : rating.toUpperCase();
    final style = TextStyle(
      color: palette.textTertiary,
      fontSize: 10.5,
      letterSpacing: 0.3,
    );

    // THE MARK IS NEVER ALLOWED TO TRUNCATE.
    //
    // GIPHY's attribution is contractual; the rating line is ours. Side by
    // side they do not fit 320 px at 200% text scale — the first capture of
    // this screen showed "Powered by ..." — so past that point the two stack
    // and the mark keeps the first line. Driven by the scaled text size and
    // the width there actually is, never by a device label.
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = scaler.scale(10.5) > 14 || constraints.maxWidth < 280;
        final markText = Text(
          mark,
          key: const ValueKey('gif-attribution'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        final ratingText = Text(
          ratingLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [markText, ratingText],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: markText),
                    const SizedBox(width: 8),
                    Flexible(child: ratingText),
                  ],
                ),
        );
      },
    );
  }
}
