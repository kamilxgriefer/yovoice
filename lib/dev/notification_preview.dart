// Developer-only preview of the production notification host. No Firebase,
// permissions, push registration or real recipient is involved.
// flutter run -d <simulator-id> -t lib/dev/notification_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

void main() => runApp(const _NotificationPreview());

class _NotificationPreview extends StatefulWidget {
  const _NotificationPreview();

  @override
  State<_NotificationPreview> createState() => _NotificationPreviewState();
}

class _NotificationPreviewState extends State<_NotificationPreview> {
  final _notifications = YoTopNotificationController();
  final _navigator = GlobalKey<NavigatorState>();
  bool _light = false;
  bool _polish = true;
  bool _reduceMotion = false;
  String _status = '';

  String _copy(String en, String pl) => _polish ? pl : en;

  @override
  void dispose() {
    _notifications.dispose();
    super.dispose();
  }

  void _show(NotificationType type, {bool long = false}) {
    final title = switch (type) {
      NotificationType.achievementUnlocked => _copy(
        'Achievement unlocked · preview',
        'Nowe osiągnięcie · podgląd',
      ),
      NotificationType.roomInvite => _copy(
        'A conversation is waiting · preview',
        'Rozmowa czeka · podgląd',
      ),
      _ => _copy('New message · preview', 'Nowa wiadomość · podgląd'),
    };
    final body = long
        ? _copy(
            'This is deliberately long sample content. The actual notification '
                'wraps fully, remains readable with enlarged text, and scrolls when '
                'there is not enough room. Close and Open remain within reach. '
                'No message was sent to another person.',
            'To celowo długa treść przykładowa. Prawdziwy komponent zawija tekst, '
                'pozostaje czytelny po powiększeniu i pozwala przewijać dłuższą '
                'wiadomość. Przyciski zamknięcia i otwarcia są stale dostępne. '
                'Żadna wiadomość nie została wysłana do innej osoby.',
          )
        : _copy(
            'A sample arrival using the production component. Tap to open.',
            'Przykładowe powiadomienie w produkcyjnym komponencie. Otwórz je.',
          );
    final accepted = _notifications.show(
      YoTopNotification(
        title: title,
        body: body,
        type: type,
        onOpen: () {
          setState(() => _status = _copy('Opened preview', 'Otwarto podgląd'));
          _navigator.currentState?.push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(title: Text(title)),
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(body),
                ),
              ),
            ),
          );
        },
      ),
    );
    setState(
      () => _status = accepted
          ? _copy('Shown — preview only', 'Wyświetlono — tylko podgląd')
          : _copy(
              'Not shown: close the keyboard or return to the app and retry.',
              'Nie wyświetlono: zamknij klawiaturę lub wróć do aplikacji i ponów.',
            ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: _light ? ThemeMode.light : ThemeMode.dark,
    locale: Locale(_polish ? 'pl' : 'en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: _reduceMotion),
      child: YoTopNotificationHost(
        controller: _notifications,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: YoPageBackground(
          section: YoPageSection.home,
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    _copy(
                      'Notifications — local preview',
                      'Powiadomienia — podgląd lokalny',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _copy(
                      'Explicit sample data. These controls do not send notifications.',
                      'Jawne dane przykładowe. Te przyciski nie wysyłają powiadomień.',
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Pearl'),
                    value: _light,
                    onChanged: (value) => setState(() => _light = value),
                  ),
                  SwitchListTile(
                    title: const Text('Polski / English'),
                    value: _polish,
                    onChanged: (value) => setState(() => _polish = value),
                  ),
                  SwitchListTile(
                    title: Text(_copy('Reduced Motion', 'Ogranicz ruch')),
                    value: _reduceMotion,
                    onChanged: (value) => setState(() => _reduceMotion = value),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _show(NotificationType.directMessage),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: Text(_copy('Message', 'Wiadomość')),
                      ),
                      OutlinedButton(
                        onPressed: () => _show(NotificationType.roomInvite),
                        child: Text(
                          _copy('Room invitation', 'Zaproszenie do pokoju'),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _show(NotificationType.achievementUnlocked),
                        child: Text(_copy('Achievement', 'Osiągnięcie')),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _show(NotificationType.directMessage, long: true),
                        child: Text(_copy('Long text', 'Długa treść')),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          _show(NotificationType.directMessage);
                          _show(NotificationType.roomInvite);
                          _show(NotificationType.achievementUnlocked);
                        },
                        child: Text(
                          _copy('Three arrivals', 'Trzy powiadomienia'),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _notifications.clear,
                        child: Text(
                          _copy('Clear immediately', 'Wyczyść natychmiast'),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              _copy('Dialog preview', 'Podgląd okna'),
                            ),
                            content: Text(
                              _copy(
                                'The notification is displayed above this dialog.',
                                'Powiadomienie pojawi się nad tym oknem.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    _show(NotificationType.directMessage),
                                child: Text(
                                  _copy(
                                    'Show notification',
                                    'Pokaż powiadomienie',
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  MaterialLocalizations.of(
                                    context,
                                  ).closeButtonLabel,
                                ),
                              ),
                            ],
                          ),
                        ),
                        child: Text(
                          _copy('Above a dialog', 'Nad oknem dialogowym'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    decoration: InputDecoration(
                      labelText: _copy(
                        'Keyboard and focus test',
                        'Test klawiatury i fokusu',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_status),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
