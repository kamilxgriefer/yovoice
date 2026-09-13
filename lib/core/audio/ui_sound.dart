enum UiSoundChannel { room, controls, notification, call }

/// Native notification delivery plays the incoming-call WAV once. Reserve
/// that audible window before handing continuous ringing to the in-app loop.
/// The generated master is 3.303 s; the small guard absorbs platform startup
/// jitter without leaving the call screen silent for a long retention period.
const Duration incomingCallNativeSoundWindow = Duration(milliseconds: 3600);

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
  ),
  notificationSocial(
    fileName: 'notification_social.wav',
    channel: UiSoundChannel.notification,
    volume: 1.0,
    cooldown: Duration(milliseconds: 800),
  ),
  notificationAchievement(
    fileName: 'notification_achievement.wav',
    channel: UiSoundChannel.notification,
    volume: 1.0,
    cooldown: Duration(milliseconds: 800),
  ),
  notificationAlert(
    fileName: 'notification_alert.wav',
    channel: UiSoundChannel.notification,
    volume: 1.0,
    cooldown: Duration(milliseconds: 800),
  ),
  callConnected(
    fileName: 'call_connected.wav',
    channel: UiSoundChannel.call,
    volume: 1.0,
    cooldown: Duration(milliseconds: 300),
  ),
  callIncoming(
    fileName: 'call_incoming_loop.wav',
    channel: UiSoundChannel.call,
    volume: 1.0,
    cooldown: Duration(milliseconds: 800),
  ),
  callEnded(
    fileName: 'call_ended.wav',
    channel: UiSoundChannel.call,
    volume: 1.0,
    cooldown: Duration(milliseconds: 300),
  ),
  callDeclined(
    fileName: 'call_declined.wav',
    channel: UiSoundChannel.call,
    volume: 1.0,
    cooldown: Duration(milliseconds: 300),
  ),
  callFailed(
    fileName: 'call_failed.wav',
    channel: UiSoundChannel.call,
    volume: 1.0,
    cooldown: Duration(milliseconds: 300),
  ),
  callBusy(
    fileName: 'call_busy.wav',
    channel: UiSoundChannel.call,
    volume: 1.0,
    cooldown: Duration(milliseconds: 300),
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

  String get assetPath => 'audio/ui/v5/$fileName';
}
