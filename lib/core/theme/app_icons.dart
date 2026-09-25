import 'package:flutter/material.dart';

/// Named Material glyphs for recurring chrome actions (refine-look §6).
///
/// The rule these aliases carry: **outline glyphs in chrome; filled glyphs
/// only** for a selected toggle, a white glyph inside a gradient disc or CTA,
/// or a status icon. The aliases change no call site on their own — each
/// owner swaps its literal `Icons.*` for the alias when it next touches the
/// file, so the family converges without a mass edit.
abstract final class AppIcons {
  /// Start a new conversation / compose.
  static const IconData compose = Icons.edit_outlined;

  /// Invite or add a friend.
  static const IconData addFriend = Icons.person_add_alt_outlined;

  /// Open a chat.
  static const IconData chat = Icons.chat_bubble_outline_rounded;

  /// Archive a conversation / open the archive.
  static const IconData archive = Icons.archive_outlined;

  /// The notifications bell in chrome.
  static const IconData notifications = Icons.notifications_none_rounded;
}
