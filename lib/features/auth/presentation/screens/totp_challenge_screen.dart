import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/theme/yo_immersive_dark_surface.dart';

class TotpChallengeScreen extends StatefulWidget {
  const TotpChallengeScreen({required this.challenge, super.key});

  final TotpSignInChallengeClient challenge;

  @override
  State<TotpChallengeScreen> createState() => _TotpChallengeScreenState();
}

class _TotpChallengeScreenState extends State<TotpChallengeScreen> {
  final _codeController = TextEditingController();
  String? _selectedFactorUid;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.challenge.factors.isNotEmpty) {
      _selectedFactorUid = widget.challenge.factors.first.uid;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _selectedFactorUid == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.challenge.resolve(
        factorUid: _selectedFactorUid!,
        code: _codeController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.code) {
            'invalid-verification-code' || 'invalid-credential' =>
              'That code is not valid. Wait for a new code and try again.',
            'too-many-requests' =>
              'Too many attempts. Wait a moment before trying again.',
            _ => error.message ?? 'Two-factor verification failed.',
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Two-factor verification could not be completed. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final factors = widget.challenge.factors;
    final content = Scaffold(
      backgroundColor: const Color(0xFF080711),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Two-factor verification'),
      ),
      body: SafeArea(
        child: ResponsiveContentFrame(
          width: ResponsiveContentWidth.form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
            children: [
              const Icon(
                Icons.security_rounded,
                color: Color(0xFFB348FF),
                size: 56,
              ),
              const SizedBox(height: 18),
              const Text(
                'Confirm it’s you',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter the current code from the authenticator app connected to your YO Voice account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFAAA1B8), height: 1.45),
              ),
              const SizedBox(height: 28),
              if (factors.isEmpty)
                const _ChallengeError(
                  'No supported authenticator is available for this account. Contact support.',
                )
              else ...[
                if (factors.length > 1)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedFactorUid,
                    dropdownColor: const Color(0xFF17101F),
                    decoration: const InputDecoration(
                      labelText: 'Authenticator',
                    ),
                    items: factors
                        .map(
                          (factor) => DropdownMenuItem(
                            value: factor.uid,
                            child: Text(factor.displayName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _selectedFactorUid = value),
                  ),
                if (factors.length > 1) const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  autofocus: true,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 6,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: '6-digit code',
                    prefixIcon: Icon(Icons.password_rounded),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ChallengeError(_error!),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verify and continue'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return YoImmersiveDarkSurface(child: content);
  }
}

class _ChallengeError extends StatelessWidget {
  const _ChallengeError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF5C1B33),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
