# YoVoice Stage 2 manifest

Main additions:
- lib/features/rooms/presentation/screens/community_voice_room_screen.dart

Modified:
- lib/features/rooms/presentation/screens/community_room_lobby_screen.dart
- lib/features/rooms/data/services/room_service.dart
- lib/features/calls/data/services/voice_call_service.dart

Validation required locally:
- flutter analyze
- test with two accounts: owner and participant
- deploy firestore.rules only if your active rules differ from the included version
