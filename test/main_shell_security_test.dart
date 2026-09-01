import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';

void main() {
  group('initial room links', () {
    test('accepts only bounded Firestore-safe room ids', () {
      expect(isSafeInitialRoomLinkId('room_01-public'), isTrue);
      expect(isSafeInitialRoomLinkId('a' * 128), isTrue);

      expect(isSafeInitialRoomLinkId(''), isFalse);
      expect(isSafeInitialRoomLinkId('a' * 129), isFalse);
      expect(isSafeInitialRoomLinkId('../admin'), isFalse);
      expect(isSafeInitialRoomLinkId('room/participant'), isFalse);
      expect(isSafeInitialRoomLinkId('room?publish=true'), isFalse);
    });
  });
}
