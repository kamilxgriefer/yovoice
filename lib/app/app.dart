import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'auth_gate.dart';

class YoVoiceApp extends StatelessWidget {
  const YoVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YO Voice',
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}
