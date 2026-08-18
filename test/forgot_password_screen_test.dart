import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:yovoice/services/firestore_service.dart';

AuthService _service() => AuthService(
  firebaseAuth: MockFirebaseAuth(),
  firestoreService: FirestoreService(firestore: FakeFirebaseFirestore()),
);

void main() {
  testWidgets(
    'valid address sends reset instructions and shows neutral result',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(authService: _service())),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('forgot-password-email')),
        'person@example.com',
      );
      await tester.tap(find.byKey(const Key('send-reset-link')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Check your inbox'), findsOneWidget);
      expect(
        find.textContaining('If an account exists for person@example.com'),
        findsOneWidget,
      );
      expect(find.text('Back to log in'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('blank address is validated on the dedicated page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(authService: _service())),
    );
    await tester.tap(find.byKey(const Key('send-reset-link')));
    await tester.pump();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Check your inbox'), findsNothing);
  });

  for (final width in <double>[320, 390, 768, 1100, 1440]) {
    testWidgets('reset form fits ${width.toInt()}px at 200% text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1100),
            textScaler: const TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: ForgotPasswordScreen(authService: _service()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Reset password'), findsOneWidget);
      expect(find.byKey(const Key('forgot-password-email')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
