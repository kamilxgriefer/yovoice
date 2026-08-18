enum UiSoundChannel { room, controls, notification }

enum UiSound {
  roomCreated(
    fileName: 'room_created.wav',
    channel: UiSoundChannel.room,
    volume: 0.50,
    cooldown: Duration(milliseconds: 450),
  ),
  roomJoined(
    fileName: 'room_joined.wav',
    channel: UiSoundChannel.room,
    volume: 0.46,
    cooldown: Duration(milliseconds: 350),
  ),
  roomLeft(
    fileName: 'room_left.wav',
    channel: UiSoundChannel.room,
    volume: 0.43,
    cooldown: Duration(milliseconds: 350),
  ),
  participantJoined(
    fileName: 'participant_joined.wav',
    channel: UiSoundChannel.room,
    volume: 0.36,
    cooldown: Duration(milliseconds: 500),
  ),
  participantLeft(
    fileName: 'participant_left.wav',
    channel: UiSoundChannel.room,
    volume: 0.34,
    cooldown: Duration(milliseconds: 500),
  ),
  microphoneMuted(
    fileName: 'microphone_muted.wav',
    channel: UiSoundChannel.controls,
    volume: 0.42,
    cooldown: Duration(milliseconds: 100),
  ),
  microphoneUnmuted(
    fileName: 'microphone_unmuted.wav',
    channel: UiSoundChannel.controls,
    volume: 0.42,
    cooldown: Duration(milliseconds: 100),
  ),
  notification(
    fileName: 'notification.wav',
    channel: UiSoundChannel.notification,
    volume: 0.40,
    cooldown: Duration(milliseconds: 600),
  );

  const UiSound({
    required this.fileName,
    required this.channel,
    required this.volume,
    required this.cooldown,
  });

  final String fileName;
  final UiSoundChannel channel;
  final double volume;
  final Duration cooldown;

  String get assetPath => 'audio/ui/$fileName';
}
