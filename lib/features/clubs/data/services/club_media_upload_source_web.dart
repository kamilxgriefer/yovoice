import 'package:image_picker/image_picker.dart';

import 'club_media_upload_source.dart';
import 'club_media_upload_source_stub.dart' as bytes;

/// The browser keeps `putData`, and deliberately so.
///
/// A web picker never produced a file: its `XFile` wraps a Blob the page
/// already holds, so there is nothing for `putFile` to stream and one copy out
/// of that Blob is the floor. `putBlob` could avoid even that copy, but reaching
/// the picker's Blob means re-fetching its object URL — a browser-only path
/// this repo's suite cannot exercise and that breaks the moment the URL is
/// revoked. The byte transport is therefore the web implementation too, reached
/// through the same conditional import the direct-message payload store uses so
/// the shape is one shape, not two.
ClubMediaUploadSource createClubMediaUploadSource(
  XFile file, {
  required int length,
}) => bytes.createClubMediaUploadSource(file, length: length);
