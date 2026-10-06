import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_catalog.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_edit_copy.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_form_parts.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_menus.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_pickers.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_profile_parts.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_focus_ink.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/profile_image_pick_flow.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// What "Edytuj stronę" needs from the account behind the Page: a Page has no
/// name, photo or cover of its own, they are the account's (ADR-233). The app
/// uses [ProfilePageEditAccount]; tests pass a fake.
abstract interface class PageEditAccount {
  Stream<UserProfile> watchProfile();

  /// `updateMyDisplayName`: the 30-day cooldown and the Page name rules are
  /// the server's.
  Future<DisplayNameChangeResult> rename(String displayName);

  /// Uploads a picked avatar or banner through the profile media pipeline.
  Future<void> uploadImage(PickedProfileImage image);

  /// Gallery pick and crop; null when the owner backed out.
  Future<PickedProfileImage?> pickImage(
    BuildContext context,
    ProfileImageKind kind,
  );
}

/// [PageEditAccount] over the app's [ProfileService].
class ProfilePageEditAccount implements PageEditAccount {
  ProfilePageEditAccount([ProfileService? service]) : _injected = service;

  final ProfileService? _injected;
  late final ProfileService _service = _injected ?? ProfileService();

  @override
  Stream<UserProfile> watchProfile() => _service.watchCurrentProfile();

  @override
  Future<DisplayNameChangeResult> rename(String displayName) =>
      _service.updateDisplayName(displayName);

  @override
  Future<void> uploadImage(PickedProfileImage image) =>
      _service.uploadProfileImage(image);

  @override
  Future<PickedProfileImage?> pickImage(
    BuildContext context,
    ProfileImageKind kind,
  ) => pickAndCropProfileImage(
    context,
    service: _service,
    kind: kind,
    useRootNavigator: true,
  );
}

/// Opens "Edytuj stronę". On desktop it opens inside Treści's own navigator
/// (the shell keeps its rail; the destination's panel steps aside, see
/// [pageEditRouteName]); on phones and tablets it is pushed over the shell,
/// like create A and the post detail, so the form and its pinned
/// "Zapisz zmiany" own the whole screen and the keyboard.
Future<void> openPageEdit(BuildContext context, {WidgetBuilder? builder}) {
  final route = MaterialPageRoute<void>(
    settings: const RouteSettings(name: pageEditRouteName),
    builder: builder ?? (_) => const PageEditScreen(),
  );
  final scope = PagesNavigatorScope.maybeOf(context);
  if (scope != null && scope.desktop) {
    return Navigator.of(context).push<void>(route);
  }
  return Navigator.of(context, rootNavigator: true).push<void>(route);
}

/// "Edytuj stronę" (pageEdit A, owner decision 2026-10-03; the approved
/// frames `6_pageEdit`): the whole Page profile in ONE form with ONE save.
///
/// * The cover and the photo on top, each with a camera control; WYGLĄD (the
///   name, with the 30-day and "7 days out of search" rule); INFORMACJE (the
///   locked type, D16; category; description); then KONTAKT (business: six
///   optional public fields) or SPOŁECZNOŚĆ (rules, linked server).
/// * "Zapisz zmiany" runs, in order, the name (`updateMyDisplayName`), the
///   pictures (the profile media upload) and one `managePageV1 update` with
///   the whole profile, each only when it changed. A later step that fails
///   says what was already saved.
/// * A clean form follows the server (so it shows the normalized values after
///   a save); a form with unsaved edits keeps what was typed.
/// * While the owner cannot edit (Premium / VIP lapsed, or the Page is
///   suspended) the form is read-only, and a business Page keeps one action:
///   "Wyczyść dane kontaktowe" (`managePageV1 clearContact`, ADR-241).
///
/// Widths (by the space the screen is given, not by device):
/// * **< 600**: one column; the cover runs edge to edge (132), the photo 84
///   overlaps it by 28. App bar "Edytuj stronę" with the text action
///   "Zapisz"; once something changed, a pinned bar with "Masz niezapisane
///   zmiany" and the gradient "Zapisz zmiany".
/// * **600-999**: one 640 column under a collapsible "Podgląd" card (the
///   profile header as visitors see it).
/// * **≥ 1000**: the create screen's 1040 frame: the form (560) on the left
///   and, standing still on the right (360), the Page as a Content-wall row
///   and its profile header, both live.
///
/// Inside the desktop shell's content slot it draws no app bar: a pinned
/// header row carries Back, the title, the unsaved note, "Anuluj" and "Zapisz
/// zmiany". Pushed as a route it has a real app bar with Back.
class PageEditScreen extends StatefulWidget {
  const PageEditScreen({
    this.service,
    this.account,
    this.accessStream,
    this.serverStream,
    this.mediaService,
    this.userId,
    this.clock,
    this.initialPreviewExpanded = true,
    super.key,
  });

  /// Test seams; the app uses the shared instances.
  final PagesService? service;
  final PageEditAccount? account;
  final Stream<PageAccessState> Function()? accessStream;
  final Stream<List<Server>> Function()? serverStream;
  final ProfileMediaService? mediaService;
  final String? userId;
  final DateTime Function()? clock;

  /// Whether the tablet "Podgląd" card starts open.
  final bool initialPreviewExpanded;

  static const double phoneCover = 132;
  static const double wideCover = 160;
  static const double face = 84;
  static const double faceOverlap = 28;
  static const double faceRing = 3;

  /// From here one centred [columnWidth] column with the preview card.
  static const double tabletBreakpoint = 600;
  static const double columnWidth = 640;

  /// From here the form and the standing preview side by side.
  static const double splitBreakpoint = 1000;
  static const double splitFrame = 1040;
  static const double formWidth = 560;
  static const double previewWidth = 360;

  /// The display name's length the server accepts, in code points.
  static const int nameMin = 2;
  static const int nameMax = 120;

  @override
  State<PageEditScreen> createState() => _PageEditScreenState();
}

enum _Layout { phone, tablet, split }

/// What the form held when it was last in step with the server.
class _Baseline {
  const _Baseline({
    required this.name,
    required this.category,
    required this.description,
    required this.business,
    required this.rules,
    required this.linkedServerId,
  });

  final String name;
  final String category;
  final String description;
  final PageBusinessInfo business;
  final String? rules;
  final String? linkedServerId;

  _Baseline copyWith({String? name, PageBusinessInfo? business}) => _Baseline(
    name: name ?? this.name,
    category: category,
    description: description,
    business: business ?? this.business,
    rules: rules,
    linkedServerId: linkedServerId,
  );
}

/// A step of the save that stopped it, in words.
class _SaveStop implements Exception {
  const _SaveStop(this.message);

  final String message;
}

class _PageEditScreenState extends State<PageEditScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final PageEditAccount _account =
      widget.account ?? ProfilePageEditAccount();
  late final String _userId = widget.userId ?? _currentUserId();

  StreamSubscription<PageAccessState>? _accessSub;
  StreamSubscription<UserProfile>? _profileSub;
  StreamSubscription<List<Server>>? _serversSub;
  PageAccessState? _access;
  UserProfile? _profile;
  bool _loadFailed = false;
  Map<String, String> _serverNames = const <String, String>{};

  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _hours = TextEditingController();
  final TextEditingController _legal = TextEditingController();
  final TextEditingController _rules = TextEditingController();
  final FocusNode _nameFocus = FocusNode(debugLabel: 'page-edit-name');
  final FocusNode _descriptionFocus = FocusNode(
    debugLabel: 'page-edit-description',
  );
  final FocusNode _websiteFocus = FocusNode(debugLabel: 'page-edit-website');
  final FocusNode _emailFocus = FocusNode(debugLabel: 'page-edit-email');
  final FocusNode _phoneFocus = FocusNode(debugLabel: 'page-edit-phone');

  List<TextEditingController> get _controllers => [
    _name,
    _description,
    _website,
    _email,
    _phone,
    _address,
    _hours,
    _legal,
    _rules,
  ];

  _Baseline? _base;
  PageKind? _kind;
  String _category = '';
  String? _linkedServerId;
  DateTime? _nextNameChangeAt;
  Timer? _nameCooldownTimer;

  /// Chosen but not uploaded: pictures commit on save with the fields, so
  /// backing out leaves the stored profile untouched.
  PickedProfileImage? _pendingAvatar;
  PickedProfileImage? _pendingBanner;
  ProfileImageKind? _picking;

  /// The server has the new name but the sign-in account's copy is still
  /// catching up: the next save retries the rename even if nothing changed.
  bool _nameSyncPending = false;

  bool _showErrors = false;
  bool _saving = false;
  bool _clearing = false;
  ({String title, String body})? _failure;
  late bool _previewExpanded = widget.initialPreviewExpanded;

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  PagesCopy get _copy => PagesCopy(AppLocalizations.of(context));

  DateTime get _now => (widget.clock ?? DateTime.now)();

  OwnPage? get _page => _access?.ownPage;

  /// The owner cannot `update` (the server would refuse): the Page is
  /// suspended, or neither Premium nor a VIP grant is active.
  bool get _locked {
    final access = _access;
    final page = _page;
    if (access == null || page == null) return true;
    return page.suspended || !access.canRunPage;
  }

  bool get _nameCoolingDown {
    final next = _nextNameChangeAt;
    return next != null && _now.isBefore(next);
  }

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_onEdit);
    }
    try {
      _accessSub = (widget.accessStream ?? PageAccessService.instance.watch)()
          .listen(
            (state) {
              if (!mounted) return;
              _access = state;
              _syncFromServer();
              setState(() {});
            },
            onError: (Object _, StackTrace _) {
              if (mounted) setState(() => _loadFailed = true);
            },
          );
      _profileSub = _account.watchProfile().listen(
        (profile) {
          if (!mounted) return;
          _profile = profile;
          _syncFromServer();
          setState(() {});
        },
        onError: (Object _, StackTrace _) {
          if (mounted) setState(() => _loadFailed = true);
        },
      );
    } catch (_) {
      _loadFailed = true;
    }
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_accessSub?.cancel());
    unawaited(_profileSub?.cancel());
    unawaited(_serversSub?.cancel());
    _nameCooldownTimer?.cancel();
    for (final node in [
      _nameFocus,
      _descriptionFocus,
      _websiteFocus,
      _emailFocus,
      _phoneFocus,
    ]) {
      node.dispose();
    }
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- the form

  /// A clean form follows the server; a form with unsaved edits (or a save
  /// in flight) keeps what the owner typed and only tracks the name
  /// cooldown.
  void _syncFromServer() {
    final page = _page;
    final profile = _profile;
    if (page == null || page.kind == null || profile == null) return;
    _nextNameChangeAt = profile.nextDisplayNameChangeAt;
    _scheduleNameCooldownRefresh();
    if (_base != null && (_dirty || _saving)) return;
    _seed(page, profile);
  }

  void _seed(OwnPage page, UserProfile profile) {
    final business = page.business ?? PageBusinessInfo.empty;
    void put(TextEditingController controller, String value) {
      if (controller.text != value) controller.text = value;
    }

    _kind = page.kind;
    _category = page.category;
    _linkedServerId = page.linkedServerId;
    _base = _Baseline(
      name: profile.displayName,
      category: page.category,
      description: page.description,
      business: business,
      rules: page.rules,
      linkedServerId: page.linkedServerId,
    );
    put(_name, profile.displayName.trim());
    put(_description, page.description);
    put(_website, business.website ?? '');
    put(_email, business.email ?? '');
    put(_phone, business.phone ?? '');
    put(_address, business.address ?? '');
    put(_hours, business.hours ?? '');
    put(_legal, business.legalNotice ?? '');
    put(_rules, page.rules ?? '');
    if (page.kind == PageKind.community) _watchServerNames();
  }

  /// The linked server's name for its field, from the owner's servers.
  void _watchServerNames() {
    if (_serversSub != null) return;
    try {
      final stream =
          (widget.serverStream ?? () => ServerService().watchMyServers())();
      _serversSub = stream.listen((servers) {
        if (!mounted) return;
        setState(() => _serverNames = {for (final s in servers) s.id: s.name});
      }, onError: (Object _, StackTrace _) {});
    } catch (_) {
      // No server list: the field shows its label instead of a name.
    }
  }

  void _scheduleNameCooldownRefresh() {
    _nameCooldownTimer?.cancel();
    final next = _nextNameChangeAt;
    if (next == null || !_now.isBefore(next)) return;
    _nameCooldownTimer = Timer(next.difference(_now), () {
      if (!mounted) return;
      setState(() {});
      // A custom clock may not advance with the timer: re-arm while the
      // boundary is still ahead.
      _scheduleNameCooldownRefresh();
    });
  }

  PageBusinessInfo get _business => PageBusinessInfo(
    website: PageFieldRules.optional(_website.text),
    email: PageFieldRules.optional(_email.text),
    phone: PageFieldRules.optional(_phone.text),
    address: PageFieldRules.optional(_address.text),
    hours: PageFieldRules.optional(_hours.text),
    legalNotice: PageFieldRules.optional(_legal.text),
  );

  bool get _nameDirty {
    final base = _base;
    return base != null && _name.text.trim() != base.name.trim();
  }

  bool get _imagesDirty => _pendingAvatar != null || _pendingBanner != null;

  bool get _pageDirty {
    final base = _base;
    final kind = _kind;
    if (base == null || kind == null) return false;
    if (_category != base.category) return true;
    if (_description.text.trim() != base.description.trim()) return true;
    if (kind == PageKind.business) return _business != base.business;
    return PageFieldRules.optional(_rules.text) != base.rules ||
        _linkedServerId != base.linkedServerId;
  }

  bool get _dirty =>
      !_locked &&
      (_nameDirty || _imagesDirty || _pageDirty || _nameSyncPending);

  // ------------------------------------------------------------ validity

  static int _runeLength(String value) => value.runes.length;

  String? get _nameError {
    if (!_nameDirty) return null;
    final length = _runeLength(_name.text.trim());
    return length < PageEditScreen.nameMin || length > PageEditScreen.nameMax
        ? _copy.editNameLength
        : null;
  }

  String? get _descriptionError =>
      _description.text.trim().length > PageFieldRules.description
      ? _copy.tooLong(PageFieldRules.description)
      : null;
  String? get _websiteError =>
      PageFieldRules.websiteOk(_website.text) ? null : _copy.websiteError;
  String? get _emailError =>
      PageFieldRules.emailOk(_email.text) ? null : _copy.emailError;
  String? get _phoneError =>
      PageFieldRules.phoneOk(_phone.text) ? null : _copy.phoneError;

  /// The first field a save cannot go out with, and what is wrong with it.
  (FocusNode, String)? get _firstError {
    final business = _kind == PageKind.business;
    if (_nameError != null) return (_nameFocus, _nameError!);
    if (_descriptionError != null) {
      return (_descriptionFocus, _descriptionError!);
    }
    if (business && _websiteError != null) {
      return (_websiteFocus, _websiteError!);
    }
    if (business && _emailError != null) return (_emailFocus, _emailError!);
    if (business && _phoneError != null) return (_phoneFocus, _phoneError!);
    return null;
  }

  /// After a refused save: the first invalid field is scrolled into view and
  /// focused, and a screen reader hears what to fix.
  void _revealFirstError((FocusNode, String) first) {
    final (node, message) = first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = node.context;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: .2,
            duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                ? Duration.zero
                : const Duration(milliseconds: 240),
          ),
        );
        node.requestFocus();
      }
      announcePages(context, message, assertive: true);
    });
  }

  // ------------------------------------------------------------- actions

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickCategory() async {
    final kind = _kind;
    if (kind == null || _locked) return;
    final picked = await pickPageCategory(
      context,
      kind: kind,
      selected: _category,
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _pickServer() async {
    if (_locked) return;
    final picked = await pickLinkedServer(
      context,
      userId: _userId,
      selected: _linkedServerId,
      servers: widget.serverStream,
    );
    if (picked == null || !mounted) return;
    setState(() => _linkedServerId = picked.serverId);
  }

  Future<void> _pickImage(ProfileImageKind kind) async {
    if (_locked || _saving || _picking != null) return;
    setState(() => _picking = kind);
    try {
      final picked = await _account.pickImage(context, kind);
      if (!mounted || picked == null) return;
      setState(() {
        if (kind == ProfileImageKind.avatar) {
          _pendingAvatar = picked;
        } else {
          _pendingBanner = picked;
        }
      });
    } catch (_) {
      // The picker refused the file (too large, not a JPG / PNG / WebP) or
      // the editor could not decode it.
      if (mounted) _snack(_copy.imageRefused);
    } finally {
      if (mounted) setState(() => _picking = null);
    }
  }

  /// A date with its year ("24 paź 2026"): the cooldown can run into the
  /// next one.
  String _formatDate(DateTime value) =>
      MaterialLocalizations.of(context).formatShortDate(value.toLocal());

  /// Step 1 of a save. Returns whether the server took a new name.
  Future<bool> _saveName() async {
    final copy = _copy;
    try {
      final result = await _account.rename(_name.text.trim());
      _applySavedName(result.displayName, result.nextDisplayNameChangeAt);
      _nameSyncPending = false;
      return result.changed;
    } on DisplayNameChangeException catch (error) {
      switch (error.failure) {
        case DisplayNameChangeFailure.cooldown:
          // The attempt was refused: put the stored name back before the
          // field locks, so an unsaved name never looks active.
          final base = _base;
          if (base != null) _name.text = base.name.trim();
          _nextNameChangeAt = error.nextDisplayNameChangeAt;
          _nameSyncPending = false;
          _scheduleNameCooldownRefresh();
          final next = error.nextDisplayNameChangeAt;
          throw _SaveStop(
            next == null
                ? copy.nameChangeFailed
                : copy.editNameLockedUntil(_formatDate(next)),
          );
        case DisplayNameChangeFailure.authSyncPending:
          _applySavedName(
            error.canonicalDisplayName,
            error.nextDisplayNameChangeAt,
          );
          _nameSyncPending = true;
          return true;
        case DisplayNameChangeFailure.authAccountMissingAfterSave:
          _applySavedName(
            error.canonicalDisplayName,
            error.nextDisplayNameChangeAt,
          );
          _nameSyncPending = false;
          return true;
        case DisplayNameChangeFailure.nameNotAllowed:
          throw _SaveStop(copy.manageError(PagesFailure.nameReserved));
        case DisplayNameChangeFailure.invalidName:
          throw _SaveStop(copy.editNameLength);
        case DisplayNameChangeFailure.tooManyAttempts:
          throw _SaveStop(copy.manageError(PagesFailure.rateLimited));
        case DisplayNameChangeFailure.emailVerificationRequired:
        case DisplayNameChangeFailure.signedOut:
        case DisplayNameChangeFailure.inactiveAccount:
        case DisplayNameChangeFailure.missingProfile:
        case DisplayNameChangeFailure.unavailable:
          throw _SaveStop(copy.nameChangeFailed);
      }
    }
  }

  void _applySavedName(String? canonical, DateTime? nextChangeAt) {
    final name = canonical != null && canonical.trim().isNotEmpty
        ? canonical
        : _name.text.trim();
    _base = _base?.copyWith(name: name);
    if (_name.text != name) _name.text = name;
    _nextNameChangeAt = nextChangeAt ?? _nextNameChangeAt;
    _scheduleNameCooldownRefresh();
  }

  Future<void> _uploadPending(PickedProfileImage image) async {
    try {
      await _account.uploadImage(image);
    } on ProfileImageException {
      throw _SaveStop(_copy.imageRefused);
    } catch (_) {
      throw _SaveStop(_copy.imageUploadFailed);
    }
  }

  /// "Zapisz zmiany": the name, the pictures, then ONE `managePageV1 update`,
  /// each only when it changed. Leaves the screen once everything is stored.
  Future<void> _save() async {
    final kind = _kind;
    final base = _base;
    if (_saving || kind == null || base == null || !_dirty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final invalid = _firstError;
    if (invalid != null) {
      setState(() {
        _showErrors = true;
        _failure = null;
      });
      _revealFirstError(invalid);
      return;
    }
    final copy = _copy;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var savedSomething = false;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      if (_nameDirty || _nameSyncPending) {
        savedSomething = await _saveName() || savedSomething;
      }
      final avatar = _pendingAvatar;
      if (avatar != null) {
        await _uploadPending(avatar);
        _pendingAvatar = null;
        savedSomething = true;
      }
      final banner = _pendingBanner;
      if (banner != null) {
        await _uploadPending(banner);
        _pendingBanner = null;
        savedSomething = true;
      }
      if (_pageDirty) {
        final business = kind == PageKind.business ? _business : null;
        final rules = kind == PageKind.community
            ? PageFieldRules.optional(_rules.text)
            : null;
        final linked = kind == PageKind.community ? _linkedServerId : null;
        final description = _description.text.trim();
        await _service.updatePage(
          kind: kind,
          category: _category,
          description: description,
          business: business,
          rules: rules,
          linkedServerId: linked,
        );
        _base = _Baseline(
          name: _base!.name,
          category: _category,
          description: description,
          business: business ?? PageBusinessInfo.empty,
          rules: rules,
          linkedServerId: linked,
        );
        savedSomething = true;
      }
      if (!mounted) return;
      if (_nameSyncPending) {
        // Everything is stored; only the account's own copy of the name is
        // catching up. The form stays open so one more Save finishes it.
        setState(
          () => _failure = (title: copy.savedPartly, body: copy.nameSavedRetry),
        );
        announcePages(context, copy.nameSavedRetry, assertive: true);
        return;
      }
      // Announced only after every stage completed. The messenger was taken
      // before the pop, so the confirmation survives this screen.
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(copy.saved)));
    } on _SaveStop catch (stop) {
      _reportFailure(stop.message, savedSomething: savedSomething);
    } on PagesException catch (error) {
      _reportFailure(
        copy.manageError(error.failure),
        savedSomething: savedSomething,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reportFailure(String reason, {required bool savedSomething}) {
    if (!mounted) return;
    final copy = _copy;
    final title = savedSomething ? copy.savedPartly : copy.saveFailed;
    setState(() => _failure = (title: title, body: reason));
    announcePages(context, '$title. $reason', assertive: true);
    final target = _failureKey.currentContext;
    if (target != null) {
      unawaited(Scrollable.ensureVisible(target, alignment: .1));
    }
  }

  final GlobalKey _failureKey = GlobalKey(debugLabel: 'page-edit-failure');

  /// "Wyczyść dane kontaktowe" (ADR-241): a safety action that works in every
  /// state of the Page and of the account.
  Future<void> _clearContact() async {
    if (_clearing || _saving) return;
    final copy = _copy;
    final confirmed = await confirmPageAction(
      context,
      title: copy.clearContactTitle,
      body: copy.clearContactBody,
      confirm: copy.clearAction,
      cancel: copy.cancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _service.clearPageContact();
      if (!mounted) return;
      for (final controller in [
        _website,
        _email,
        _phone,
        _address,
        _hours,
        _legal,
      ]) {
        controller.clear();
      }
      _base = _base?.copyWith(business: PageBusinessInfo.empty);
      _snack(copy.contactCleared);
    } on PagesException catch (error) {
      if (!mounted) return;
      _snack(
        error.failure == PagesFailure.network
            ? copy.manageError(PagesFailure.network)
            : copy.actionFailed,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  /// Back, system Back and "Anuluj": unsaved edits are only dropped after the
  /// owner says so.
  Future<void> _leave() async {
    if (_saving) return;
    if (!_dirty) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    final copy = _copy;
    final post = PagePostCopy(copy.copy);
    final discard = await confirmPageAction(
      context,
      title: copy.discardChangesTitle,
      body: copy.discardChangesBody,
      confirm: post.discard,
      cancel: post.keepEditing,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final embedded = PagesNavigatorScope.maybeOf(context)?.desktop ?? false;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final layout = width >= PageEditScreen.splitBreakpoint
              ? _Layout.split
              : width >= PageEditScreen.tabletBreakpoint
              ? _Layout.tablet
              : _Layout.phone;
          return embedded
              ? _embedded(context, layout, width)
              : _pushed(context, layout, width);
        },
      ),
    );
  }

  /// Null when the form can be shown; else what stands in for it.
  Widget? _stateView(BuildContext context) {
    final copy = _copy;
    final access = _access;
    if (_loadFailed) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: YoErrorState(message: copy.loadSettingsError),
      );
    }
    if (access != null && access.resolved && access.ownPage?.kind == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: YoErrorState(message: copy.noPageYet),
      );
    }
    if (_base == null || _kind == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: YoLoadingIndicator(semanticLabel: copy.loadingPage),
        ),
      );
    }
    return null;
  }

  // ---- Pushed as a route: a real app bar ------------------------------------

  Widget _pushed(BuildContext context, _Layout layout, double width) {
    final palette = context.appPalette;
    final copy = _copy;
    final state = _stateView(context);
    final dirty = _dirty;
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(
          key: const ValueKey('page-edit-back'),
          onPressed: () => unawaited(_leave()),
        ),
        title: Text(
          copy.editPage,
          style: AppTypography.titleMedium.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (state == null && !_locked)
            // The toolbar does not grow with the text size, and the app bar
            // caps its title at 1.34x: the action keeps the same cap, so a
            // long "Save" at a large text size cannot squeeze the title out
            // ("Edytuj s…"). The pinned "Zapisz zmiany" below scales fully.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.34,
              child: TextButton(
                key: const ValueKey('page-edit-save-action'),
                onPressed: dirty && !_saving ? () => unawaited(_save()) : null,
                style: TextButton.styleFrom(
                  foregroundColor: palette.interactiveForeground,
                  minimumSize: const Size(64, 44),
                  textStyle: AppTypography.labelLarge.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(copy.save),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      // Scaffold pins this slot to the bottom of the window, behind the
      // keyboard (UI.md "Placement invariant", ADR-169): the wrapper lifts
      // Done and "Zapisz zmiany" onto the keyboard.
      bottomNavigationBar: YoKeyboardSafeBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const YoKeyboardDoneBar(),
            if (state == null && dirty)
              PageBottomActionBar(
                key: const ValueKey('page-edit-save-bar'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // With the keyboard up the form needs the room more
                    // than the note does; the button says enough.
                    if (!keyboardUp) ...[
                      _UnsavedNote(text: copy.unsavedChanges),
                      const SizedBox(height: 10),
                    ],
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: PageEditScreen.columnWidth,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: _saveButton(const Size(64, 52)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: state ?? _formBody(context, layout, width),
    );
  }

  // ---- Inside the desktop shell's slot: no app bar ---------------------------

  Widget _embedded(BuildContext context, _Layout layout, double width) {
    final palette = context.appPalette;
    final state = _stateView(context);
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final gutter = _gutter(width, layout);
    return Scaffold(
      backgroundColor: palette.background,
      // Done is the way out of a multi-line field on a touch screen wide
      // enough for the desktop shell; it renders nothing with a hardware
      // keyboard, and is attached only while the software keyboard is up.
      bottomNavigationBar: keyboardUp
          ? const YoKeyboardSafeBottomBar(child: YoKeyboardDoneBar())
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: layout == _Layout.split
                        ? PageEditScreen.splitFrame
                        : PageEditScreen.columnWidth,
                  ),
                  child: _EmbeddedHeader(
                    title: _copy.editPage,
                    backTooltip: _copy.goBack,
                    onBack: () => unawaited(_leave()),
                    unsaved: state == null && _dirty
                        ? _UnsavedNote(text: _copy.unsavedChanges)
                        : null,
                    actions: state == null && !_locked
                        ? [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 120),
                              child: PageTonalButton(
                                key: const ValueKey('page-edit-cancel'),
                                label: _copy.cancel,
                                height: 44,
                                onPressed: _saving
                                    ? null
                                    : () => unawaited(_leave()),
                              ),
                            ),
                            _saveButton(const Size(168, 44)),
                          ]
                        : const <Widget>[],
                  ),
                ),
              ),
            ),
            Expanded(
              child: state == null
                  ? _formBody(context, layout, width, topPadding: 24)
                  : SingleChildScrollView(child: state),
            ),
          ],
        ),
      ),
    );
  }

  /// The label takes a second line rather than being cut: at a large text
  /// size a long translation ("Änderungen speichern", "Enregistrer les
  /// modifications") is wider than the phone's pinned button.
  Widget _saveButton(Size minimumSize) => YoGradientFilledButton(
    key: const ValueKey('page-edit-save'),
    onPressed: _dirty ? () => unawaited(_save()) : null,
    busy: _saving,
    minimumSize: minimumSize,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Text(
      _copy.saveChanges,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    ),
  );

  /// The centred frame's side margin at [width].
  static double _gutter(double width, _Layout layout) => switch (layout) {
    _Layout.split => math.max(24, (width - PageEditScreen.splitFrame) / 2),
    _Layout.tablet => math.max(24, (width - PageEditScreen.columnWidth) / 2),
    _Layout.phone => 16,
  };

  // ---- The body at the three widths ------------------------------------------

  /// The form, inert while a save is in flight: a successful save closes
  /// the screen, so anything changed meanwhile would be dropped unsaved.
  Widget _formBody(
    BuildContext context,
    _Layout layout,
    double width, {
    double topPadding = 8,
  }) => AbsorbPointer(
    absorbing: _saving,
    child: _formLayout(context, layout, width, topPadding: topPadding),
  );

  Widget _formLayout(
    BuildContext context,
    _Layout layout,
    double width, {
    required double topPadding,
  }) {
    switch (layout) {
      case _Layout.phone:
        return ListView(
          key: const ValueKey('page-edit-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.zero,
          children: [
            _photos(context, cover: PageEditScreen.phoneCover, rounded: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _fields(context),
              ),
            ),
          ],
        );
      case _Layout.tablet:
        final gutter = _gutter(width, layout);
        return ListView(
          key: const ValueKey('page-edit-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(gutter, topPadding, gutter, 40),
          children: [
            _PreviewCard(
              expanded: _previewExpanded,
              onToggle: () =>
                  setState(() => _previewExpanded = !_previewExpanded),
              child: _profilePreview(),
            ),
            const SizedBox(height: 24),
            _photos(context, cover: PageEditScreen.wideCover, rounded: true),
            const SizedBox(height: 20),
            ..._fields(context),
          ],
        );
      case _Layout.split:
        final gutter = _gutter(width, layout);
        final form = Column(
          key: const ValueKey('page-edit-form-column'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _photos(context, cover: PageEditScreen.wideCover, rounded: true),
            const SizedBox(height: 20),
            ..._fields(context),
          ],
        );
        final columns = <Widget>[
          SliverConstrainedCrossAxis(
            maxExtent: PageEditScreen.formWidth,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: form,
              ),
            ),
          ),
          const SliverCrossAxisExpanded(
            flex: 1,
            sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          SliverConstrainedCrossAxis(
            maxExtent: PageEditScreen.previewWidth,
            sliver: PageStickySliver(
              child: Padding(
                key: const ValueKey('page-edit-preview-column'),
                padding: EdgeInsets.only(top: topPadding),
                child: _previewColumn(context),
              ),
            ),
          ),
        ];
        // A cross-axis group places its slivers left to right whatever the
        // text direction: right to left, the form still starts the row
        // (under the title) and the preview ends it (under the actions).
        final rtl = Directionality.of(context) == TextDirection.rtl;
        // One scroll view scrolls the whole page, so the wheel works
        // anywhere; the preview column stands still beside the form.
        return CustomScrollView(
          key: const ValueKey('page-edit-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 40),
              sliver: SliverCrossAxisGroup(
                slivers: rtl ? columns.reversed.toList() : columns,
              ),
            ),
          ],
        );
    }
  }

  // ---- Previews --------------------------------------------------------------

  String get _previewName {
    final typed = _name.text.trim();
    return typed.isEmpty ? _copy.yourPage : typed;
  }

  ImageProvider<Object>? get _pendingCover {
    final banner = _pendingBanner;
    return banner == null ? null : MemoryImage(banner.bytes);
  }

  ImageProvider<Object>? get _pendingFace {
    final avatar = _pendingAvatar;
    return avatar == null ? null : MemoryImage(avatar.bytes);
  }

  Widget _profilePreview() => PageProfilePreviewHeader(
    frameKey: const ValueKey('page-edit-preview-header'),
    pageId: _userId,
    name: _previewName,
    kind: _kind!,
    followerCount: _profile?.accountFollowerCount ?? 0,
    description: _description.text.trim(),
    coverImage: _pendingCover,
    faceImage: _pendingFace,
    mediaService: widget.mediaService,
    mediaRevision: _profile?.profileUpdatedAt,
  );

  /// The standing column of the split layout: the Page as it appears on the
  /// Content wall and its profile header. Pictures of the result, so the
  /// column is inert and hidden from screen readers (the form says
  /// everything it shows).
  Widget _previewColumn(BuildContext context) {
    final copy = _copy;
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageFormOverline(copy.previewOnWall),
          PageWallPreviewRow(
            cardKey: const ValueKey('page-edit-preview-wall'),
            pageId: _userId,
            name: _previewName,
            kind: _kind!,
            category: _category,
            followerCount: _profile?.accountFollowerCount ?? 0,
            faceImage: _pendingFace,
            mediaService: widget.mediaService,
            mediaRevision: _profile?.profileUpdatedAt,
          ),
          const SizedBox(height: 24),
          PageFormOverline(copy.previewProfile),
          _profilePreview(),
          PageFootnote(
            copy.editPreviewNote,
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            scaleIcon: true,
          ),
        ],
      ),
    );
  }

  // ---- Cover and photo -------------------------------------------------------

  Widget _photos(
    BuildContext context, {
    required double cover,
    required bool rounded,
  }) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = _copy;
    const face = PageEditScreen.face;
    const overlap = PageEditScreen.faceOverlap;
    const ring = PageEditScreen.faceRing;
    final editable = !_locked && !_saving;
    Widget coverBox = PageCover(
      pageId: _userId,
      scrim: false,
      localImage: _pendingCover,
      mediaService: widget.mediaService,
      mediaRevision: _profile?.profileUpdatedAt,
    );
    if (rounded) {
      coverBox = ClipRRect(borderRadius: AppRadius.block, child: coverBox);
    }
    final faceWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        PageFace(
          pageId: _userId,
          name: _previewName,
          kind: _kind,
          size: face,
          ring: ring,
          ringColor: palette.background,
          localImage: _pendingFace,
          mediaService: widget.mediaService,
          mediaRevision: _profile?.profileUpdatedAt,
        ),
        if (!_locked)
          PositionedDirectional(
            end: -2,
            bottom: -2,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: palette.background, width: 2),
              ),
              child: Icon(
                Icons.photo_camera_outlined,
                size: 14,
                color: colors.onPrimary,
              ),
            ),
          ),
      ],
    );
    return SizedBox(
      key: const ValueKey('page-edit-photos'),
      height: cover + face - overlap + ring,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: cover,
            // The whole cover takes the tap; the glass camera is the
            // control a keyboard and a screen reader reach.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: editable
                  ? () => unawaited(_pickImage(ProfileImageKind.banner))
                  : null,
              child: coverBox,
            ),
          ),
          if (!_locked)
            PositionedDirectional(
              end: 12,
              top: cover - 44 - 10,
              child: PageGlassButton(
                key: const ValueKey('page-edit-cover'),
                icon: Icons.photo_camera_outlined,
                tooltip: copy.changeCover,
                onPressed: () {
                  if (editable) unawaited(_pickImage(ProfileImageKind.banner));
                },
              ),
            ),
          PositionedDirectional(
            start: 16 - ring,
            top: cover - overlap - ring,
            child: _locked
                ? faceWidget
                : Tooltip(
                    message: copy.changePhoto,
                    excludeFromSemantics: true,
                    child: Semantics(
                      button: true,
                      label: copy.changePhoto,
                      excludeSemantics: true,
                      onTap: editable
                          ? () => unawaited(_pickImage(ProfileImageKind.avatar))
                          : null,
                      child: PagesFocusInk(
                        key: const ValueKey('page-edit-photo'),
                        excludeFromSemantics: true,
                        borderRadius: BorderRadius.circular(
                          PageFace.cornerRadius + ring,
                        ),
                        onTap: editable
                            ? () =>
                                  unawaited(_pickImage(ProfileImageKind.avatar))
                            : null,
                        child: faceWidget,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---- Fields ----------------------------------------------------------------

  List<Widget> _fields(BuildContext context) {
    final copy = _copy;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final kind = _kind!;
    final page = _page;
    final locked = _locked;
    final show = _showErrors;
    final failure = _failure;
    final business = kind == PageKind.business;
    final nameLocked = _nameCoolingDown;
    final storedContact = page?.business;
    final hasStoredContact = storedContact != null && !storedContact.isEmpty;

    return [
      if (failure != null) ...[
        _FailureBanner(
          key: _failureKey,
          title: failure.title,
          body: failure.body,
        ),
        const SizedBox(height: 20),
      ],
      if (locked) ...[
        PageNotice(
          key: const ValueKey('page-edit-locked'),
          tone: page?.suspended ?? false ? PageTone.danger : PageTone.warning,
          icon: page?.suspended ?? false
              ? Icons.gavel_rounded
              : Icons.lock_outline_rounded,
          title: copy.editLockedTitle,
          body: page?.suspended ?? false
              ? copy.editLockedSuspended
              : copy.editLockedLapsed,
        ),
        const SizedBox(height: 20),
      ],
      PageFormOverline(copy.editAppearance),
      PageFootnote(
        copy.editSharedIdentity,
        icon: Icons.person_outline_rounded,
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 18),
        scaleIcon: true,
      ),
      PageFormTextField(
        fieldKey: const ValueKey('page-edit-name'),
        focusNode: _nameFocus,
        label: copy.editName,
        controller: _name,
        limit: PageEditScreen.nameMax,
        enabled: !locked,
        readOnly: nameLocked,
        helperText: nameLocked
            ? copy.editNameLockedUntil(_formatDate(_nextNameChangeAt!))
            : copy.editNameHelper,
        error: show ? _nameError : null,
        suffixIcon: nameLocked
            ? Icon(Icons.lock_clock_rounded, color: palette.textTertiary)
            : null,
      ),
      const SizedBox(height: 8),
      PageFormOverline(copy.aboutTitle),
      PageFormPickerField(
        fieldKey: const ValueKey('page-edit-type'),
        label: copy.pageType,
        value: copy.kindLabel(kind),
        onTap: null,
        locked: true,
        lockedLabel: copy.pageTypeLocked,
        helperText: copy.editTypeLocked,
      ),
      PageFormPickerField(
        fieldKey: const ValueKey('page-edit-category'),
        label: copy.categoryField(kind),
        value: _category.isEmpty ? null : copy.categoryLabel(_category),
        onTap: locked ? null : () => unawaited(_pickCategory()),
        helper: const PagePublicHelper(),
      ),
      PageFormTextField(
        fieldKey: const ValueKey('page-edit-description'),
        focusNode: _descriptionFocus,
        label: copy.descriptionLabel,
        controller: _description,
        maxLines: 5,
        maxLength: PageFieldRules.description,
        enabled: !locked,
        error: show ? _descriptionError : null,
      ),
      const SizedBox(height: 8),
      if (business) ...[
        PageFormOverline(
          copy.contactOverline,
          trailing: Text(
            copy.allOptional,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-website'),
          focusNode: _websiteFocus,
          label: copy.websiteLabel,
          controller: _website,
          publicExtra: copy.httpsOnly,
          keyboard: TextInputType.url,
          maxLength: PageFieldRules.website,
          enabled: !locked,
          error: locked || _website.text.isEmpty ? null : _websiteError,
        ),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-email'),
          focusNode: _emailFocus,
          label: copy.contactEmailLabel,
          controller: _email,
          keyboard: TextInputType.emailAddress,
          maxLength: PageFieldRules.email,
          enabled: !locked,
          error: locked || _email.text.isEmpty ? null : _emailError,
        ),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-phone'),
          focusNode: _phoneFocus,
          label: copy.phoneLabel,
          controller: _phone,
          keyboard: TextInputType.phone,
          maxLength: 32,
          enabled: !locked,
          error: locked || _phone.text.isEmpty || !show ? null : _phoneError,
        ),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-address'),
          label: copy.addressOrAreaLabel,
          controller: _address,
          maxLength: PageFieldRules.address,
          enabled: !locked,
        ),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-hours'),
          label: copy.hoursLabel,
          controller: _hours,
          maxLength: PageFieldRules.hours,
          enabled: !locked,
        ),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-legal'),
          label: copy.legalNoticeFieldLabel,
          controller: _legal,
          hint: locked ? null : copy.legalNoticeHint,
          maxLines: 3,
          maxLength: PageFieldRules.legalNotice,
          enabled: !locked,
        ),
        // The promise the create consent makes ("you can clear them any
        // time"), next to the action that keeps it in every state.
        PageFootnote(
          copy.retention,
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
          scaleIcon: true,
        ),
        if (hasStoredContact) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('page-edit-clear-contact'),
              onPressed: _clearing || _saving
                  ? null
                  : () => unawaited(_clearContact()),
              style: TextButton.styleFrom(
                foregroundColor: colors.error,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                textStyle: AppTypography.labelLarge.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // The label wraps instead of running off a narrow screen at a
              // large text size.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.backspace_outlined, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(copy.clearContact)),
                ],
              ),
            ),
          ),
        ],
      ] else ...[
        PageFormOverline(copy.kindLabel(PageKind.community)),
        PageFormTextField(
          fieldKey: const ValueKey('page-edit-rules'),
          label: copy.rulesTitle,
          controller: _rules,
          hint: locked ? null : copy.editRulesHint,
          maxLines: 4,
          maxLength: PageFieldRules.rules,
          enabled: !locked,
        ),
        PageFormPickerField(
          fieldKey: const ValueKey('page-edit-linked-server'),
          label: copy.linkedServerLabel,
          value: _linkedServerId == null
              ? copy.noLinkedServer
              : _serverNames[_linkedServerId] ?? copy.linkedServerLabel,
          onTap: locked ? null : () => unawaited(_pickServer()),
          helper: PagePublicHelper(extra: copy.linkedServerHelper),
        ),
      ],
    ];
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// "● Masz niezapisane zmiany": a live region, so a screen reader hears it
/// when the first change makes it appear.
class _UnsavedNote extends StatelessWidget {
  const _UnsavedNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      key: const ValueKey('page-edit-unsaved'),
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: palette.warningForeground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: palette.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The header row of the screen inside the desktop shell's slot (the shell
/// owns navigation, so there is no app bar): Back, the title and, at the
/// end, the unsaved note with "Anuluj" and "Zapisz zmiany". It stays put
/// while the form scrolls. When the row has no room for everything on one
/// line (a narrow slot, large text) the actions drop to a second line.
class _EmbeddedHeader extends StatelessWidget {
  const _EmbeddedHeader({
    required this.title,
    required this.backTooltip,
    required this.onBack,
    required this.unsaved,
    required this.actions,
  });

  final String title;
  final String backTooltip;
  final VoidCallback onBack;
  final Widget? unsaved;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final back = IconButton(
      key: const ValueKey('page-edit-back'),
      onPressed: onBack,
      tooltip: backTooltip,
      icon: Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 18,
        color: palette.textPrimary,
      ),
    );
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.screenTitle.copyWith(color: palette.textPrimary),
      ),
    );
    final trailing = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        if (unsaved != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: unsaved,
          ),
        ...actions,
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final stacked = constraints.maxWidth < 760 || scale > 1.3;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  back,
                  const SizedBox(width: 6),
                  Expanded(child: heading),
                ],
              ),
              if (unsaved != null || actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trailing,
                ),
              ],
            ],
          );
        }
        return Row(
          children: [
            back,
            const SizedBox(width: 6),
            Expanded(child: heading),
            const SizedBox(width: 16),
            trailing,
          ],
        );
      },
    );
  }
}

/// The collapsible "Podgląd" card of the one-column tablet layout: the
/// profile header as visitors see it, above the form.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = PagesCopy(AppLocalizations.of(context));
    return YoCard(
      key: const ValueKey('page-edit-preview-card'),
      semanticButton: false,
      padding: EdgeInsetsDirectional.fromSTEB(16, 6, 8, expanded ? 16 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 20,
                color: palette.interactiveForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    copy.previewOverline,
                    style: AppTypography.sectionTitle.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('page-edit-preview-toggle'),
                onPressed: onToggle,
                tooltip: expanded ? copy.hidePreview : copy.showPreview,
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          if (expanded)
            Center(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: PageProfilePreviewHeader.layoutWidth,
                  ),
                  child: child,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Why a save stopped: what happened and what to do, as a live region above
/// the form.
class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.dangerSurface,
        borderRadius: AppRadius.md,
        border: Border.all(
          color: palette.dangerForeground.withValues(alpha: .35),
        ),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: palette.dangerForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textPrimary.withValues(alpha: .86),
                      fontSize: 13,
                      height: 1.45,
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
