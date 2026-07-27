# Stage 5.4 — Achievement tracking fix

Modified files:

- `lib/features/achievements/data/services/achievement_service.dart`
- `lib/features/messages/presentation/screens/chat_screen.dart`

What changed:

- Every successfully sent text message now increments `messageCount`.
- Newly reached title thresholds are saved in `unlockedTitleIds`.
- The first unlocked title becomes the selected profile title when none is selected.
- A floating `Achievement unlocked!` notification appears in chat.
- Achievement tracking failure never cancels or duplicates a sent message.
