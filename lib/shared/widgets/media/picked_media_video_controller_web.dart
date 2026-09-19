import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

VideoPlayerController pickedMediaVideoControllerOnPlatform(XFile file) =>
    VideoPlayerController.networkUrl(Uri.parse(file.path));
