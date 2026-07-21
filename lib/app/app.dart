import 'package:flutter/material.dart';

import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';

class YoVoiceApp extends StatelessWidget {
  const YoVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YO Voice',
      theme: AppTheme.darkTheme,
      home: const PresenceLifecycle(
        child: AuthGate(),
      ),
    );
  }
}
