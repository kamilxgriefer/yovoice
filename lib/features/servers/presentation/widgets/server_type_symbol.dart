import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/models/server_type.dart';

/// Exact vector paths from the approved selector, rendered as UI symbols.
class ServerTypeSymbol extends StatelessWidget {
  const ServerTypeSymbol({
    required this.type,
    required this.color,
    this.size = 31,
    super.key,
  });
  final ServerType type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" '
      'stroke="currentColor" fill="none" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round">${_paths[type]}</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
  static const _paths = <ServerType, String>{
    ServerType.friends:
        '<circle cx="12" cy="10" r="4"/>'
        '<path d="M3 27v-3a9 9 0 0 1 18 0v3M23 7a4 4 0 0 1 0 8M25 20a7 7 0 0 1 4 7"/>',
    ServerType.community:
        '<circle cx="16" cy="16" r="4"/>'
        '<path d="M8 8a11 11 0 0 0 0 16M24 8a11 11 0 0 1 0 16M4 4a17 17 0 0 0 0 24M28 4a17 17 0 0 1 0 24"/>',
    ServerType.podcast:
        '<rect x="11" y="3" width="10" height="17" rx="5"/>'
        '<path d="M6 15v2a10 10 0 0 0 20 0v-2M16 27v4M11 31h10"/>',
    ServerType.family:
        '<path d="m3 15 13-11 13 11M6 13v15h20V13M16 23s-7-4-7-8a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 4-7 8-7 8"/>',
    ServerType.company:
        '<rect x="3" y="9" width="26" height="19" rx="4"/>'
        '<path d="M10 9V5h12v4M3 17a35 35 0 0 0 26 0M14 17v5h4v-5"/>',
  };
}
