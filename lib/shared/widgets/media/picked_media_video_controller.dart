import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'picked_media_video_controller_stub.dart'
    if (dart.library.io) 'picked_media_video_controller_io.dart'
    if (dart.library.js_interop) 'picked_media_video_controller_web.dart';

/// Builds an uninitialized, local-only preview controller for a video the
/// person just picked. Tests inject a fake; production uses
/// [pickedMediaVideoController].
typedef YoMediaPreviewControllerFactory =
    VideoPlayerController Function(XFile file);

/// io: `VideoPlayerController.file(path)`; web: the picker's blob URL. On a
/// platform without either, the returned controller fails to initialize and
/// the review falls back to its static video card.
VideoPlayerController pickedMediaVideoController(XFile file) =>
    pickedMediaVideoControllerOnPlatform(file);
