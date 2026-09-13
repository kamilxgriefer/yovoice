import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/shared/widgets/profile/premium_avatar_frame.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

void main() {
  testWidgets('legacy external image is not fetched without a canonical uid', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 57,
            child: UserAvatar(
              key: ValueKey('avatar-under-test'),
              radius: 25,
              photoUrl: 'https://example.invalid/avatar.png',
              displayName: 'Avatar Test',
            ),
          ),
        ),
      ),
    );

    final avatarRect = tester.getRect(
      find.byKey(const ValueKey('avatar-under-test')),
    );
    expect(avatarRect.size, const Size.square(57));
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);

    final clip = tester.widget<ClipOval>(find.byType(ClipOval));
    expect(clip.clipBehavior, Clip.antiAlias);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Premium uses the canonical shimmer frame and reduced motion settles statically',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Center(
              child: UserAvatar(
                radius: 25,
                displayName: 'Premium Member',
                premium: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PremiumAvatarFrame), findsOneWidget);
      expect(find.byKey(premiumAvatarRingKey), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: UserAvatar(radius: 25, displayName: 'Free Member'),
          ),
        ),
      );
      expect(find.byType(PremiumAvatarFrame), findsNothing);
    },
  );
}
