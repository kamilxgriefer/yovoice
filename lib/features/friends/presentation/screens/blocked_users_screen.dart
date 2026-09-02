import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({this.friendService, super.key});

  final FriendService? friendService;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  late final Stream<List<FriendUser>> _blockedStream;
  final Set<String> _processingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _blockedStream = _friendService.watchBlockedUsers();
  }

  Future<void> _unblock(FriendUser user) async {
    if (_processingIds.contains(user.id)) return;
    setState(() => _processingIds.add(user.id));
    try {
      await _friendService.unblockUser(user.id);
      if (mounted) {
        final palette = context.appPalette;
        final copy = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  '${user.displayName} unblocked.',
                  'Odblokowano użytkownika ${user.displayName}.',
                ),
                style: TextStyle(color: palette.successForeground),
              ),
              backgroundColor: palette.successSurface,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        final palette = context.appPalette;
        final copy = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                copy.text(
                  'Something went wrong. Please try again.',
                  'Coś poszło nie tak. Spróbuj ponownie.',
                ),
                style: TextStyle(color: palette.dangerForeground),
              ),
              backgroundColor: palette.dangerSurface,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('blocked-users-screen'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.list,
          alignment: ResponsiveContentAlignment.topLeft,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: copy.text('Back', 'Wstecz'),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: palette.textPrimary,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        copy.text('Blocked users', 'Zablokowani użytkownicy'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<FriendUser>>(
                  stream: _blockedStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: palette.interactiveForeground,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                color: palette.interactiveForeground,
                                size: 40,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                copy.text(
                                  'Could not load blocked users',
                                  'Nie udało się wczytać zablokowanych osób',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                copy.isPolish
                                    ? 'Sprawdź połączenie i spróbuj ponownie.'
                                    : friendlyErrorMessage(snapshot.error!),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final blocked = snapshot.data ?? const <FriendUser>[];
                    if (blocked.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.block_rounded,
                                color: palette.interactiveForeground,
                                size: 40,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                copy.text(
                                  'No blocked users',
                                  'Brak zablokowanych osób',
                                ),
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                copy.text(
                                  'People you block will appear here.',
                                  'Zablokowane osoby pojawią się tutaj.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                      itemCount: blocked.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final user = blocked[index];
                        final processing = _processingIds.contains(user.id);

                        return Container(
                          key: ValueKey('blocked-user-${user.id}'),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: palette.border),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final identity = Row(
                                children: [
                                  UserAvatar(
                                    radius: 24,
                                    userId: user.id,
                                    mediaRevision: user.profileUpdatedAt,
                                    displayName: user.displayName,
                                    backgroundColor: palette.surfaceSunken,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      user.displayName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                              final button = OutlinedButton(
                                onPressed: processing
                                    ? null
                                    : () => _unblock(user),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      palette.interactiveForeground,
                                  disabledForegroundColor: palette.textTertiary,
                                  side: BorderSide(color: palette.borderStrong),
                                  minimumSize: const Size(0, 44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                ),
                                child: processing
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(copy.text('Unblock', 'Odblokuj')),
                              );
                              final stackAction =
                                  constraints.maxWidth < 300 ||
                                  MediaQuery.textScalerOf(context).scale(1) >
                                      1.3;
                              if (stackAction) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    identity,
                                    const SizedBox(height: 12),
                                    button,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: identity),
                                  const SizedBox(width: 10),
                                  button,
                                ],
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
