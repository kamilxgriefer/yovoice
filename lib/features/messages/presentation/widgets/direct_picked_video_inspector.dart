import 'package:image_picker/image_picker.dart';

import 'direct_picked_video_inspector_stub.dart'
    if (dart.library.io) 'direct_picked_video_inspector_io.dart'
    if (dart.library.js_interop) 'direct_picked_video_inspector_web.dart';

typedef DirectMessageVideoInspector = Future<Duration> Function(XFile video);

Future<Duration> inspectPickedDirectVideo(XFile video) =>
    inspectDirectVideoOnPlatform(video);
