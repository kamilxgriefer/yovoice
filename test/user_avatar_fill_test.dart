import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

void main() {
  testWidgets('network image fills tight circular avatar constraints', (
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
    final imageRect = tester.getRect(find.byType(Image));
    expect(avatarRect.size, const Size.square(57));
    expect(imageRect, avatarRect);

    final clip = tester.widget<ClipOval>(find.byType(ClipOval));
    expect(clip.clipBehavior, Clip.antiAlias);
    expect(tester.takeException(), isNull);
  });
}
