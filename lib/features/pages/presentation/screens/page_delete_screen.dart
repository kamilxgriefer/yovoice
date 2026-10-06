import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_deletion_state.dart';
import 'package:yovoice/features/pages/data/services/page_deletion_center.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_delete_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_settings_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/settings/presentation/widgets/delete_account_consequences.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';

/// "Usuń stronę" (ADR-236; owner's choice pageDeleteWhat B + pageDeleteHow
/// B): what goes, what stays, the reported-content exception, the 30 days
/// to come back, and the Page's name typed as the confirmation.
///
/// Modelled on the account deletion screen: the same consequence list and
/// the same destructive button. Like Page settings it is always a pushed
/// screen with its own Back, in one 640 column on tablet and desktop.
///
/// Confirming calls `managePageDeletionV1 {op:"request"}`: the Page is
/// hidden at once and removed 30 days later; the route pops with the new
/// [PageDeletionState].
class PageDeleteScreen extends StatefulWidget {
  const PageDeleteScreen({
    required this.pageId,
    required this.name,
    required this.kind,
    required this.postCount,
    required this.followerCount,
    this.deletion,
    this.clock,
    super.key,
  });

  final String pageId;
  final String name;
  final PageKind kind;

  /// Published posts and followers, as the lists name them.
  final int postCount;
  final int followerCount;

  /// Test seams; the app uses the shared instance and the wall clock.
  final PageDeletionCenter? deletion;
  final DateTime Function()? clock;

  /// The server's window (functions/pages/deletion.js
  /// PAGE_DELETION_WINDOW_MS), for the date this screen promises.
  static const Duration window = Duration(days: 30);

  @override
  State<PageDeleteScreen> createState() => _PageDeleteScreenState();
}

class _PageDeleteScreenState extends State<PageDeleteScreen> {
  late final PageDeletionCenter _deletion =
      widget.deletion ?? PageDeletionCenter.instance;
  final TextEditingController _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The name as typed matches the Page's, whatever the keyboard did to
  /// its capitals or its edges.
  bool get _matches =>
      _text.text.trim().toLowerCase() == widget.name.trim().toLowerCase();

  Future<void> _delete() async {
    if (_busy || !_matches) return;
    final copy = PagesCopy(AppLocalizations.of(context));
    setState(() => _busy = true);
    try {
      final state = await _deletion.requestDeletion();
      if (mounted) Navigator.of(context).pop(state);
    } on PagesException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(copy.manageError(error.failure))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = PagesCopy(AppLocalizations.of(context));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final deleteAt = (widget.clock ?? DateTime.now)().add(
      PageDeleteScreen.window,
    );
    final hasPosts = widget.postCount > 0;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          key: const ValueKey('page-delete-list'),
          padding: EdgeInsets.only(top: wide ? 24 : 0),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PageSettingsScreen.columnWidth + 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageSettingsTitleBar(
                      title: copy.deletePage,
                      onBack: Navigator.of(context).canPop()
                          ? () => unawaited(Navigator.of(context).maybePop())
                          : null,
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          YoCard(
                            key: const ValueKey('page-delete-identity'),
                            semanticButton: false,
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                PageFace(
                                  pageId: widget.pageId,
                                  name: widget.name,
                                  kind: widget.kind,
                                  size: 52,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      NameWithVipMark(
                                        uid: widget.pageId,
                                        name: widget.name,
                                        style: AppTypography.titleMedium
                                            .copyWith(
                                              color: palette.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 17,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${copy.kindLabel(widget.kind)} · ${copy.exactFollowers(widget.followerCount)}',
                                        style: AppTypography.bodySmall.copyWith(
                                          color: palette.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          PageSettingsGroupLabel(
                            copy.goesOverline,
                            danger: true,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DeleteAccountConsequenceList(
                              key: const ValueKey('page-delete-goes'),
                              items: [
                                DeleteAccountConsequence(
                                  icon: Icons.public_off_outlined,
                                  text: copy.goesPage,
                                ),
                                if (hasPosts) ...[
                                  DeleteAccountConsequence(
                                    icon: Icons.photo_library_outlined,
                                    text: copy.goesPosts(widget.postCount),
                                  ),
                                  DeleteAccountConsequence(
                                    icon: Icons.forum_outlined,
                                    text: copy.goesEngagement,
                                  ),
                                ],
                                DeleteAccountConsequence(
                                  icon: Icons.group_off_outlined,
                                  text: copy.goesFollowers(
                                    widget.followerCount,
                                  ),
                                ),
                                if (widget.kind == PageKind.business)
                                  DeleteAccountConsequence(
                                    icon: Icons.contact_phone_outlined,
                                    text: copy.goesContact,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          PageSettingsGroupLabel(copy.staysOverline),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DeleteAccountConsequenceList(
                              key: const ValueKey('page-delete-stays'),
                              danger: false,
                              items: [
                                DeleteAccountConsequence(
                                  icon: Icons.person_outline_rounded,
                                  text: copy.staysAccount,
                                ),
                                DeleteAccountConsequence(
                                  icon: Icons.forum_outlined,
                                  text: copy.staysSocial,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          PageNotice(
                            key: const ValueKey('page-delete-exception'),
                            tone: PageTone.neutral,
                            icon: Icons.shield_outlined,
                            title: copy.reportedExceptionTitle,
                            body: copy.reportedExceptionBody,
                          ),
                          const SizedBox(height: 12),
                          PageNotice(
                            key: const ValueKey('page-delete-grace'),
                            tone: PageTone.info,
                            icon: Icons.history_rounded,
                            title: copy.graceTitle,
                            body: copy.graceBody(deleteAt),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            key: const ValueKey('page-delete-name'),
                            controller: _text,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => unawaited(_delete()),
                            style: AppTypography.bodyLarge.copyWith(
                              color: palette.textPrimary,
                              fontSize: 16,
                            ),
                            decoration: InputDecoration(
                              labelText: copy.typeNameLabel,
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              hintText: widget.name,
                              helperText: copy.typeNameHelper(widget.name),
                              helperMaxLines: 3,
                              filled: true,
                              fillColor: palette.surface,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('page-delete-confirm'),
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.errorContainer,
                              foregroundColor: colors.onErrorContainer,
                              minimumSize: const Size.fromHeight(52),
                            ),
                            onPressed: _matches && !_busy
                                ? () => unawaited(_delete())
                                : null,
                            icon: _busy
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.onErrorContainer,
                                    ),
                                  )
                                : const Icon(Icons.delete_forever_rounded),
                            label: Text(
                              copy.deletePage,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
