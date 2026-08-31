import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';
import 'package:yovoice/features/auth/presentation/screens/responsive_auth_screen.dart';

/// Route-compatible registration entry for deep links and older callers.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({
    super.key,
    @visibleForTesting this.authService,
    this.onRegistrationLoadingChanged,
  });

  final AuthService? authService;
  final ValueChanged<bool>? onRegistrationLoadingChanged;

  @override
  Widget build(BuildContext context) {
    return ResponsiveAuthScreen(
      initialMode: AuthMode.register,
      authService: authService,
      popAfterSocialSuccess: true,
      popWhenSelectingLogin: true,
      replaceWithVerifyEmail: true,
      onRegistrationLoadingChanged: onRegistrationLoadingChanged,
    );
  }
}
