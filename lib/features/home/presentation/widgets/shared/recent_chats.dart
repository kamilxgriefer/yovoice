import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

enum RecentChatsStyle { standard, desktopBackdrop }

typedef RecentChatImageProvider = ImageProvider<Object> Function(String url);
typedef RecentChatPhotoStream = Stream<String> Function(String userId);

/// A compact Home preview of this account's three most recently updated DMs.
/// [MessageService.watchConversations] already supplies the list newest-first
/// and excludes archived conversations, so this widget only presents it.
class RecentChats extends StatelessWidget {
  const RecentChats({
    required this.snapshot,
    required this.currentUserId,
    required this.onOpenConversation,
    required this.onFindFriends,
    this.style = RecentChatsStyle.standard,
    this.backdropImageProvider,
    this.photoStreamForUser,
    super.key,
  });

  final AsyncSnapshot<List<Conversation>> snapshot;
  final String currentUserId;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onFindFriends;
  final RecentChatsStyle style;
  final RecentChatImageProvider? backdropImageProvider;

  /// Optional live public-profile photo source for the desktop artwork.
  ///
  /// Conversation snapshots intentionally keep enough denormalized identity
  /// to render offline, but older conversations can carry an empty or stale
  /// avatar. Desktop Home supplies the current public profile projection and
  /// the card falls back to the conversation copy while it loads or fails.
  final RecentChatPhotoStream? photoStreamForUser;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    // The desktop backdrop is compact at ordinary scale, but gives enlarged
    // names/previews real space rather than capping accessibility text. The
    // shared mobile presentation keeps its established geometry.
    final cardHeight = switch (style) {
      RecentChatsStyle.standard => 148 + ((textScale - 1) * 68),
      RecentChatsStyle.desktopBackdrop => 116 + ((textScale - 1) * 96),
    };

    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return SizedBox(
        height: cardHeight,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }

    if (snapshot.hasError) {
      return const _RecentChatsMessage(
        icon: Icons.cloud_off_rounded,
        text: 'Your recent chats could not be loaded.',
      );
    }

    final conversations = (snapshot.data ?? const <Conversation>[])
        .take(3)
        .toList(growable: false);
    if (conversations.isEmpty) {
      return _RecentChatsMessage(
        icon: Icons.chat_bubble_outline_rounded,
        text: 'Your latest chats with friends will appear here.',
        actionLabel: 'Find friends',
        onAction: onFindFriends,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = style == RecentChatsStyle.standard ? 10.0 : 12.0;

        Widget card(Conversation conversation, double width) => SizedBox(
          width: width,
          height: cardHeight,
          child: switch (style) {
            RecentChatsStyle.standard => _RecentChatCard(
              conversation: conversation,
              currentUserId: currentUserId,
              onTap: () => onOpenConversation(conversation),
            ),
            RecentChatsStyle.desktopBackdrop => _BackdropRecentChatCard(
              conversation: conversation,
              currentUserId: currentUserId,
              onTap: () => onOpenConversation(conversation),
              imageProvider: backdropImageProvider,
              photoStreamForUser: photoStreamForUser,
            ),
          },
        );

        // Phones keep every card readable instead of squeezing three tiny
        // columns into the viewport. Around 390 px this shows two complete
        // cards; the third remains one horizontal swipe away.
        if (constraints.maxWidth < 600) {
          final twoColumnWidth = (constraints.maxWidth - gap) / 2;
          final cardWidth = twoColumnWidth.clamp(156.0, 220.0);
          return SizedBox(
            height: cardHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  for (
                    var index = 0;
                    index < conversations.length;
                    index++
                  ) ...[
                    if (index > 0) SizedBox(width: gap),
                    card(conversations[index], cardWidth),
                  ],
                ],
              ),
            ),
          );
        }

        // Tablets and desktops show at most three equal cards without
        // stretching a one- or two-item list across the entire page.
        final cardWidth = (constraints.maxWidth - (gap * 2)) / 3;
        return SizedBox(
          height: cardHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < conversations.length; index++) ...[
                if (index > 0) SizedBox(width: gap),
                card(conversations[index], cardWidth),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _RecentChatCard extends StatelessWidget {
  const _RecentChatCard({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final otherUserId = conversation.otherUserId(currentUserId);
    final unread = conversation.unreadCountFor(currentUserId);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    displayName: conversation.displayNameFor(otherUserId),
                    photoUrl: conversation.photoUrlFor(otherUserId),
                    radius: 20,
                  ),
                  const Spacer(),
                  if (unread > 0) _UnreadBadge(count: unread, compact: true),
                ],
              ),
              const Spacer(),
              Text(
                conversation.displayNameFor(otherUserId),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                conversation.previewFor(currentUserId),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropRecentChatCard extends StatelessWidget {
  const _BackdropRecentChatCard({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
    required this.imageProvider,
    required this.photoStreamForUser,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;
  final RecentChatImageProvider? imageProvider;
  final RecentChatPhotoStream? photoStreamForUser;

  @override
  Widget build(BuildContext context) {
    final otherUserId = conversation.otherUserId(currentUserId);
    final unread = conversation.unreadCountFor(currentUserId);
    final displayName = conversation.displayNameFor(otherUserId);
    final conversationPhotoUrl = conversation.photoUrlFor(otherUserId);
    final preview = conversation.previewFor(currentUserId);
    final copy = AppLocalizations.of(context);
    final openLabel = copy.text(
      'Open chat with $displayName',
      'Otwórz czat z $displayName',
    );
    final polishFew =
        unread % 10 >= 2 &&
        unread % 10 <= 4 &&
        (unread % 100 < 12 || unread % 100 > 14);
    final unreadLabel = unread == 0
        ? ''
        : unread == 1
        ? copy.text('1 unread message', '1 nieprzeczytana wiadomość')
        : copy.text(
            '$unread unread messages',
            polishFew
                ? '$unread nieprzeczytane wiadomości'
                : '$unread nieprzeczytanych wiadomości',
          );
    final previewLabel = copy.text(
      'Last message: $preview',
      'Ostatnia wiadomość: $preview',
    );
    final semanticLabel = [
      openLabel,
      if (unreadLabel.isNotEmpty) unreadLabel,
      previewLabel,
    ].join('. ');

    return AccessibleTapRegion(
      onTap: onTap,
      semanticLabel: semanticLabel,
      tooltip: openLabel,
      borderRadius: 18,
      // This artwork can be any uploaded photo. AccessibleTapRegion draws
      // the complementary white ring too, so black is the robust paired
      // focus treatment over arbitrary light and dark pixels.
      focusContrastColor: Colors.black,
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF181122),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF3A2B4B)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _ChatBackdrop(
                conversationId: conversation.id,
                displayName: displayName,
                conversationPhotoUrl: conversationPhotoUrl,
                userId: otherUserId,
                imageProvider: imageProvider,
                photoStreamForUser: photoStreamForUser,
              ),
              const _ChatScrim(),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 0),
                child: unread > 0
                    ? Align(
                        alignment: Alignment.topRight,
                        child: _UnreadBadge(count: unread),
                      )
                    : const SizedBox.shrink(),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: double.infinity,
                      height: 24,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00090712),
                              Color(0x40090712),
                              Color(0xC4090712),
                            ],
                            stops: [0, .45, 1],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      key: ValueKey('recent-chat-text-seat-${conversation.id}'),
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(13, 8, 13, 12),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xC4090712), Color(0xF2090712)],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.12,
                              letterSpacing: -.1,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(
                                  color: Color(0xCC08050E),
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD8CEE1),
                              fontSize: 12,
                              height: 1.2,
                              shadows: [
                                Shadow(
                                  color: Color(0xE608050E),
                                  offset: Offset(0, 1),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A portrait fills the card rather than becoming a small detached avatar.
/// Broken/missing photos resolve to a deterministic branded fallback, so no
/// card ever shows an image error glyph.
class _ChatBackdrop extends StatelessWidget {
  const _ChatBackdrop({
    required this.conversationId,
    required this.displayName,
    required this.conversationPhotoUrl,
    required this.userId,
    required this.imageProvider,
    required this.photoStreamForUser,
  });

  final String conversationId;
  final String displayName;
  final String conversationPhotoUrl;
  final String userId;
  final RecentChatImageProvider? imageProvider;
  final RecentChatPhotoStream? photoStreamForUser;

  static const _accents = <Color>[
    Color(0xFF9D20FF),
    Color(0xFF6347E8),
    Color(0xFFE23D94),
    Color(0xFF188BD1),
  ];

  int get _stableConversationHash {
    var hash = 0;
    for (final unit in conversationId.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7FFFFFFF;
    }
    return hash;
  }

  Color get _fallbackAccent =>
      _accents[_stableConversationHash % _accents.length];

  String get _initial {
    final name = displayName.trim();
    return name.isEmpty ? '?' : name.characters.first.toUpperCase();
  }

  Widget _fallback() => DecoratedBox(
    key: ValueKey('recent-chat-fallback-$conversationId'),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF191122), Color(0xFF0F0B16)],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(.78, -.72),
              radius: .95,
              colors: [
                _fallbackAccent.withValues(alpha: .70),
                _fallbackAccent.withValues(alpha: .20),
                Colors.transparent,
              ],
              stops: const [0, .45, 1],
            ),
          ),
        ),
        Align(
          alignment: const Alignment(.72, -.56),
          child: Text(
            _initial,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .16),
              fontSize: 76,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _photo(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return _fallback();
    final provider = imageProvider?.call(url) ?? NetworkImage(url);

    return Stack(
      fit: StackFit.expand,
      children: [
        _fallback(),
        Image(
          key: ValueKey('recent-chat-photo-$conversationId'),
          image: provider,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -.20),
          filterQuality: FilterQuality.medium,
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => SizedBox.shrink(
            key: ValueKey('recent-chat-photo-error-$conversationId'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolver = photoStreamForUser;
    if (resolver == null) return _photo(conversationPhotoUrl);

    Stream<String> stream;
    try {
      stream = resolver(userId);
    } catch (_) {
      return _photo(conversationPhotoUrl);
    }

    return StreamBuilder<String>(
      stream: stream,
      builder: (context, snapshot) {
        // Until the authoritative public projection answers, keep the
        // conversation copy so the card never flashes to a placeholder.
        // An emitted empty value is authoritative (the avatar was removed).
        final photoUrl =
            snapshot.connectionState == ConnectionState.waiting ||
                snapshot.hasError ||
                !snapshot.hasData
            ? conversationPhotoUrl
            : snapshot.data!;
        return _photo(photoUrl);
      },
    );
  }
}

class _ChatScrim extends StatelessWidget {
  const _ChatScrim();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x10090712), Color(0x26090712), Color(0x5C090712)],
        stops: [0, .55, 1],
      ),
    ),
  );
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, this.compact = false});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      minWidth: compact ? 20 : 22,
      minHeight: compact ? 0 : 22,
    ),
    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF9D20FF),
      borderRadius: BorderRadius.circular(99),
      border: compact
          ? null
          : Border.all(color: Colors.white.withValues(alpha: .28)),
      boxShadow: compact
          ? null
          : const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _RecentChatsMessage extends StatelessWidget {
  const _RecentChatsMessage({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
          ),
          if (onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
