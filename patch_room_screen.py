from pathlib import Path

path = Path('lib/features/rooms/presentation/screens/room_screen.dart')
if not path.exists():
    raise SystemExit(f'Nie znaleziono pliku: {path}')

text = path.read_text(encoding='utf-8')

old = '''            return _Controls(
              isMuted: isMuted,
              handRaised: handRaised,
              onMute: onMute,
              onRaiseHand: onRaiseHand,
              onChat: onOpenChat,
              onLeave: onLeave,
            );'''

new = '''            final voice = VoiceCallService.instance;
            final connectedToThisRoom =
                voice.isConnected && voice.roomId == room.id;

            if (!connectedToThisRoom) {
              return _JoinVoiceFooter(
                onJoin: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VoiceCallScreen(
                        roomId: room.id,
                        roomName: room.name,
                      ),
                    ),
                  );
                },
                onChat: onOpenChat,
              );
            }

            return _Controls(
              isMuted: voice.isMuted,
              handRaised: handRaised,
              onMute: () async {
                await voice.toggleMute();
                await service.setMuted(
                  roomId: room.id,
                  isMuted: voice.isMuted,
                );
              },
              onRaiseHand: onRaiseHand,
              onChat: onOpenChat,
              onLeave: onLeave,
            );'''

if old not in text:
    raise SystemExit(
        'Nie znaleziono oczekiwanego fragmentu w room_screen.dart. '
        'Plik mógł zostać wcześniej zmieniony.'
    )

path.write_text(text.replace(old, new), encoding='utf-8')
print('Gotowe: room_screen.dart został poprawiony.')
