import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';

/// Defines an intentional dark-theme island, including the surrounding
/// platform chrome, without changing the application's selected theme.
///
/// The island follows the platform's high-contrast flag the way
/// `MaterialApp` does for the app: under high contrast it uses
/// [AppTheme.darkHighContrastTheme], so a theme-inheriting Material chip or
/// card inside it gets its `borderStrong` edge back ("high contrast brings
/// `borderStrong` back everywhere") instead of keeping the decorative
/// hairline.
class YoImmersiveDarkSurface extends StatelessWidget {
  const YoImmersiveDarkSurface({required this.child, super.key});

  static final ThemeData _theme = AppTheme.darkTheme;
  static final ThemeData _highContrastTheme = AppTheme.darkHighContrastTheme;
  static final SystemUiOverlayStyle _overlayStyle = AppTheme.systemOverlayStyle(
    Brightness.dark,
    AppPalette.dark,
  );

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MediaQuery.highContrastOf(context) ? _highContrastTheme : _theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyle,
        child: child,
      ),
    );
  }
}
