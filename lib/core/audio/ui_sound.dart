enum UiSoundChannel { room, controls, notification }

enum UiSound {
  roomCreated(
    fileName: 'room_created.wav',
    channel: UiSoundChannel.room,
    volume: 1.0,
    cooldown: Duration(milliseconds: 600),
  ),
  roomJoined(
    fileName: 'room_joined.wav',
    channel: UiSoundChannel.room,
    volume: 1.0,
    cooldown: Duration(milliseconds: 450),
  ),
  roomLeft(
    fileName: 'room_left.wav',
    channel: UiSoundChannel.room,
    volume: 1.0,
    cooldown: Duration(milliseconds: 350),
  ),
  participantJoined(
    fileName: 'participant_joined.wav',
    channel: UiSoundChannel.room,
    volume: 1.0,
    cooldown: Duration(milliseconds: 750),
  ),
  participantLeft(
    fileName: 'participant_left.wav',
    channel: UiSoundChannel.room,
    volume: 1.0,
    cooldown: Duration(milliseconds: 750),
  ),
  microphoneMuted(
    fileName: 'microphone_muted.wav',
    channel: UiSoundChannel.controls,
    volume: 1.0,
    cooldown: Duration(milliseconds: 120),
  ),
  microphoneUnmuted(
    fileName: 'microphone_unmuted.wav',
    channel: UiSoundChannel.controls,
    volume: 1.0,
    cooldown: Duration(milliseconds: 120),
  ),
  notification(
    fileName: 'notification.wav',
    channel: UiSoundChannel.notification,
    volume: 1.0,
    cooldown: Duration(milliseconds: 800),
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

  String get assetPath => 'audio/ui/v4/$fileName';
}
