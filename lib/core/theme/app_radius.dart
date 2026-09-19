import 'package:flutter/material.dart';

class AppRadius {
  AppRadius._();

  static const BorderRadius sm = BorderRadius.all(Radius.circular(8));

  /// The Slim redesign's one card radius (ADR-209): cards, inputs and
  /// composers. [md] stays 14 for server squircles; [lg] and up are for
  /// sheets and the dock.
  static const BorderRadius card = BorderRadius.all(Radius.circular(12));

  static const BorderRadius md = BorderRadius.all(Radius.circular(14));

  static const BorderRadius lg = BorderRadius.all(Radius.circular(20));

  static const BorderRadius xl = BorderRadius.all(Radius.circular(28));

  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}
