import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';

/// Public signed-out entry kept stable for AuthGate and route tests.
class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    @visibleForTesting this.authService,
    this.onRegistrationLoadingChanged,
  });

  final AuthService? authService;
  final ValueChanged<bool>? onRegistrationLoadingChanged;

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScreen(
      initialMode: AuthMode.login,
      authService: authService,
      onRegistrationLoadingChanged: onRegistrationLoadingChanged,
    );
  }
}
