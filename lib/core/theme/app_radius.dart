import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  static const BorderRadius sm = BorderRadius.all(Radius.circular(8));

  /// Inputs, composers, auth controls and glyph boxes. Content blocks use
  /// [block] (refine-look §3.0); the value stays 12. [md] stays 14 for
  /// server squircles; [lg] and up are for sheets and the dock.
  static const BorderRadius card = BorderRadius.all(Radius.circular(12));

  static const BorderRadius md = BorderRadius.all(Radius.circular(14));

  /// More tiles, the conversation-row wash, the vibe sticker, image actions
  /// and the name plate.
  static const BorderRadius tile = BorderRadius.all(Radius.circular(16));

  static const BorderRadius lg = BorderRadius.all(Radius.circular(20));

  /// The one block radius: every content block, the LIVE tile, Moment cards
  /// and Settings groups. An alias of [lg] (20), so there is no hero radius.
  static const BorderRadius block = lg;

  static const BorderRadius xl = BorderRadius.all(Radius.circular(28));

  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}
