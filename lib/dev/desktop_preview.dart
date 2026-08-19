// Developer-only harness for the DESKTOP shell surfaces.
//
// Renders the real DesktopSidebar and the Home right-column cards at an
// arbitrary window width without a signed-in Firebase session — the same
// reason profile_preview.dart exists: nothing in the repo could show a
// desktop-width surface without logging in, and the first desktop layout
// bug shipped unseen because of exactly that.
//
// Run with:
//   flutter run -d web-server -t lib/dev/desktop_preview.dart
//
// Not referenced by lib/main.dart; never part of a shipped build.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same rationale as the other preview harnesses: plugins register
  // unconditionally on web, but this preview never signs in — the desktop
  // widgets degrade to their empty states without a session.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
  } catch (error) {
    debugPrint('Preview: continuing without Firebase ($error)');
  }
  runApp(const _DesktopPreviewApp());
}

class _DesktopPreviewApp extends StatelessWidget {
  const _DesktopPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const _DesktopPreviewHome(),
    );
  }
}

class _DesktopPreviewHome extends StatefulWidget {
  const _DesktopPreviewHome();

  @override
  State<_DesktopPreviewHome> createState() => _DesktopPreviewHomeState();
}

class _DesktopPreviewHomeState extends State<_DesktopPreviewHome> {
  DesktopNavItem _active = DesktopNavItem.home;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      body: Row(
        children: [
          DesktopSidebar(
            active: _active,
            unreadConversationCount: 3,
            unreadNotificationCount: 6,
            onSelect: (item) => setState(() => _active = item),
            onCreateRoom: () {},
            onCreateMoment: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
          const Expanded(child: _CenterPlaceholder()),
          SizedBox(
            width: 344,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 20, 20, 20),
              children: [
                VoiceTrendingCard(
                  onOpenRoom: (_) {},
                  onSeeAll: () {},
                  onSeeAllRooms: () {},
                ),
                const SizedBox(height: 16),
                PremiumDesktopCard(onCheckPlans: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stands in for the real Home content, which this harness deliberately
/// does not render (it needs a signed-in session).
class _CenterPlaceholder extends StatelessWidget {
  const _CenterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Home content (real HomeScreen in the app)',
        style: TextStyle(color: AppColors.textHint, fontSize: 13),
      ),
    );
  }
}
