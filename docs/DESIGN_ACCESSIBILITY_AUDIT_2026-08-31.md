# YO Voice — audyt design systemu i dostępności

Data: 31 sierpnia 2026

Zakres: Flutter UI — wspólny theme i komponenty, logowanie/rejestracja, onboarding, główna nawigacja, ustawienia i formularze

Standard odniesienia: WCAG 2.1 AA

## Podsumowanie

YO Voice ma dobrą bazę: semantyczne palety Dark/Pearl, testy kontrastu, responsywny auth, klawiaturowy onboarding i dolną nawigację z poprawnymi obszarami dotyku. Audyt usunął najważniejsze pozostałe niespójności w obszarach wspólnych, tak aby poprawki objęły wiele ekranów bez zmiany charakteru marki.

Nie jest to deklaracja stuprocentowej zgodności. Przed publicznym wydaniem nadal potrzebny jest krótki test manualny na fizycznych urządzeniach z VoiceOver i TalkBack, powiększeniem systemowym oraz klawiaturą.

## Wdrożone poprawki

| Obszar | Ryzyko | Zmiana | Odniesienie |
| --- | --- | --- | --- |
| Cele dotykowe | Część wspólnych kontrolek mogła zejść poniżej 44 px | Dodano wspólne tokeny rozmiaru; przyciski i ikony mają minimum 44 px, standardowe kontrolki 48 px | WCAG 2.5.5, 2.5.8 jako praktyka przyszłościowa |
| Widoczny fokus | Fokus klawiatury nie był jednakowo czytelny na wszystkich typach przycisków | Theme zapewnia spójny, dwupikselowy focus ring w obu motywach | WCAG 2.4.7 |
| Formularze | Widoczny komunikat błędu nie zawsze był jednoznacznie połączony z polem | Błąd jest przekazywany do semantyki pola i ogłaszany jako live region; uniknięto podwójnej narracji ikony | WCAG 3.3.1, 4.1.2, 4.1.3 |
| Loading/error/empty | Stany asynchroniczne miały różne animacje i nie zawsze były ogłaszane | Wspólne stany mają spójne etykiety, live regions, nagłówki i obsługę ograniczenia animacji | WCAG 1.3.1, 4.1.3 |
| Reduce Motion | Czas animacji był rozproszony i nie każda kontrolka respektowała ustawienie systemowe | Dodano centralne tokeny ruchu; podstawowe przyciski, formularze i stany wyłączają przejścia przy `disableAnimations` | Preferencja platformy; poprawa komfortu ponad minimum AA |
| Ustawienia asynchroniczne | Podczas zapisu inne opcje mogły wyglądać na aktywne mimo blokady | Wybory języka, wyglądu i prywatności wyraźnie oraz semantycznie blokują się na czas zapisu; status „Saving” ma kontekst | WCAG 3.2.2, 4.1.2, 4.1.3 |
| Reflow ustawień | Długie nazwy, odznaki i trailing status mogły być ściśnięte przy 320 px / 200% tekstu | Profil i wiersze ustawień przechodzą w układ pionowy, zachowują pełne etykiety i minimalną wysokość | WCAG 1.4.10, 1.4.4 |
| Semantyka wyborów | Część kart opcji składała się w kilka niejednoznacznych węzłów | Każda karta jest pojedynczym przyciskiem z nazwą, stanem selected/enabled i jasną akcją | WCAG 1.3.1, 4.1.2 |

## Potwierdzone mocne strony

- Krytyczne pary tekst/tło mają automatyczne testy kontrastu co najmniej 4.5:1; elementy nietekstowe co najmniej 3:1.
- Auth ma testy dla szerokości od 320 do 1440 px, polskiej treści i tekstu 200%.
- Główna nawigacja ma co najmniej 48 px celu, etykiety semantyczne, obsługę klawiatury oraz stabilną oś podczas hover/focus.
- Onboarding ma pułapkę fokusu, Escape/strzałki, test 320 px przy 200% tekstu i respektuje Reduce Motion.
- Dark i Pearl przeszły przegląd screenshotów na telefonie, tablecie i desktopie, włącznie z 320 px / 200% tekstu.

## Weryfikacja automatyczna

- 34/34: theme, wspólne komponenty, preferencje i prywatność wiadomości.
- 117/117: auth, onboarding, główna nawigacja, arkusz More, responsive frame i matryca screenshotów Dark/Pearl.
- `flutter analyze`: brak błędów w zmienionym zakresie. Pozostaje jedno wcześniejsze ostrzeżenie informacyjne poza zakresem audytu w `moment_service.dart`.
- `git diff --check`: bez błędów whitespace.

## Kontrole manualne przed wydaniem

1. Przejść pełną rejestrację, onboarding, zmianę motywu/języka i wylogowanie za pomocą VoiceOver na iOS.
2. Powtórzyć przepływ TalkBackiem na małym Androidzie, w tym przełączniki prywatności i komunikaty zapisu.
3. Sprawdzić browser zoom 200%, systemowe największe fonty oraz sterowanie Tab/Shift+Tab/Enter/Escape.
4. Zweryfikować kolejność ogłaszania odznak i długich nazw na prawdziwych danych profilowych.
5. Uzupełnić lokalizację pozostałych starszych tekstów ustawień; nie blokuje to reflow ani obsługi czytnika, ale poprawi spójność produktu.

## Kierunek design systemu

Nowe komponenty powinny korzystać z `AppPalette`, `AppSizing` i `AppMotion` zamiast lokalnych wartości. Lokalny kolor jest dopuszczalny tylko dla znaczenia produktu lub świadomego efektu marki i powinien mieć test kontrastu w Dark oraz Pearl. Każda akcja powinna mieć nazwę semantyczną, widoczny fokus i co najmniej 44 × 44 px obszaru interakcji.
