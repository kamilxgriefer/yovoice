import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

VideoPlayerController pickedMediaVideoControllerOnPlatform(XFile file) =>
    throw UnsupportedError('Video preview is unavailable on this platform.');
