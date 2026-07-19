import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class YoLogo extends StatelessWidget {
  const YoLogo({super.key, this.width = 260});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/yo_voice_logo_full.svg',
      width: width,
      fit: BoxFit.contain,
    );
  }
}
