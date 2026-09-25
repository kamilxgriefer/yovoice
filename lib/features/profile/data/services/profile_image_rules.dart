import 'dart:typed_data';

/// What a profile image is for. Avatars and banners share a pipeline but not
/// their limits or aspect ratio.
enum ProfileImageKind { avatar, banner }

/// Image formats the app is willing to accept.
///
/// Deliberately narrow: these are the three the Flutter image codec can
/// decode on Web, iOS and Android alike. Anything else (HEIC straight off an
/// iPhone, TIFF, AVIF, SVG) is rejected up front with a readable message
/// rather than failing later inside the decoder or, worse, uploading bytes
/// no client can render.
enum ProfileImageFormat {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const ProfileImageFormat(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

/// Raised when a picked image cannot be accepted. [message] is written for
/// the user, not the log — callers surface it verbatim.
class ProfileImageException implements Exception {
  const ProfileImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Size/dimension budget for one kind of profile image.
class ProfileImageRules {
  const ProfileImageRules._({
    required this.kind,
    required this.maxSourceBytes,
    required this.maxOutputEdge,
    required this.aspectRatio,
  });

  static const ProfileImageRules avatar = ProfileImageRules._(
    kind: ProfileImageKind.avatar,
    maxSourceBytes: 5 * 1024 * 1024,
    maxOutputEdge: 1024,
    aspectRatio: 1,
  );

  /// 16:9 — deliberately a superset of what any screen shows.
  ///
  /// The profile hero (`ProfileHeroGeometry`) paints the banner as the
  /// header's full-bleed background with `BoxFit.cover` and
  /// `Alignment.center`. Its height is capped at the width's 16:9, so a phone
  /// shows the whole stored image; wider heroes run up to about 6.2:1 from
  /// 1440pt up, where only the middle ~29% of the height survives. Storing
  /// the 16:9 superset is the point: the hero can change in a redesign
  /// without asking anyone to re-upload their banner.
  ///
  /// The crop editor marks that surviving strip inside the 16:9 frame
  /// (`ImageCropScreen`'s banner safe band, sized from
  /// `ProfileHeader.bannerSafeBandFraction`), so the user can see which part
  /// always survives instead of discovering it afterwards.
  static const ProfileImageRules banner = ProfileImageRules._(
    kind: ProfileImageKind.banner,
    maxSourceBytes: 10 * 1024 * 1024,
    maxOutputEdge: 1920,
    aspectRatio: 16 / 9,
  );

  static ProfileImageRules of(ProfileImageKind kind) => switch (kind) {
    ProfileImageKind.avatar => avatar,
    ProfileImageKind.banner => banner,
  };

  final ProfileImageKind kind;

  /// Largest file we accept *from the picker*, before processing.
  final int maxSourceBytes;

  /// Longest edge of the processed upload.
  final int maxOutputEdge;

  /// Width / height of the final crop.
  final double aspectRatio;

  String get _label =>
      kind == ProfileImageKind.avatar ? 'Image' : 'Banner image';

  String get tooLargeMessage {
    final megabytes = maxSourceBytes ~/ (1024 * 1024);
    return '$_label must be smaller than $megabytes MB.';
  }

  /// Sniffs the real format from the file header.
  ///
  /// The extension is not trusted: pickers on Web hand back whatever name
  /// the OS supplied, and a `.jpg` that is really HEIC would only fail once
  /// it reached the decoder.
  static ProfileImageFormat? detectFormat(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return ProfileImageFormat.jpeg;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    var isPng = true;
    for (var i = 0; i < pngSignature.length; i++) {
      if (bytes[i] != pngSignature[i]) {
        isPng = false;
        break;
      }
    }
    if (isPng) return ProfileImageFormat.png;

    // WebP: "RIFF" .... "WEBP"
    final isRiff =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;
    final isWebp =
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    if (isRiff && isWebp) return ProfileImageFormat.webp;

    return null;
  }

  /// Validates a freshly picked file. Throws [ProfileImageException] with a
  /// user-facing message when the image cannot be used.
  void validateSource(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ProfileImageException(
        "We couldn't process this image. Try another one.",
      );
    }

    if (bytes.lengthInBytes > maxSourceBytes) {
      throw ProfileImageException(tooLargeMessage);
    }

    if (detectFormat(bytes) == null) {
      throw const ProfileImageException(
        'That file type is not supported. Use a JPG, PNG or WebP image.',
      );
    }
  }
}
