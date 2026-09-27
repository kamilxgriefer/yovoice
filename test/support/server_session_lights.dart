import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server session card's light layers (refine-look R4 / W2 at card
/// scale), as the tests and the Servers capture harness read them.
///
/// Since spec §13 (B4, "stable tree shape") every layer is ALWAYS in the
/// tree — in the quiet, live, connected and high-contrast states alike — and
/// simply paints nothing while its light is off. Whether a light is on is
/// therefore read from what its layer paints, never from whether its key
/// can be found.
enum ServerSessionLight {
  /// The live under-glow behind the card: `server-session-glow`.
  glow('server-session-glow'),

  /// The live corner light inside the card: `server-session-corner`.
  corner('server-session-corner'),

  /// The connected corner tint inside the card: `server-session-tint`.
  tint('server-session-tint');

  const ServerSessionLight(this.key);

  /// The layer's key.
  final String key;

  /// Every layer of this light on screen (one per session card).
  Finder get layers => find.byKey(ValueKey(key));

  /// Looks up a light by its layer key, or null for any other key.
  static ServerSessionLight? byKey(String key) {
    for (final light in values) {
      if (light.key == key) return light;
    }
    return null;
  }

  /// How many of this light's layers on screen actually paint.
  int litCount(WidgetTester tester) => layers
      .evaluate()
      .where((element) => _paints(_decoration(tester, element)))
      .length;

  /// Whether any layer of this light on screen paints.
  bool isLit(WidgetTester tester) => litCount(tester) > 0;

  /// The decoration the layer keyed [key] paints. The glow and the corner
  /// key their `DecoratedBox` itself; the tint keys the positioned slot
  /// around its disc.
  BoxDecoration _decoration(WidgetTester tester, Element element) {
    final widget = element.widget;
    if (widget is DecoratedBox) return widget.decoration as BoxDecoration;
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byElementPredicate((candidate) => candidate == element),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return box.decoration as BoxDecoration;
  }

  bool _paints(BoxDecoration decoration) => switch (this) {
    ServerSessionLight.glow => decoration.boxShadow?.isNotEmpty ?? false,
    ServerSessionLight.corner || ServerSessionLight.tint =>
      decoration.gradient != null || decoration.color != null,
  };
}
