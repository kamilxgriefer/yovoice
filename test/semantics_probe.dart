import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the COMPILED semantics tree, not the `Semantics` widgets.
///
/// A `Semantics` widget's `properties.label` is what the widget asked for; a
/// `SemanticsNode`'s label is what a screen reader actually announces. The two
/// diverge whenever a non-boundary annotation merges with its siblings — which
/// is exactly the failure mode these helpers exist to catch, and exactly the
/// one a widget-level assertion cannot see.
///
/// Requires `tester.ensureSemantics()` to be active.
List<SemanticsNode> compiledSemanticsNodes(
  WidgetTester tester, {
  Finder? anchor,
}) {
  // Climbing from any node reaches the root without touching the deprecated
  // `pipelineOwner.semanticsOwner`.
  var root = tester.getSemantics(anchor ?? find.byType(MaterialApp));
  while (root.parent != null) {
    root = root.parent!;
  }
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return nodes;
}

/// The announced label of every compiled node flagged as a button.
List<String> compiledButtonLabels(WidgetTester tester, {Finder? anchor}) => [
  for (final node in compiledSemanticsNodes(tester, anchor: anchor))
    if (node.getSemanticsData().flagsCollection.isButton)
      node.getSemanticsData().label,
];

/// The announced label of the compiled node for [finder], with the value a
/// screen reader would read after it.
String announcedLabelOf(WidgetTester tester, Finder finder) {
  final data = tester.getSemantics(finder).getSemanticsData();
  return data.value.isEmpty ? data.label : '${data.label} ${data.value}';
}
