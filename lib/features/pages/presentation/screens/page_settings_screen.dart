import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_deletion_state.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_catalog.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/page_deletion_center.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_delete_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/screens/page_delete_screen.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_menus.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/settings/presentation/screens/profile_visibility_screen.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/navigation/yo_server_rail_item.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// The contact / community fields an owner edits in a one-field sheet.
enum PageSettingsField {
  category,
  description,
  website,
  email,
  phone,
  address,
  hours,
  legalNotice,
  rules,
  linkedServer,
}

/// Page settings, variant A "lista" (approved R6 `pages-r/settings/A_*`;
/// spec premium-pages §4.4): the app's Settings rows. The identity card
/// with the status pill; STRONA (type locked, D16; category; description;
/// name and photos through the profile editor); KONTAKT · WIDOCZNE
/// PUBLICZNIE with one-field sheets that edit or clear each value and the
/// retention line; OBSERWUJĄCY as a count only (D12: no list); WIDOCZNOŚĆ
/// STRONY with Wstrzymaj / Wznów; and STREFA ZAGROŻENIA (ADR-236): "Usuń
/// wszystkie posty" and "Usuń stronę". While a deletion is pending the
/// screen leads with the date and "Przywróć stronę", every edit row is
/// disabled, and the zone offers "Usuń teraz, nie czekaj".
///
/// Always a pushed screen (from the Page profile), so it carries its own
/// Back on every width; tablet and desktop centre one 640 column.
class PageSettingsScreen extends StatefulWidget {
  const PageSettingsScreen({
    this.service,
    this.accessStream,
    this.profileStream,
    this.serverStream,
    this.userId,
    this.clock,
    this.deletion,
    super.key,
  });

  /// Test seams; the app uses the shared instances.
  final PageDeletionCenter? deletion;
  final PagesService? service;
  final Stream<PageAccessState> Function()? accessStream;
  final Stream<UserProfile> Function()? profileStream;
  final Stream<List<Server>> Function()? serverStream;
  final String? userId;
  final DateTime Function()? clock;

  static const double columnWidth = 640;

  @override
  State<PageSettingsScreen> createState() => _PageSettingsScreenState();
}

class _PageSettingsScreenState extends State<PageSettingsScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final String _userId = widget.userId ?? _currentUserId();
  late final Stream<PageAccessState> _access =
      (widget.accessStream ?? PageAccessService.instance.watch)();
  late final Stream<UserProfile> _profile =
      (widget.profileStream ?? () => ProfileService().watchCurrentProfile())();

  late final PageDeletionCenter _deletion =
      widget.deletion ?? PageDeletionCenter.instance;

  bool _busy = false;
  bool _askedAfterGone = false;
  StreamSubscription<List<Server>>? _serversSub;
  Map<String, String> _serverNames = const <String, String>{};

  /// The linked server's name for its row, read from the owner's servers
  /// the first time a community Page is shown.
  void _watchServerNames() {
    if (_serversSub != null) return;
    final stream =
        (widget.serverStream ?? () => ServerService().watchMyServers())();
    _serversSub = stream.listen((servers) {
      if (!mounted) return;
      setState(() => _serverNames = {for (final s in servers) s.id: s.name});
    }, onError: (Object _, StackTrace _) {});
  }

  @override
  void initState() {
    super.initState();
    // ADR-236: the deletion state lives outside pages/{uid}; ask for it.
    _deletion.addListener(_onDeletionChanged);
    unawaited(_deletion.refresh());
  }

  void _onDeletionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _deletion.removeListener(_onDeletionChanged);
    unawaited(_serversSub?.cancel());
    super.dispose();
  }

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  PagesCopy get _copy => PagesCopy(AppLocalizations.of(context));

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- writes

  Future<bool> _update(
    OwnPage page, {
    String? category,
    String? description,
    PageBusinessInfo? business,
    Object? rules = _keep,
    Object? linkedServerId = _keep,
  }) async {
    final kind = page.kind;
    if (kind == null || _busy) return false;
    setState(() => _busy = true);
    try {
      await _service.updatePage(
        kind: kind,
        category: category ?? page.category,
        description: description ?? page.description,
        business: kind == PageKind.business
            ? (business ?? page.business ?? PageBusinessInfo.empty)
            : null,
        rules: identical(rules, _keep) ? page.rules : rules as String?,
        linkedServerId: identical(linkedServerId, _keep)
            ? page.linkedServerId
            : linkedServerId as String?,
      );
      if (mounted) _snack(_copy.saved);
      return true;
    } on PagesException catch (error) {
      if (mounted) _snack(_copy.manageError(error.failure));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    final copy = _copy;
    final confirmed = await confirmPageAction(
      context,
      title: copy.pauseTitle,
      body: copy.pauseBody,
      confirm: copy.pause,
      cancel: copy.cancel,
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.pausePage();
      if (mounted) _snack(copy.pagePausedSnack);
    } on PagesException catch (error) {
      if (mounted) _snack(copy.manageError(error.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume() async {
    final copy = _copy;
    setState(() => _busy = true);
    try {
      await _service.resumePage();
      if (mounted) _snack(copy.pageResumedSnack);
    } on PagesException catch (error) {
      if (mounted) _snack(copy.manageError(error.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------- deletion (ADR-236)

  /// One deletion op with the busy flag and the refusal in words.
  Future<PageDeletionState?> _deletionOp(
    Future<PageDeletionState> Function() op,
  ) async {
    final copy = _copy;
    setState(() => _busy = true);
    try {
      return await op();
    } on PagesException catch (error) {
      if (mounted) _snack(copy.manageError(error.failure));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearPosts(OwnPage page, int followers) async {
    final copy = _copy;
    final confirmed = await confirmPageAction(
      context,
      title: copy.clearPostsTitle(page.postCount),
      body: copy.clearPostsBody(followers),
      confirm: copy.deletePosts,
      cancel: copy.cancel,
    );
    if (!confirmed || !mounted) return;
    final state = await _deletionOp(_deletion.clearPosts);
    if (state == null || !mounted) return;
    _snack(
      state.postsClearingSince == null ? copy.postsDeleted : copy.clearingTitle,
    );
  }

  Future<void> _openDelete(OwnPage page, String name, int followers) async {
    final copy = _copy;
    final kind = page.kind;
    if (kind == null) return;
    final state = await Navigator.of(context).push<PageDeletionState>(
      MaterialPageRoute<PageDeletionState>(
        settings: const RouteSettings(name: 'pages/delete'),
        builder: (_) => PageDeleteScreen(
          pageId: _userId,
          name: name,
          kind: kind,
          postCount: page.postCount,
          followerCount: followers,
          deletion: _deletion,
          clock: widget.clock,
        ),
      ),
    );
    final deletion = state?.deletion;
    if (deletion == null || !mounted) return;
    _snack(copy.pendingTitle(deletion.deleteAt));
  }

  Future<void> _restore() async {
    final copy = _copy;
    final state = await _deletionOp(_deletion.restore);
    if (state != null && mounted) _snack(copy.pageRestored);
  }

  Future<void> _deleteNow() async {
    final copy = _copy;
    final confirmed = await confirmPageAction(
      context,
      title: copy.deleteNowTitle,
      body: copy.deleteNowBody,
      confirm: copy.delete,
      cancel: copy.cancel,
    );
    if (!confirmed || !mounted) return;
    final state = await _deletionOp(_deletion.purgeNow);
    if (state == null || !mounted || state.pageExists) return;
    // A small Page is gone before the call answers: say so and leave, there
    // is nothing left to set. (A larger one shows the purging notice; the
    // worker finishes it.)
    _snack(copy.pageDeleted);
    unawaited(Navigator.of(context).maybePop());
  }

  /// The Page is gone while this screen is open (the purge finished): the
  /// plain fact and when a new Page can be created, instead of an error.
  /// Null when no deletion is known, i.e. the account simply has no Page.
  Widget? _deletedBlock(PagesCopy copy) {
    final state = _deletion.state;
    if (state == null ||
        (state.deletion == null && state.recreateAllowedAt == null)) {
      return null;
    }
    if (state.pageExists && !_askedAfterGone) {
      // What this screen knows is older than the Page's removal: ask once
      // for the date a new Page can be created.
      _askedAfterGone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_deletion.refresh());
      });
    }
    final until = state.recreateAllowedAt;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: PagesStateBlock(
        key: const ValueKey('settings-page-deleted'),
        icon: Icons.auto_delete_outlined,
        title: copy.pageDeleted,
        body: until == null ? null : copy.recreateAfter(until),
        liveRegion: true,
      ),
    );
  }

  void _openProfileEditor(UserProfile? profile) {
    if (profile == null) return;
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => EditProfileScreen(profile: profile),
        ),
      ),
    );
  }

  void _openVisibility(UserProfile? profile) {
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProfileVisibilityScreen(
            initialVisibility:
                profile?.profileVisibility ?? ProfileVisibility.private,
          ),
        ),
      ),
    );
  }

  Future<void> _editField(OwnPage page, PageSettingsField field) async {
    final copy = _copy;
    final kind = page.kind;
    if (kind == null) return;
    switch (field) {
      case PageSettingsField.category:
        final picked = await pickPageCategory(
          context,
          kind: kind,
          selected: page.category,
        );
        if (picked != null && picked != page.category && mounted) {
          await _update(page, category: picked);
        }
      case PageSettingsField.linkedServer:
        final picked = await pickLinkedServer(
          context,
          userId: _userId,
          selected: page.linkedServerId,
          servers: widget.serverStream,
        );
        if (picked != null &&
            picked.serverId != page.linkedServerId &&
            mounted) {
          await _update(page, linkedServerId: picked.serverId);
        }
      default:
        final spec = _fieldSpec(copy, page, field);
        final result = await showModalBottomSheet<_FieldResult>(
          context: context,
          useRootNavigator: true,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: context.appPalette.surfaceRaised,
          constraints: const BoxConstraints(maxWidth: 560),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (_) => _FieldSheet(spec: spec),
        );
        if (result == null || !mounted) return;
        final value = result.value;
        if (value == spec.initial) return;
        final business = page.business ?? PageBusinessInfo.empty;
        switch (field) {
          case PageSettingsField.description:
            await _update(page, description: value ?? '');
          case PageSettingsField.website:
            await _update(page, business: business.copyWith(website: value));
          case PageSettingsField.email:
            await _update(page, business: business.copyWith(email: value));
          case PageSettingsField.phone:
            await _update(page, business: business.copyWith(phone: value));
          case PageSettingsField.address:
            await _update(page, business: business.copyWith(address: value));
          case PageSettingsField.hours:
            await _update(page, business: business.copyWith(hours: value));
          case PageSettingsField.legalNotice:
            await _update(
              page,
              business: business.copyWith(legalNotice: value),
            );
          case PageSettingsField.rules:
            await _update(page, rules: value);
          case PageSettingsField.category:
          case PageSettingsField.linkedServer:
            break;
        }
    }
  }

  _FieldSpec _fieldSpec(PagesCopy copy, OwnPage page, PageSettingsField field) {
    final business = page.business ?? PageBusinessInfo.empty;
    return switch (field) {
      PageSettingsField.description => _FieldSpec(
        title: copy.descriptionLabel,
        body: copy.publicOnPage,
        label: copy.descriptionLabel,
        icon: Icons.notes_rounded,
        initial: page.description.isEmpty ? null : page.description,
        maxLength: PageFieldRules.description,
        multiline: true,
        clearable: false,
      ),
      PageSettingsField.website => _FieldSpec(
        title: copy.websiteLabel,
        body: copy.publicOnPage,
        label: copy.websiteLabel,
        icon: Icons.language_rounded,
        initial: business.website,
        maxLength: PageFieldRules.website,
        keyboard: TextInputType.url,
        helper: copy.httpsOnly,
        validate: (v) => PageFieldRules.websiteOk(v) ? null : copy.websiteError,
      ),
      PageSettingsField.email => _FieldSpec(
        title: copy.emailLabel,
        body: copy.publicOnPage,
        label: copy.contactEmailLabel,
        icon: Icons.mail_outline_rounded,
        initial: business.email,
        maxLength: PageFieldRules.email,
        keyboard: TextInputType.emailAddress,
        validate: (v) => PageFieldRules.emailOk(v) ? null : copy.emailError,
      ),
      PageSettingsField.phone => _FieldSpec(
        title: copy.phoneLabel,
        body: copy.phoneSheetBody,
        label: copy.phoneNumberLabel,
        icon: Icons.call_outlined,
        initial: business.phone,
        maxLength: 32,
        keyboard: TextInputType.phone,
        helper: copy.phoneHelper,
        validate: (v) => PageFieldRules.phoneOk(v) ? null : copy.phoneError,
        clearLabel: copy.removeNumberFromPage,
      ),
      PageSettingsField.address => _FieldSpec(
        title: copy.addressLabel,
        body: copy.publicOnPage,
        label: copy.addressOrAreaLabel,
        icon: Icons.place_outlined,
        initial: business.address,
        maxLength: PageFieldRules.address,
      ),
      PageSettingsField.hours => _FieldSpec(
        title: copy.hoursLabel,
        body: copy.publicOnPage,
        label: copy.hoursLabel,
        icon: Icons.schedule_rounded,
        initial: business.hours,
        maxLength: PageFieldRules.hours,
      ),
      PageSettingsField.legalNotice => _FieldSpec(
        title: copy.legalNotice,
        body: copy.publicOnPage,
        label: copy.legalNoticeFieldLabel,
        icon: Icons.gavel_rounded,
        initial: business.legalNotice,
        maxLength: PageFieldRules.legalNotice,
        multiline: true,
        hint: copy.legalNoticeHint,
      ),
      PageSettingsField.rules => _FieldSpec(
        title: copy.rulesTitle,
        body: copy.publicOnPage,
        label: copy.rulesTitle,
        icon: Icons.rule_rounded,
        initial: page.rules,
        maxLength: PageFieldRules.rules,
        multiline: true,
      ),
      PageSettingsField.category ||
      PageSettingsField.linkedServer => throw ArgumentError.value(field),
    };
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = _copy;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<PageAccessState>(
          stream: _access,
          builder: (context, accessSnapshot) => StreamBuilder<UserProfile>(
            stream: _profile,
            builder: (context, profileSnapshot) {
              final access = accessSnapshot.data;
              final profile = profileSnapshot.hasError
                  ? null
                  : profileSnapshot.data;
              Widget body;
              if (accessSnapshot.hasError) {
                body = Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: YoErrorState(message: copy.loadSettingsError),
                );
              } else if (access == null || !access.resolved) {
                body = Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: YoLoadingIndicator(semanticLabel: copy.loadingPage),
                  ),
                );
              } else if (access.ownPage == null ||
                  access.ownPage!.kind == null) {
                body =
                    (access.ownPage == null ? _deletedBlock(copy) : null) ??
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: YoErrorState(message: copy.noPageYet),
                    );
              } else {
                body = _content(context, access.ownPage!, profile);
              }
              // Desktop (the shell's wide content slot) has no status bar
              // above the title: give it the standard page top margin.
              final wide = MediaQuery.sizeOf(context).width >= 900;
              return ListView(
                key: const ValueKey('page-settings-list'),
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
                          _TitleBar(
                            title: copy.pageSettings,
                            onBack: Navigator.of(context).canPop()
                                ? () => unawaited(
                                    Navigator.of(context).maybePop(),
                                  )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                            child: body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  PageHeaderState _stateOf(OwnPage page) {
    if (page.suspended) return PageHeaderState.suspended;
    if (page.status == 'hidden') return PageHeaderState.hidden;
    if (page.ownerPaused) return PageHeaderState.paused;
    if (page.status == 'readOnly') return PageHeaderState.readOnly;
    return PageHeaderState.active;
  }

  Widget _content(BuildContext context, OwnPage page, UserProfile? profile) {
    final copy = _copy;
    final palette = context.appPalette;
    final kind = page.kind!;
    final state = _stateOf(page);
    final private =
        profile != null &&
        profile.profileVisibility != ProfileVisibility.public;
    // ADR-236: a pending deletion locks every edit; a running purge leaves
    // nothing to do here at all.
    final deletion = _deletion.state?.deletion;
    final pending = deletion?.phase == PageDeletionPhase.pending;
    final purging = deletion?.phase == PageDeletionPhase.purging;
    final locked = deletion != null;
    final editable = !page.suspended && !_busy && !locked;
    final name = page.displayName ?? profile?.displayName ?? copy.yourPage;
    final business = page.business ?? PageBusinessInfo.empty;
    final categoryLabel = copy.categoryLabel(page.category);
    final pill = locked
        ? (label: copy.statusPendingDeletion, tone: PageTone.warning)
        : pageStatusPill(copy, state);
    final followerCount = profile?.accountFollowerCount ?? 0;
    if (kind == PageKind.community && page.linkedServerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _watchServerNames();
      });
    }

    Widget? notice;
    if (deletion != null && purging) {
      notice = PageNotice(
        key: const ValueKey('settings-notice-purging'),
        tone: PageTone.warning,
        icon: Icons.auto_delete_outlined,
        title: copy.purgingTitle,
        body: copy.purgingBody,
      );
    } else if (deletion != null) {
      notice = PageNotice(
        key: const ValueKey('settings-notice-pending'),
        tone: PageTone.warning,
        icon: Icons.auto_delete_outlined,
        title: copy.pendingTitle(deletion.deleteAt),
        body: copy.pendingSettingsBody,
        actions: [
          YoGradientFilledButton(
            key: const ValueKey('settings-notice-restore'),
            onPressed: _busy ? null : () => unawaited(_restore()),
            minimumSize: const Size(64, 40),
            icon: const Icon(Icons.restore_rounded, size: 20),
            child: Text(copy.restorePage),
          ),
        ],
      );
    } else if (state == PageHeaderState.paused) {
      notice = private
          ? PageNotice(
              key: const ValueKey('settings-notice-private'),
              tone: PageTone.warning,
              icon: Icons.lock_outline_rounded,
              title: copy.pausedTitle,
              body: copy.pausedPrivateBody,
              actions: [
                PageTonalButton(
                  label: copy.profileVisibility,
                  icon: Icons.visibility_outlined,
                  height: 40,
                  onPressed: () => _openVisibility(profile),
                ),
              ],
            )
          : PageNotice(
              key: const ValueKey('settings-notice-paused'),
              tone: PageTone.info,
              icon: Icons.pause_circle_outline_rounded,
              title: copy.pausedTitle,
              body: copy.pausedBody,
              actions: [
                YoGradientFilledButton(
                  key: const ValueKey('settings-notice-resume'),
                  onPressed: _busy ? null : () => unawaited(_resume()),
                  minimumSize: const Size(64, 40),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  child: Text(copy.resumePage),
                ),
              ],
            );
    } else if (state == PageHeaderState.suspended) {
      notice = PageNotice(
        tone: PageTone.danger,
        icon: Icons.gavel_rounded,
        title: copy.suspendedTitle,
        body: copy.suspendedBody(page.suspensionReason),
      );
    } else if (state == PageHeaderState.readOnly) {
      notice = PageNotice(
        tone: PageTone.warning,
        icon: Icons.hourglass_bottom_rounded,
        title: copy.readOnlyTitle,
        body: copy.readOnlyBody(),
      );
    } else if (state == PageHeaderState.hidden) {
      notice = PageNotice(
        tone: PageTone.neutral,
        icon: Icons.visibility_off_outlined,
        title: copy.hiddenTitle,
        body: copy.hiddenBody,
      );
    }

    Widget contactTile(
      PageSettingsField field,
      IconData icon,
      String label,
      String? value,
    ) => _SettingsTile(
      key: ValueKey('settings-${field.name}'),
      icon: icon,
      title: label,
      subtitle: value ?? copy.notAdded,
      subtitleLines: 1,
      enabled: editable,
      trailing: value == null
          ? Text(
              copy.add,
              style: AppTypography.labelLarge.copyWith(
                color: palette.interactiveForeground,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
      chevron: value != null,
      onTap: () => unawaited(_editField(page, field)),
    );

    final followers = profile?.followerCount;
    return Column(
      key: const ValueKey('page-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[notice, const SizedBox(height: 16)],
        YoCard(
          key: const ValueKey('settings-identity'),
          onTap: () => unawaited(Navigator.of(context).maybePop()),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            children: [
              PageFace(pageId: _userId, name: name, kind: kind, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NameWithVipMark(
                      uid: _userId,
                      name: name,
                      style: AppTypography.titleMedium.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${copy.kindLabel(kind)} · $categoryLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PageStatusPill(
                      key: const ValueKey('settings-status'),
                      label: pill.label,
                      tone: pill.tone,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _GroupLabel(copy.pageGroup),
        _SettingsGroup(
          children: [
            _SettingsTile(
              icon: kind == PageKind.business
                  ? Icons.storefront_outlined
                  : Icons.groups_2_outlined,
              title: copy.pageType,
              subtitle: copy.kindLabel(kind),
              trailing: Tooltip(
                message: copy.pageTypeLocked,
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: palette.textTertiary,
                  semanticLabel: copy.pageTypeLocked,
                ),
              ),
            ),
            _SettingsTile(
              key: const ValueKey('settings-category'),
              icon: Icons.category_outlined,
              title: copy.categoryField(kind),
              subtitle: categoryLabel,
              chevron: true,
              enabled: editable,
              onTap: () =>
                  unawaited(_editField(page, PageSettingsField.category)),
            ),
            _SettingsTile(
              key: const ValueKey('settings-description'),
              icon: Icons.notes_rounded,
              title: copy.descriptionLabel,
              subtitle: page.description.isEmpty
                  ? copy.notAdded
                  : page.description,
              subtitleLines: 2,
              chevron: true,
              enabled: editable,
              onTap: () =>
                  unawaited(_editField(page, PageSettingsField.description)),
            ),
            _SettingsTile(
              key: const ValueKey('settings-name-photos'),
              icon: Icons.badge_outlined,
              title: copy.nameAndPhotos,
              subtitle: copy.nameAndPhotosBody,
              chevron: true,
              enabled: profile != null && !locked,
              onTap: () => _openProfileEditor(profile),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (kind == PageKind.business) ...[
          _GroupLabel(copy.contactGroup),
          _SettingsGroup(
            children: [
              contactTile(
                PageSettingsField.website,
                Icons.language_rounded,
                copy.websiteLabel,
                business.website,
              ),
              contactTile(
                PageSettingsField.email,
                Icons.mail_outline_rounded,
                copy.emailLabel,
                business.email,
              ),
              contactTile(
                PageSettingsField.phone,
                Icons.call_outlined,
                copy.phoneLabel,
                business.phone,
              ),
              contactTile(
                PageSettingsField.address,
                Icons.place_outlined,
                copy.addressLabel,
                business.address,
              ),
              contactTile(
                PageSettingsField.hours,
                Icons.schedule_rounded,
                copy.hoursLabel,
                business.hours,
              ),
              contactTile(
                PageSettingsField.legalNotice,
                Icons.gavel_rounded,
                copy.legalNotice,
                business.legalNotice,
              ),
            ],
          ),
          PageFootnote(copy.retention),
        ] else ...[
          _GroupLabel(copy.communityGroup),
          _SettingsGroup(
            children: [
              contactTile(
                PageSettingsField.rules,
                Icons.rule_rounded,
                copy.rulesTitle,
                page.rules,
              ),
              contactTile(
                PageSettingsField.linkedServer,
                Icons.hub_outlined,
                copy.linkedServerLabel,
                page.linkedServerId == null
                    ? null
                    : _serverNames[page.linkedServerId] ??
                          copy.linkedServerLabel,
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _GroupLabel(copy.followersGroup),
        _SettingsGroup(
          children: [
            _SettingsTile(
              key: const ValueKey('settings-followers'),
              icon: Icons.people_alt_outlined,
              title: followers == null
                  ? copy.followersGroup
                  : copy.exactFollowers(followers),
              subtitle: copy.followersOnlyCount,
            ),
          ],
        ),
        const SizedBox(height: 24),
        // A running purge has no visibility left to change.
        if (!purging) ...[
          _GroupLabel(copy.visibilityGroup),
          _SettingsGroup(
            children: [
              if (pending)
                _SettingsTile(
                  key: const ValueKey('settings-restore'),
                  icon: Icons.restore_rounded,
                  title: copy.restorePage,
                  subtitle: copy.restoreSubtitle,
                  chevron: true,
                  enabled: !_busy,
                  onTap: () => unawaited(_restore()),
                )
              else if (!page.ownerPaused)
                _SettingsTile(
                  key: const ValueKey('settings-pause'),
                  icon: Icons.pause_circle_outline_rounded,
                  title: copy.pausePage,
                  subtitle: copy.pauseSubtitle,
                  chevron: true,
                  enabled: !_busy,
                  onTap: () => unawaited(_pause()),
                )
              else
                _SettingsTile(
                  key: const ValueKey('settings-resume'),
                  icon: Icons.play_circle_outline_rounded,
                  title: copy.resumePage,
                  subtitle: private
                      ? copy.resumeNeedsPublic
                      : copy.resumeSubtitle,
                  chevron: true,
                  enabled: !private && !page.suspended && !_busy,
                  onTap: () => unawaited(_resume()),
                ),
            ],
          ),
          ..._dangerZone(
            page,
            name: name,
            followers: followerCount,
            deletion: deletion,
          ),
        ],
      ],
    );
  }

  /// STREFA ZAGROŻENIA (ADR-236; chosen frames 6_pageDeleteWhat B1 and
  /// 6_pageDeleteHow B3): "Usuń wszystkie posty" and "Usuń stronę", or,
  /// while a deletion is pending, "Usuń teraz, nie czekaj".
  List<Widget> _dangerZone(
    OwnPage page, {
    required String name,
    required int followers,
    required PageDeletionInfo? deletion,
  }) {
    final copy = _copy;
    return [
      const SizedBox(height: 24),
      _GroupLabel(copy.dangerZone, danger: true),
      _SettingsGroup(
        key: const ValueKey('settings-danger-zone'),
        danger: true,
        children: [
          if (deletion != null)
            _SettingsTile(
              key: const ValueKey('settings-delete-now'),
              icon: Icons.delete_forever_rounded,
              title: copy.deleteNow,
              subtitle: copy.deleteNowSubtitle(deletion.deleteAt),
              danger: true,
              chevron: true,
              enabled: !_busy,
              onTap: () => unawaited(_deleteNow()),
            )
          else ...[
            _SettingsTile(
              key: const ValueKey('settings-delete-posts'),
              icon: Icons.delete_sweep_outlined,
              title: copy.deleteAllPosts,
              subtitle: copy.deleteAllPostsSubtitle,
              danger: true,
              chevron: true,
              // Nothing to delete on a Page with no published post.
              enabled: !_busy && page.postCount > 0,
              onTap: () => unawaited(_clearPosts(page, followers)),
            ),
            _SettingsTile(
              key: const ValueKey('settings-delete-page'),
              icon: Icons.delete_forever_rounded,
              title: copy.deletePage,
              subtitle: copy.deletePageSubtitle,
              danger: true,
              chevron: true,
              enabled: !_busy,
              onTap: () => unawaited(_openDelete(page, name, followers)),
            ),
          ],
        ],
      ),
    ];
  }
}

/// The settings title bar and group label, for the screens settings pushes
/// (`PageDeleteScreen`).
typedef PageSettingsTitleBar = _TitleBar;
typedef PageSettingsGroupLabel = _GroupLabel;

const Object _keep = Object();

// ---------------------------------------------------------------------------
// Settings rows (the Settings screen's Slim tile and group)
// ---------------------------------------------------------------------------

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        onBack == null ? 16 : 6,
        10,
        12,
        6,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            YoIconButton(
              key: const ValueKey('page-settings-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              size: 44,
              tooltip: copy.goBack,
              onPressed: onBack,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.screenTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.danger = false});

  final String text;

  /// The destructive ink ("STREFA ZAGROŻENIA", "ZNIKNIE").
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: AppTypography.overline.copyWith(
            color: danger
                ? Theme.of(context).colorScheme.error
                : palette.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 11 * .08,
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.children,
    this.danger = false,
    super.key,
  });

  final List<Widget> children;

  /// The destructive edge of the danger zone.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final fill = AppFinish.blockFill(palette);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.block,
        boxShadow: fill.boxShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.block,
          side: BorderSide(
            color: danger
                ? Theme.of(context).colorScheme.error.withValues(alpha: .45)
                : palette.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(color: fill.color, gradient: fill.gradient),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 68,
                    color: palette.hairline,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.chevron = false,
    this.enabled = true,
    this.subtitleLines = 3,
    this.onTap,
    this.danger = false,
    super.key,
  });

  /// A destructive row: the danger glyph and title ink.
  final bool danger;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool chevron;
  final bool enabled;
  final int subtitleLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final tile = ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      minLeadingWidth: 40,
      horizontalTitleGap: 12,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      leading: SizedBox.square(
        dimension: 40,
        child: Center(child: PageGlyph(icon, danger: danger)),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyLarge.copyWith(
          color: danger
              ? Theme.of(context).colorScheme.error
              : palette.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: subtitleLines,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
      trailing:
          trailing ??
          (chevron
              ? Icon(Icons.chevron_right_rounded, color: palette.textTertiary)
              : null),
    );
    return enabled || onTap == null ? tile : Opacity(opacity: .45, child: tile);
  }
}

// ---------------------------------------------------------------------------
// One-field sheet (R6 A "edycja pola")
// ---------------------------------------------------------------------------

class _FieldSpec {
  const _FieldSpec({
    required this.title,
    required this.body,
    required this.label,
    required this.icon,
    required this.initial,
    required this.maxLength,
    this.multiline = false,
    this.clearable = true,
    this.keyboard,
    this.helper,
    this.hint,
    this.validate,
    this.clearLabel,
  });

  /// The field's own "remove" wording (A_ustawienia: "Usuń numer ze
  /// strony"); null keeps the generic "Usuń ze strony".
  final String? clearLabel;

  final String title;
  final String body;
  final String label;
  final IconData icon;
  final String? initial;
  final int maxLength;
  final bool multiline;
  final bool clearable;
  final TextInputType? keyboard;
  final String? helper;
  final String? hint;
  final String? Function(String value)? validate;
}

class _FieldResult {
  const _FieldResult(this.value);

  /// The new value; null clears the field.
  final String? value;
}

class _FieldSheet extends StatefulWidget {
  const _FieldSheet({required this.spec});

  final _FieldSpec spec;

  @override
  State<_FieldSheet> createState() => _FieldSheetState();
}

class _FieldSheetState extends State<_FieldSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.spec.initial ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final spec = widget.spec;
    final value = _text.text;
    final error = spec.validate?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final trimmed = value.trim();
    Navigator.of(context).pop(
      _FieldResult(
        trimmed.isEmpty && spec.clearable
            ? null
            : spec.multiline
            ? trimmed
            : PageFieldRules.optional(trimmed) ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = PagesCopy(AppLocalizations.of(context));
    final spec = widget.spec;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoModalSheetChrome(
                sheetLabel: spec.title,
                surfaceColor: palette.surfaceRaised,
                onClose: () => Navigator.of(context).pop(),
              ),
              Semantics(
                header: true,
                child: Text(
                  spec.title,
                  style: AppTypography.screenTitle.copyWith(
                    color: palette.textPrimary,
                    fontSize: 21,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                spec.body,
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('page-field-input'),
                controller: _text,
                autofocus: true,
                keyboardType: spec.multiline
                    ? TextInputType.multiline
                    : spec.keyboard,
                minLines: spec.multiline ? 3 : 1,
                maxLines: spec.multiline ? 8 : 1,
                maxLength: spec.maxLength,
                style: AppTypography.bodyLarge.copyWith(
                  color: palette.textPrimary,
                  fontSize: 16,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: spec.label,
                  hintText: spec.hint,
                  helperText: spec.helper,
                  errorText: _error,
                  errorMaxLines: 3,
                  helperMaxLines: 3,
                  // A one-line field shows no counter (R6); the length is
                  // still capped.
                  counterText: spec.multiline ? null : '',
                  filled: true,
                  fillColor: palette.surface,
                  prefixIcon: spec.multiline ? null : Icon(spec.icon),
                ),
              ),
              const SizedBox(height: 18),
              YoButton(
                key: const ValueKey('page-field-save'),
                label: copy.save,
                height: 52,
                onPressed: _save,
              ),
              if (spec.clearable && spec.initial != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('page-field-clear'),
                  onPressed: () =>
                      Navigator.of(context).pop(const _FieldResult(null)),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: colors.error,
                    textStyle: AppTypography.labelLarge.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  label: Text(spec.clearLabel ?? copy.removeFromPage),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pickers (category, linked server), shared with create A
// ---------------------------------------------------------------------------

/// The server-owned categories of [kind] as a radio list; pops the key.
class PageCategorySheet extends StatelessWidget {
  const PageCategorySheet({
    required this.kind,
    required this.selected,
    super.key,
  });

  final PageKind kind;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final title = kind == PageKind.business
        ? copy.chooseCategory
        : copy.chooseTopic;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YoModalSheetChrome(
              sheetLabel: title,
              surfaceColor: palette.surfaceRaised,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                title,
                style: AppTypography.screenTitle.copyWith(
                  color: palette.textPrimary,
                  fontSize: 21,
                ),
              ),
            ),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (value) => Navigator.of(context).pop(value),
              child: Column(
                children: [
                  for (final key in PageCatalog.categoriesFor(kind))
                    RadioListTile<String>(
                      key: ValueKey('page-category-$key'),
                      value: key,
                      title: Text(
                        copy.categoryLabel(key),
                        style: AppTypography.bodyLarge.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerChoice {
  const _ServerChoice(this.serverId);

  final String? serverId;
}

/// The owner's public Community / Podcast servers (the only ones a Page may
/// link, §2.2) plus "Bez serwera"; pops the choice.
class PageServerSheet extends StatelessWidget {
  const PageServerSheet({
    required this.userId,
    required this.selected,
    this.servers,
    super.key,
  });

  final String userId;
  final String? selected;
  final Stream<List<Server>> Function()? servers;

  /// Servers a Page may link: owned, active, public Community or Podcast.
  static List<Server> eligible(List<Server> servers, String userId) => [
    for (final server in servers)
      if (server.ownerId == userId &&
          server.status == 'active' &&
          server.privacy == ServerPrivacy.public &&
          (server.type == ServerType.community ||
              server.type == ServerType.podcast))
        server,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    final stream = (servers ?? () => ServerService().watchMyServers())();
    return SafeArea(
      top: false,
      child: StreamBuilder<List<Server>>(
        stream: stream,
        builder: (context, snapshot) {
          final options = eligible(snapshot.data ?? const <Server>[], userId);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                YoModalSheetChrome(
                  sheetLabel: copy.linkedServerLabel,
                  surfaceColor: palette.surfaceRaised,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    copy.linkedServerLabel,
                    style: AppTypography.screenTitle.copyWith(
                      color: palette.textPrimary,
                      fontSize: 21,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    copy.linkedServerHelper,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                ListTile(
                  key: const ValueKey('page-server-none'),
                  minTileHeight: 56,
                  leading: const Icon(Icons.link_off_rounded),
                  title: Text(copy.noLinkedServer),
                  trailing: selected == null
                      ? Icon(
                          Icons.check_rounded,
                          color: palette.interactiveForeground,
                        )
                      : null,
                  onTap: () =>
                      Navigator.of(context).pop(const _ServerChoice(null)),
                ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    options.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: YoLoadingIndicator()),
                  )
                else if (options.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      copy.noEligibleServers,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                for (final server in options)
                  ListTile(
                    key: ValueKey('page-server-${server.id}'),
                    minTileHeight: 56,
                    leading: YoServerTile(
                      initial: PageFace.initialFor(server.name),
                      type: server.type,
                      size: 36,
                      bordered: false,
                    ),
                    title: Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected == server.id
                        ? Icon(
                            Icons.check_rounded,
                            color: palette.interactiveForeground,
                          )
                        : null,
                    onTap: () =>
                        Navigator.of(context).pop(_ServerChoice(server.id)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Opens [PageServerSheet]; null when dismissed, else the chosen id (which
/// may itself be null for "Bez serwera").
Future<({String? serverId})?> pickLinkedServer(
  BuildContext context, {
  required String userId,
  required String? selected,
  Stream<List<Server>> Function()? servers,
}) async {
  final choice = await showModalBottomSheet<_ServerChoice>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.appPalette.surfaceRaised,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        PageServerSheet(userId: userId, selected: selected, servers: servers),
  );
  return choice == null ? null : (serverId: choice.serverId);
}

/// Opens [PageCategorySheet]; the picked key or null.
Future<String?> pickPageCategory(
  BuildContext context, {
  required PageKind kind,
  required String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: context.appPalette.surfaceRaised,
  constraints: const BoxConstraints(maxWidth: 560),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) => PageCategorySheet(kind: kind, selected: selected),
);
