import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:yovoice/features/auth/data/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateChangesProvider = StreamProvider((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final authLoadingProvider = StateProvider<bool>((ref) {
  return false;
});

final authErrorProvider = StateProvider<String?>((ref) {
  return null;
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});

class AuthController {
  AuthController(this.ref);

  final Ref ref;

  AuthService get _service {
    return ref.read(authServiceProvider);
  }

  Future<bool> signIn({required String email, required String password}) async {
    ref.read(authLoadingProvider.notifier).state = true;
    ref.read(authErrorProvider.notifier).state = null;

    try {
      await _service.signIn(email: email, password: password);

      return true;
    } catch (error) {
      ref.read(authErrorProvider.notifier).state = _service.getErrorMessage(
        error,
      );
      return false;
    } finally {
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String username,
  }) async {
    ref.read(authLoadingProvider.notifier).state = true;
    ref.read(authErrorProvider.notifier).state = null;

    try {
      await _service.register(
        email: email,
        password: password,
        username: username,
      );

      return true;
    } catch (error) {
      ref.read(authErrorProvider.notifier).state = _service.getErrorMessage(
        error,
      );
      return false;
    } finally {
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  Future<bool> signInWithGoogle() async {
    ref.read(authLoadingProvider.notifier).state = true;
    ref.read(authErrorProvider.notifier).state = null;

    try {
      await _service.signInWithGoogle();
      return true;
    } catch (error) {
      ref.read(authErrorProvider.notifier).state = _service.getErrorMessage(
        error,
      );
      return false;
    } finally {
      ref.read(authLoadingProvider.notifier).state = false;
    }
  }

  Future<void> signOut() async {
    ref.read(authErrorProvider.notifier).state = null;

    try {
      // Presence and FCM-token cleanup live inside AuthService.signOut(),
      // which every sign-out entry point routes through — doing either one
      // here as well would only re-run it for this single call site.
      await _service.signOut();
    } catch (error) {
      ref.read(authErrorProvider.notifier).state = _service.getErrorMessage(
        error,
      );
    }
  }

  void clearError() {
    ref.read(authErrorProvider.notifier).state = null;
  }
}
