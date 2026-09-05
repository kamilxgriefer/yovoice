// Developer-only interactive preview for the production mobile navigation
// dock. Run with:
//   flutter run -d web-server -t lib/dev/navigation_dock_preview.dart
//
// This entrypoint is never imported by lib/main.dart and is not shipped.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/mobile_destination_history.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/navigation/yo_edge_back_gesture.dart';

void main() => runApp(const _NavigationDockPreviewApp());

class _NavigationDockPreviewApp extends StatefulWidget {
  const _NavigationDockPreviewApp();

  @override
  State<_NavigationDockPreviewApp> createState() =>
      _NavigationDockPreviewAppState();
}

class _NavigationDockPreviewAppState extends State<_NavigationDockPreviewApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YO dock preview',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _PreviewSurface(
        light: _themeMode == ThemeMode.light,
        onThemeChanged: (light) => setState(
          () => _themeMode = light ? ThemeMode.light : ThemeMode.dark,
        ),
      ),
    );
  }
}

class _PreviewSurface extends StatefulWidget {
  const _PreviewSurface({required this.light, required this.onThemeChanged});

  final bool light;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<_PreviewSurface> createState() => _PreviewSurfaceState();
}

class _PreviewSurfaceState extends State<_PreviewSurface> {
  static const _momentsIndex = 5;
  int _selectedIndex = 0;
  bool _moreSelected = false;
  final _history = MobileDestinationHistory();

  void _back() {
    final previous = _history.back();
    if (previous != null) setState(() => _selectedIndex = previous);
  }

  String get _status {
    if (_moreSelected) return 'More';
    return switch (_selectedIndex) {
      0 => 'Home',
      1 => 'Chats',
      3 => 'Rooms',
      _momentsIndex => 'Your Moments',
      _ => 'Navigation',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<Object?>(
      canPop: !_history.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: YoEdgeBackGesture(
          enabled: _history.canGoBack && !_moreSelected,
          navigationIdentity: _selectedIndex,
          onBack: _back,
          child: YoPageBackground(
            section: _moreSelected
                ? YoPageSection.more
                : switch (_selectedIndex) {
                    0 => YoPageSection.home,
                    1 => YoPageSection.chats,
                    3 => YoPageSection.rooms,
                    _ => YoPageSection.moments,
                  },
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.light
                    ? [const Color(0xFFFCF9FF), const Color(0xFFF1E9FA)]
                    : [const Color(0xFF160727), const Color(0xFF070610)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Navigation dock',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const Icon(Icons.dark_mode_rounded, size: 18),
                        Switch(
                          value: widget.light,
                          onChanged: widget.onThemeChanged,
                        ),
                        const Icon(Icons.light_mode_rounded, size: 18),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kliknij zakładkę albo przeciągnij okrągły przycisk. '
                      'Przesuń od lewej krawędzi, aby wrócić przez odwiedzone sekcje. '
                      'To produkcyjny widget Meniscus — podgląd lokalny.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                          key: ValueKey(_status),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: .72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Text(
                            _status,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: YoFloatingNavigationDock(
          selectedTabIndex: _selectedIndex,
          momentsTabIndex: _momentsIndex,
          unreadConversationCount: 7,
          moreSelected: _moreSelected,
          onDestinationSelected: (index) => setState(() {
            _history.select(index);
            _selectedIndex = index;
            _moreSelected = false;
          }),
          onVoicePressed: () {},
          onMorePressed: () => setState(() {
            _moreSelected = true;
          }),
        ),
      ),
    );
  }
}
