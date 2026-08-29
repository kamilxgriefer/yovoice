import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';

/// Defines an intentional dark-theme island, including the surrounding
/// platform chrome, without changing the application's selected theme.
class YoImmersiveDarkSurface extends StatelessWidget {
  const YoImmersiveDarkSurface({required this.child, super.key});

  static final ThemeData _theme = AppTheme.darkTheme;
  static final SystemUiOverlayStyle _overlayStyle = AppTheme.systemOverlayStyle(
    Brightness.dark,
    AppPalette.dark,
  );

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _overlayStyle,
        child: child,
      ),
    );
  }
}
