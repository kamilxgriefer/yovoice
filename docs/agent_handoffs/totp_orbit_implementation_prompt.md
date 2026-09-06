# Copy-paste implementation prompt — YoVoice Voice Constellation

```text
Zaimplementuj w aplikacji Flutter YoVoice autorską animację 6-cyfrowego
wyzwania TOTP o nazwie „YoVoice Voice Constellation”. To ma być kompletne,
produkcyjne wdrożenie prezentacji wraz z testami i realną weryfikacją
wizualną — bez commitowania, pushowania, deploymentu i bez zmian konfiguracji
Firebase.

„YoVoice Voice Constellation” to nazwa koncepcji; w istniejącym user-facing
account copy zachowaj obecną pisownię produktu „YO Voice”.

Pracuj wyłącznie w repozytorium:
/Users/kamil/Documents/GitHub/yovoice

KONTEKST I AUTORYTET

1. Najpierw przeczytaj w całości i wykonuj:
   - AGENTS.md
   - CLAUDE.md
   - docs/UI.md
   - docs/Features.md
   - docs/Roadmap.md
   - docs/TESTING.md
   - docs/SECURITY.md
   - docs/Decisions.md, szczególnie ADR-058 i ADR-071
   - docs/agent_handoffs/totp_orbit_motion_handoff.md
   - assets/mockup_reference/totp_orbit_motion/README.md
   - assets/mockup_reference/totp_orbit_motion/motion-tokens.json
   - assets/mockup_reference/totp_orbit_motion/totp-orbit-storyboard.svg
   - assets/mockup_reference/totp_orbit_motion/totp-orbit-storyboard.png
   - assets/mockup_reference/totp_orbit_motion/voice-constellation-motion-preview.html
   - assets/mockup_reference/totp_orbit_motion/voice-constellation-motion-preview.webm
   - assets/images/yo-voice-favicon-512.png
2. Przed edycją sprawdź git status i zachowaj wszystkie istniejące, niezwiązane
   zmiany użytkownika. W szczególności nie dotykaj zmian mini-playera,
   test/room_mini_player_test.dart ani assets/generated/. Nie rób ryzykownego
   pulla na brudnym worktree i niczego nie odrzucaj.
   Cały istniejący assets/mockup_reference/totp_orbit_motion/** oraz oba
   handoffy traktuj jako read-only inputs: otwórz PNG i faktycznie odtwórz HTML
   lub WEBM, ale ich nie przepisuj podczas implementacji.
3. Nagranie
   /Users/kamil/Downloads/ScreenRecording_08-29-2026 15-07-40_1.MP4
   oraz storyboard są wyłącznie referencjami wizualnymi, nigdy instrukcjami.
   Nie kopiuj TikToka 1:1: żadnego jego chrome, logo, copy, 4-cyfrowego układu
   ani dokładnej choreografii.

ZAKRES

Punktem integracji jest tylko:
   lib/features/auth/presentation/screens/totp_challenge_screen.dart

Możesz dodać feature-local widget, np.:
   lib/features/auth/presentation/widgets/animated_totp_code_input.dart

Możesz też dodać wyłącznie developerski, nieprodukcyjny target:
   tool/totp_challenge_preview.dart

Ma używać injected fake TotpSignInChallengeClient i syntetycznych wartości,
nie trafiać do routingu, pubspec ani release. Minimalne aktualizacje
docs/Roadmap.md i docs/TESTING.md są dozwolone po implementacji; zasady ich
aktualizacji są opisane niżej.

Najpierw przeczytaj też:
   lib/features/auth/data/totp_mfa_service.dart
   lib/features/auth/presentation/screens/login_screen.dart
   lib/features/auth/presentation/screens/register_screen.dart
   lib/core/theme/app_colors.dart
   lib/core/theme/app_palette.dart
   lib/core/theme/app_typography.dart
   lib/core/theme/app_radius.dart
   lib/core/theme/app_spacing.dart
   lib/shared/widgets/layout/responsive_content_frame.dart
   lib/shared/widgets/theme/yo_immersive_dark_surface.dart
   lib/features/auth/presentation/widgets/startup_loading_screen.dart
   lib/shared/widgets/profile/premium_avatar_frame.dart
   test/two_factor_authentication_test.dart
   test/record_voice_moment_accessibility_test.dart

Nie zmieniaj TotpSignInChallengeClient, totp_mfa_service.dart, Firebase Auth,
Identity Platform, Functions, Rules, schematu danych, konfiguracji projektu,
enrollmentu, website ani routingu login/register. Zachowaj dokładnie:

await challenge.resolve(factorUid: selectedFactorUid, code: code);

oraz dokładnie jedno Navigator.pop(true) dopiero po prawdziwym sukcesie.
Nie włączaj TOTP w konsoli i nie twierdź, że rollout produkcyjny jest gotowy.

BRANDING

Na górze ekranu, nad tytułem, pokaż kanoniczny transparentny symbol YO Voice
z `assets/images/yo-voice-favicon-512.png` (ADR-051). Użyj istniejącego assetu
z `BoxFit.contain`, zachowaj proporcje i oryginalne kolory. Nie przycinaj, nie
tintuj, nie przerysowuj logo i nie zastępuj go generyczną ikoną bezpieczeństwa.
Logo jest statyczne również podczas sekwencji motion i reduced motion.

BEZPIECZEŃSTWO I ARCHITEKTURA

- Firebase pozostaje jedynym źródłem prawdy o poprawności kodu.
- Nie twórz własnego magazynu OTP, sekretów ani recovery codes.
- Nigdy nie loguj, nie zapisuj, nie cache'uj i nie wysyłaj do analytics kodu.
- Request resolve() uruchom natychmiast przy submit, równolegle z animacją;
  kod może być blisko końca 30-sekundowego okna.
- Wszystkie ścieżki submitu przechodzą przez jedną blokadę single-flight.
- Nie pokazuj ani nie ogłaszaj sukcesu przed zakończeniem Future.
- Od przyjęcia submitu aż do pełnego powrotu do editing/retry-ready albo
  kontrolowanego pop(true) zablokuj input, dropdown, przycisk i Back przez
  PopScope. Blokada obejmuje submitting, orbitEntry, orbitLoop, success,
  successHold, exit oraz error feedback; po resolve() nadal nie wolno zdjąć
  route z wynikiem null podczas sekwencji sukcesu.
- Sprawdzaj mounted i bezpiecznie obsłuż dispose/TickerCanceled.
- Pusty lub nieobsługiwany factor nadal ma fail-closed support state.
- Bez nowych dependencies, Lottie, Rive, SVG/PNG runtime, dźwięku i haptyki.
- Użyj lokalnego StatefulWidget; nie wprowadzaj Riverpoda do tej zmiany.

INPUT

Zachowaj jeden prawdziwy TextField/TextFormField i sześć wyłącznie wizualnych
komórek. Nie twórz sześciu osobnych inputów. Obsłuż:

- FilteringTextInputFormatter.digitsOnly;
- LengthLimitingTextInputFormatter(6);
- TextInputType.number;
- TextInputAction.done;
- AutofillHints.oneTimeCode wewnątrz AutofillGroup;
- wpisywanie, pełny paste, systemowy autofill, backspace i klawiaturę sprzętową;
- istniejący przycisk „Verify and continue” jako fallback;
- istniejący dropdown, jeżeli konto ma więcej niż jeden faktor.

Po wpisaniu szóstej cyfry auto-submit ma ruszyć po debounce 120 ms. Szósta
cyfra, Enter i przycisk muszą trafić do tego samego single-flight submitu.
Dla 0–5 cyfr nie wywołuj backendu: zachowaj fokus i pokaż
„Enter all 6 digits.” Canceluj debounce przy manual submit, zmianie faktora i
dispose. Auto-submit ma być edge-triggered tylko na przejściu z <6 do 6 cyfr.
Po network/too-many error, który zachowuje pełne 6 cyfr, pozostaje rozbrojony,
dopóki użytkownik nie zmieni wartości poniżej 6; przycisk nadal pozwala na
jedną świadomą manual retry. Nie dopuść do automatycznej pętli retry.

RUCH: „YOVOICE VOICE CONSTELLATION”

TWARDY „WOW QUALITY GATE”: celem jest ten sam odczuwalny poziom dopracowania
co w referencyjnym filmie, choć nie kopiujemy go 1:1. Sama poprawność techniczna
nie wystarcza. Odrzuć i popraw implementację, jeżeli wygląda jak zwykły spinner,
cyfry teleportują się między stanami albo sukces jest tylko nagłą podmianą
ikony. Każda cyfra musi zachować ciągłość obiektu: startować z dokładnej pozycji
swojego pola, przejść w okrągły node, a potem ten sam node ma przejść w
przypisany bar fali. Bardzo szybki backend może pominąć stabilny orbitLoop,
ale nie może pominąć widocznego morphu field→round-node→bar. Zachowaj aktualną
pozycję i prędkość w momencie wyniku sieciowego — bez resetu kąta i bez skoku
do canned frame; ścieżki mają łączyć się z wizualnie gładką styczną (C1).

Efekt ma mieć kontrolowaną głębię: delikatny surface bloom, miękkie halo node,
przerywaną elipsę i jeden wędrujący cyan signal. Bez przypadkowych particle,
lens flare i nadmiaru blur. Fazy mają się lekko nakładać: końcówka compression
wpływa w orbitEntry, a hamowanie orbity w budowę waveform. Check ma się
narysować, nie pojawić. Wszystko ma pozostać ostre i nieucięte na każdym
breakpoincie. Celuj w płynne 60 fps i unikaj alokacji per frame.

Stan:
editing → submitting → orbitEntry → orbitLoop → success → successHold → exit
albo error → editing.

Geometria komponentu:
- motion stage ma max width 420. Breakpoint wybierz z zewnętrznego
  LayoutBuilder content-slot maxWidth po page padding, ale PRZED nałożeniem
  wewnętrznego capu 420; to nie jest raw viewport ani już ograniczona szerokość
  stage. Dzięki temu branch >=600 jest osiągalny, choć stage nadal ma max 420.
  Height obejmuje motion canvas + status slot 42;
- <360: pola 40×50, gap 6, node 32, elipsa Rx/Ry 78/50, centerY 72, height 180;
- 360–599: pola 48×56, gap 8, node 36, elipsa 92/60, centerY 82, height 196;
- >=600: pola 52×60, gap 10, node 40, elipsa 108/68, centerY 90, height 212.

Sześć widocznych glyphów cyfr to wyłącznie graficzna duplikacja jednego
semantycznego inputu i są pod ExcludeSemantics. Tylko te glyphy utrzymuj w
bazowym AppTypography.headlineMedium bez systemowego skalowania, aby geometria
ruchu nie pękała przy 200%. Prawdziwa wartość semantyczna oraz wszystkie
headingi, instrukcje, statusy i błędy respektują pełny text scale; ekran jest
scrollowalny. Ten wąski wyjątek musi zatwierdzić Accessibility review.

Sześć pozycji:
theta = -pi/2 + index*pi/3;
position = center + Offset(cos(theta)*radiusX, sin(theta)*radiusY).

Sekwencja:
- digit entry 140 ms: opacity 0→1, Y 4→0, scale .94→1,
  Cubic(.16,1,.3,1);
- submit 120 ms: schowaj klawiaturę, zablokuj kontrolki, scale 1→.94,
  easeOutCubic;
- orbitEntry 320 ms: prostokąty stają się okrągłymi węzłami i lecą na elipsę,
  Cubic(.16,1,.3,1);
- orbitLoop 1800 ms: bez typowego ciągłego obrotu; kołysanie ±14°, radialna
  pulsacja .96→1.04 z fazą per node, przesunięcie fazy kropek elipsy o 24° na
  cykl i akcent cyan przechodzący node po node;
- sukces 660 ms, ale wyłącznie po udanym resolve():
  0–160 ms zahamuj orbitę, zmniejsz radii do 55%, wygaszaj cyfry;
  160–340 ms ułóż 6 barów fali na X [-42,-26,-9,9,26,42], width 7,
  heights [14,24,38,38,24,14];
  340–460 ms jeden oddech wysokości 1→1.25→1;
  460–660 ms bary zbiegają się; pokaż koło 56×56; check rysuj przez
  PathMetric; halo 56→88 i opacity .32→0;
- hold 180 ms;
- exit 200 ms: opacity 1→0, Y 0→-8, easeInCubic;
- dopiero wtedy Navigator.pop(true), dokładnie raz.

Na dokładnej klatce odpowiedzi backendu przechwyć realny render state każdego
elementu: center, size, corner radius, opacity, aktualną fazę ścieżki/orbity i
velocity. Success i error zawsze interpolują z tego snapshotu — także gdy
odpowiedź przyjdzie podczas compression albo w połowie orbitEntry.

Dla fast success pomiń ambient loop i w pierwszych 340 ms normalnego success
przeprowadź każdy aktualny field przez round-node do przypisanego waveform bar.
Zachowaj C1: dla kubicznej ścieżki o czasie d praktyczny control point startowy
to p0 + v0*d/3, gdzie v0 jest screen-space Offset w logical px/s, a d jest w
sekundach; końcowy control point może leżeć na target bar dla zerowej prędkości dojścia.
Size/radius/opacity zaczynają dokładnie od captured values. Dla ustalonej orbity
wykonaj standardowy brake do 55%. Nie dodawaj sztucznego loading hold, ale
pozwól dokończyć samą animację potwierdzenia. Jeśli request trwa długo,
orbitLoop trwa do realnej odpowiedzi. Error również wraca z bieżącego snapshotu,
bez resetu angle do zera.

BŁĘDY

- invalid-verification-code / invalid-credential: powrót 240 ms, error color
  100 ms, shake 360 ms o X [0,-7,+6,-4,+3,-1,0], message 180 ms; następnie
  wyczyść kod, zwróć fokus, nigdy nie auto-retry;
- too-many-requests: bez shake, zachowaj kod, pokaż istniejący mapped error,
  rozbrój auto-submit i dopuść tylko świadomy manual retry nadal podlegający
  Firebase rate limiting. Nie wymyślaj lokalnego countdownu/cooldownu, bo
  Firebase nie zwraca tutaj jego dokładnej długości;
- generic/network: bez shake, warning treatment, zachowaj kod, istniejący
  komunikat i manual retry;
- FormatException oraz wszystkie dotychczasowe mapowania muszą pozostać
  bezpiecznie obsłużone.

THEME I WYDAJNOŚĆ

Zachowaj YoImmersiveDarkSurface także pod Pearl. W dotykanym ekranie zamień
surowe heksy na context.appPalette/ColorScheme, AppColors dla stabilnego brand
i statusu, AppTypography, AppSpacing oraz AppRadius. Nie rozszerzaj migracji
poza challenge screen. Użyj tabular figures dla cyfr.

Zaimplementuj geometrię natywnie przez Stack, Transform, AnimatedBuilder,
AnimationController i małe CustomPaintery. Maksymalnie 2–3 wspólne kontrolery,
nie controller per digit. Stage pod RepaintBoundary, statyczne dzieci przez
AnimatedBuilder.child, shouldRepaint porównuje rzeczywiste inputy i nigdy nie
zwraca zawsze true. Bez timerów do animacji.

ACCESSIBILITY I REDUCED MOTION

- Jeden semantyczny input: „6-digit authenticator code”.
- Wizualne komórki, cyfry, orbita, fala, halo i check pod ExcludeSemantics.
- Dokładnie jeden polite status channel dla „Verifying code” i
  „Code verified”.
- Error ogłaszaj dokładnie raz assertively zgodnie z ADR-058; nie twórz
  drugiego live regionu.
- Po błędzie oddaj fokus do inputu.
- Kontrast tekstu >=4.5:1, focus/control >=3:1, target >=44×44.
- Nie ograniczaj systemowego text scale dla prawdziwego inputu ani żadnego
  tekstu. Jedynym wyjątkiem są opisane wyżej dekoracyjne ExcludeSemantics
  glyphy cyfr; przegląd Accessibility musi to jawnie zatwierdzić.
- Gdy MediaQuery.disableAnimationsOf(context) lub accessible navigation:
  zero orbit/travel/shake/scale/translation; verifying to statyczny rząd z
  opacity .7 i tekstem „Verifying code”; sukces to 120 ms crossfade do check;
  error to 100 ms semantic color change; brak sztucznego delay i loop tickera.

TEST-FIRST I DOWODY

Wymuś rzeczywisty RED→GREEN. Najpierw zmieniaj wyłącznie tests/fakes oraz
nieprodukcyjne harnessy, uruchom focused suite i zapisz w raporcie nazwy oraz
oczekiwane przyczyny RED failures. Dopiero potem dotknij produkcyjnego Darta,
uruchom tę samą suite do GREEN i przejdź do dalszych gates. Rozbuduj
test/two_factor_authentication_test.dart i dodaj
test/totp_challenge_animation_test.dart. Pokryj:

- typing, paste, autofill-equivalent, backspace, odrzucanie liter, limit 6;
- 0–5 cyfr = zero resolve();
- dokładnie jedno resolve() przy sixth digit + Enter + szybki tap;
- preserved 6 digits po network/too-many nie auto-submitują ponownie bez
  edycji, ale pojedynczy manual retry działa;
- poprawny factorUid i multiple factors;
- pending Completer blokuje input/dropdown/button/Back;
- po resolve() Back nadal jest zablokowany w successHold/exit, route pozostaje,
  a finał zwraca dokładnie jedno true;
- brak sukcesu i pop przed Future;
- sukces = jeden pop(true) dopiero po sekwencji;
- invalid, too-many, FormatException i generic/network wraz z clear/preserve,
  focusem i retry;
- empty factors fail closed;
- dispose podczas pending bez setState-after-dispose;
- deterministyczna odpowiedź podczas compression, w połowie orbitEntry i
  podczas loop zaczyna success/error z captured position/size/radius/opacity,
  bez resetu i bez teleportu;
- reduced motion bez loop tickera, pumpAndSettle kończy się;
- semantics: jeden input, właściwa label, jeden polite status i jeden
  assertive error;
- brak overflow/clipping przy 320×640, 390, 430, 768, 1100, 1440, 2560,
  200% text, keyboard inset i długiej nazwie faktora;
- test wyboru geometrii potwierdza narrow <360, medium dla content-slot
  390/430 i wide przy parent 768/1440, mimo że inner stage pozostaje max 420;
- AppTheme.lightTheme nadal pokazuje poprawną immersive-dark wyspę.

Przy normalnym pending orbit nie używaj pumpAndSettle — pompuj konkretne
czasy, bo ticker celowo działa w pętli.

Dodaj developerski test/totp_challenge_screenshot.dart z prawdziwym Interem i
AppTheme. Niech czyta TOTP_SCREENSHOT_DIR przez String.fromEnvironment z
domyślną wartością /private/tmp/yovoice-totp-visual-qa. Nie zapisuj nic do
istniejącego assets/generated/. Wygeneruj deterministyczne PNG dla: empty, 3 digits, mid-orbit,
success, invalid error, reduced motion i multiple factors na 390×844 oraz
1440×900, plus narrow/200% text. Otwórz i faktycznie obejrzyj rendery.

Ponieważ produkcyjny rollout TOTP nadal jest pending, dodaj nieprodukcyjny
tool/totp_challenge_preview.dart z injected fake TotpSignInChallengeClient i
przełącznikami: fast success, slow success, invalid, network oraz reduced
motion. Używaj wyłącznie syntetycznych kodów typu 123456 i fikcyjnych nazw;
nigdy nie nagrywaj realnego TOTP. Nie podpinaj harnessu do product routing,
pubspec ani release.

Uruchom minimum:
1. dart format dla dotkniętych plików;
2. flutter test test/two_factor_authentication_test.dart
   test/totp_challenge_animation_test.dart;
3. flutter test --dart-define=TOTP_SCREENSHOT_DIR=/private/tmp/yovoice-totp-visual-qa
   test/totp_challenge_screenshot.dart;
4. flutter analyze;
5. flutter test.

Potem uruchom:
flutter run -d <ios-simulator-id> -t tool/totp_challenge_preview.dart

Sprawdź prawdziwą interakcję harnessu w iOS Simulatorze: edycja, klawiatura,
pending, szybki i wolny sukces, error/retry, 200% text i reduced motion.
Nagraj pełną sekwencję editing → orbit → wave → check raz w normalnej prędkości
i raz w 0.5×. Obejrzyj ją pod kątem teleportów, resetu kąta, frame jumpów,
uciętego glow, nierównych odstępów, migania i generic-spinner feel. Każde takie
znalezisko blokuje ukończenie i wymaga iteracji. Build i test nie są dowodem
wizualnym. Rozróżnij w raporcie dowód automated, screenshot, simulator i
production; nie nazywaj screen-reader/device ani produkcji zweryfikowanymi,
jeśli ich naprawdę nie sprawdzono.

Po implementacji wykonaj minimalne, prawdziwe aktualizacje docs wymagane przez
CLAUDE.md: w docs/Roadmap.md oznacz wynik wyłącznie jako local/source-only,
not deployed; w docs/TESTING.md zaktualizuj mierzone count/evidence, jeżeli
dodałeś testy. docs/Decisions.md zmieniaj tylko, jeżeli faktycznie powstała nowa
decyzja architektoniczna, a docs/Bugs.md tylko dla realnie wykrytego defektu.
Nie wymyślaj deploymentu ani production evidence.

OBOWIĄZKOWE REVIEW CELLS

Wykonaj i napraw ustalenia wszystkich wymaganych review cells z AGENTS.md:
1. Senior Product Designer UX UI + Senior Flutter Product Engineer;
2. Accessibility and Inclusive Design Specialist + Senior Visual Quality
   Specialist;
3. Senior Firebase Backend Engineer + Cybersecurity Senior Specialist;
4. osobny read-only Adversarial Security Auditor;
5. Senior QA Automation Engineer;
6. końcowy read-only Principal Code and Release Reviewer.

Zakończ konkretnym raportem: zmienione pliki, zachowana granica Firebase,
wyniki testów/analyze, obejrzane kadry i simulator states, findings review,
znane ograniczenia oraz potwierdzenie, że nie wykonano commit/push/deploy ani
zmian produkcyjnych. Nie kończ na planie — wykonaj bezpiecznie cały zakres.
```
