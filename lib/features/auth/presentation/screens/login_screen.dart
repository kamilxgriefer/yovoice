import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/auth_entry_link.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';

/// Public signed-out entry kept stable for AuthGate and route tests.
class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    @visibleForTesting this.authService,
    this.onRegistrationLoadingChanged,
    this.entryLink,
  });

  final AuthService? authService;
  final ValueChanged<bool>? onRegistrationLoadingChanged;

  /// The profile or Voice Moment link this visitor arrived through, if any
  /// (ADR-238).
  final AuthEntryLink? entryLink;

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScreen(
      initialMode: AuthMode.login,
      authService: authService,
      onRegistrationLoadingChanged: onRegistrationLoadingChanged,
      entryLink: entryLink,
    );
  }
}
