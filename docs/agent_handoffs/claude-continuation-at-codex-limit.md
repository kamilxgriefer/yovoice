> HISTORICAL (2026-09-11): superseded by the later tester builds, starting
> with Build 24 (`001626e7`, 2026-09-12). Do not execute. Kept because
> `docs/Sessions/2026-09-11-servers-runtime-and-mapping.md` links to it.

# YO Voice — kompletny prompt kontynuacji dla Claude'a

Stan przekazania: **11 września 2026, około 17:42 Europe/Amsterdam**.
Monitor konta wykazał 99% wykorzystania głównej puli Codex, czyli 1% pozostałego
limitu. To przyczyna przekazania, ale **nie jedyna przeszkoda w wydaniu**.
Poniższy tekst można w całości przekazać Claude'owi mającemu lokalny dostęp do
projektów. Niczego nie wysłano automatycznie do Claude'a ani innej usługi.

## Zadanie i warunek zakończenia

Wznów i dokończ istniejące prace nad YO Voice. Nie zaczynaj aplikacji od nowa,
nie zastępuj implementacji makietami i nie porzucaj części zaakceptowanego
zakresu, żeby szybciej ogłosić sukces. Po rzeczywistym ukończeniu CAŁEGO zakresu,
niezależnych przeglądach i wymaganej weryfikacji przygotuj oraz udostępnij nowy
build obecnym testerom **Apple TestFlight i Google Play**. Potwierdź dostępność
oddzielnie dla obu platform, dopiero potem powiadom testerów.

**Aktualny werdykt: HOLD — wydanie niegotowe.** Pełne Serwery, integracja
rzeczywistych usług i odbiór na urządzeniach pozostają otwarte. Właściciel nie
odpowiedział na pytanie, czy dopuszcza osobny build samych sprawdzonych poprawek
z Serwerami wyłączonymi. Bez tej odpowiedzi NIE zakładaj zgody na częściowe
wydanie. Termin i wyczerpanie limitu nie znoszą bramek jakości.

Zgoda na przyszły build dla istniejących testerów nie zastępuje osobnej zgody
na produkcyjną migrację danych, aktywację nowych funkcji, destrukcyjne
przełączenie ani publiczny release sklepowy. Przygotuj konkretny plan i uzyskaj
wymaganą zgodę w odpowiednim momencie. Nie przedstawiaj lokalnych testów jako
potwierdzenia działania produkcji.

## 1. Repozytoria i ochrona zastanej pracy

- Aplikacja Flutter/Firebase: `/Users/kamil/Documents/GitHub/yovoice`.
- Strona Next.js/Vercel: `/Users/kamil/Documents/GitHub/yovoice-website`.
- Referencje Serwerów: `/Users/kamil/Documents/GitHub/yovoice-server-concepts-2026-09-10`.
- Dodatkowy istniejący projekt treści: `/Users/kamil/Documents/GitHub/yovoice-marketing`;
  nie jest drugą aplikacją Firebase. Uaktualnij odpowiednie bieżące materiały
  tylko w uzgodnionym zakresie, zachowując historyczne dzienniki publikacji.

Ponowny odczyt w chwili przekazania:

| Repozytorium | Gałąź i HEAD | Stan przed dodaniem tego przekazania |
| --- | --- | --- |
| yovoice | `main`, `692aa93ff647f9342f96ad1acb423d1f6037d953` | 313 zmienionych/nowych ścieżek: 133 śledzone, 180 nieśledzonych; `pubspec.yaml` nadal `2.0.0+23` |
| yovoice-website | `main`, `975e5c6f27cf59024ba2c3aa3cb41986fded373b` | 25 ścieżek: 19 śledzonych, 6 nieśledzonych |

Te liczby to migawka, nie lista plików do bezwarunkowego commitowania. Obejmują
pracę Claude'a, Codex i inne zastane zasoby. Sprawdź ponownie stan oraz aktywność
innych zadań przed pierwszą edycją. Zachowaj wszystkie zmiany, także `.env`,
wygenerowane grafiki, referencje i pliki nieśledzone. Nie drukuj wartości
sekretów, nie dołączaj ich do promptów/raportów i nie commituj ich przypadkiem.

Nigdy nie wykonuj `git reset --hard`, `git clean`, wymuszonego checkoutu,
force-pusha ani automatycznego odrzucania/stashowania cudzych zmian. Nie
nadpisuj archiwów i starych buildów. Jeśli równoległa praca nachodzi na Twoje
pliki, najpierw ustal właściciela zmiany i bezpieczny sposób integracji.

Projekt pracuje bezpośrednio na `main`, bez automatycznych PR. Zgodnie z
polityką odczytaj stan i wykonaj bezpieczne `git pull --ff-only origin main`
przed implementacją; konfliktu z brudnym drzewem nie rozwiązuj jego kasowaniem.
Ostatni nocny pull był „Already up to date”; nie jest to obecne sprawdzenie
zdalnego repo. Commit/push wykonuje tylko główny agent po wymaganych kontrolach.

## 2. Obowiązkowe źródła przed kontynuacją

W obu projektach przeczytaj `AGENTS.md` i `CLAUDE.md`; w stronie także README
i odpowiednie lokalne przewodniki z `node_modules/next/dist/docs/`, zanim
zmienisz kod Next.js. Stara ścieżka strony z kontem `kamiljaguszewski` w
aplikacyjnym CLAUDE.md jest historyczna — aktualna ścieżka jest powyżej.

W aplikacji przeczytaj w pierwszej kolejności:

1. `docs/Vision.md`, `docs/Architecture.md`, aktualne sekcje `docs/Roadmap.md`.
2. Całe `docs/Servers.md` oraz oryginalny prompt właściciela:
   `/Users/kamil/.codex/attachments/938f5d13-4b30-4160-9c2f-85d9c9506d64/pasted-text.txt`.
3. `docs/Sessions/2026-09-11-servers-runtime-and-mapping.md` i
   `docs/Sessions/2026-09-10-claude-integration.md`.
4. `docs/agent_handoffs/2026-09-11-approved-home-moments-reels.md` — wszystkie
   trzy kierunki są już zaakceptowane, nie pytaj ponownie o ten sam projekt.
5. `docs/SECURITY.md`, `docs/TESTING.md`, `docs/DEPLOYMENT.md`, `docs/Bugs.md`,
   właściwe dokumenty domenowe i ADR-173, ADR-174 z późniejszym doprecyzowaniem
   terminalnego usuwania oraz ADR-175 w `docs/Decisions.md`.
6. `docs/AI_TEAM.md` i istniejące definicje specjalistów w `.claude/agents/`.

Dokumenty zawierają kolejne historyczne checkpointy: najnowszy pełny backend
to **1817**, nie 1580/1744/1772; najnowszy Flutter to **3686**, nie 3289/3604.
Starsze opisy wydań 19–23 nie dowodzą dostępności nowej wersji. Przy rozbieżności
sprawdź kod, logi i datę — nie zmieniaj historii, aby udawała aktualny stan.

Stosuj wymagane przez AGENTS komórki review: właściciel implementacji,
niezależna QA i read-only Principal; UI dodatkowo design/visual/accessibility;
uprawnienia/migracja/media/role/limity dodatkowo backend/security i niezależny
Adversarial; realtime także voice/audio oraz reliability; release także
DevOps i dokumentacja. Rozdzielaj konkretne niezależne zakresy i unikaj
równoczesnych edycji tych samych plików. Nie uruchamiaj całej listy ról bez
zadania. Główny agent odpowiada za integrację i weryfikację wyników.

## 3. Co faktycznie wykonano lokalnie

**Żadnego commitu, pusha, deployu, migracji/aktywacji produkcyjnej, uploadu do
sklepów, zmiany grup testerów ani maila nie wykonano w tej integracji nocnej
ani podczas przygotowania przekazania.** Starsze opublikowane buildy istnieją,
ale nie zawierają tego niezatwierdzonego drzewa.

### Poprawki Claude'a i zaakceptowany Home / Voice / Reels

- Reels: połączenie autoodtwarzania i feedu własnego autora z backendem,
  rzeczywiste postępy odtwarzania zamiast „obejrzano przy montowaniu”, ranking,
  caught-up/replay, ograniczone inline grants, cache przypisany do konta,
  ogrzewanie sąsiada i odnowienie wygasających grantów.
- GIF-y: rzeczywiste wysyłanie kanonicznych `{provider,id}` przez istniejące
  serwerowe ścieżki DM/Room/Club, wspólny panel Emoji/GIF, odbiór i ustawienie
  automatycznego ładowania, moderacja/report/block oraz stany błędów/retry.
  **Provider nadal `none`**, więc to nie jest działająca produkcyjna usługa
  GIPHY. Konta/warunki/klucz/live smoke/eksporty/rollout pozostają osobną bramką.
- Klawiatura i kompozytory: dokończona integracja Done/panelu, także w Reels;
  poprawki przepełnień przy dużym tekście. Rzeczywista klawiatura i zachowanie
  systemowe na telefonach nadal wymagają sprawdzenia.
- Home: bardziej kompaktowa tożsamość, prawdziwi znajomi/statusy, wyraźne
  wejście do rozmowy przez prejoin, czytelne nowe treści i zachowane pozostałe
  akcje. Stabilne subskrypcje i jedna grupowana asertywna informacja a11y
  o błędach sekcji zamiast konkurujących komunikatów.
- Voice Moments: jedna czytelna lista kart, odtwarzanie i postęp, like/comment,
  zachowana paginacja/expiry/moderacja. Naprawione wyścigi grantów i konta,
  oznaczanie obejrzenia przed udanym startem, kolejność cleanup i powracanie
  już usuniętego Momentu po spóźnionym odczycie. To nie jest pełnoekranowy feed.
- Reels: immersyjny film nad zachowaną dolną nawigacją, akcje po prawej,
  zgłaszanie pod „…”, czytelne podpisy i linki; zatrzymywanie niewidocznych
  odtwarzaczy i usuwanie prywatnych overlayów po zmianie konta/uprawnień.
- Udostępnianie: kanoniczne `https://app.yovoice.app/?reel=<safe-id>`, bez
  bearer URL, reautoryzacja odbiorcy, obsługa wejścia po logowaniu. Brak
  skonfigurowanych natywnych App Links: link jest drogą webową, nie obietnicą
  automatycznego otwarcia zainstalowanej aplikacji.
- Lokalizacja: GIF-y i nowe interakcje są spięte z katalogami. Ostatni wycinek
  feedu dodał 24 stabilne klucze × 41 dodatkowych katalogów (984 wartości),
  poza granicami EN/PL, oraz ponownie użył istniejących tłumaczeń czasu.
  Razem system ma 43 warianty locale. To nie certyfikat językowy całej aplikacji.

Przy nowych poprawkach od razu aktualizuj lokalizację, w tym dopracowany polski,
nie zostawiaj nowych etykiet wyłącznie po angielsku. Utrzymuj Pearl/dark,
Material 3, aktualne tokeny i brak przechylania ikon na hover. Żadnych fikcyjnych
użytkowników, aktywności czy liczników z makiet w produkcji.

### Serwery — fundament, nie kompletny produkt

- Addytywna fasada Server nad istniejącymi `clubs`/`rooms`; żadnej drugiej
  autorytatywnej kolekcji `servers`, usuwania starych pól czy zmiany historii.
- Wersjonowane modele, tworzenie/struktura/membership/ACL, powiązania kanałów,
  fundament Flutter selector/workspace i lokalna granica Firestore/Storage.
- Held session factories obsługują start, jawny join/token, scope/revisions,
  generation-safe end i cofanie dostępu. Istnieje wewnętrzny bridge konwergencji
  po zmianie ACL/członkostwa/ownership, ale **nie aktywny dispatcher**.
- ADR-174: niepewny wynik usunięcia uczestnika nie daje prawa do ponowienia
  tej samej operacji w żywej generacji ani wydania nowego tokena po upływie
  lease. Bezpieczny recovery wymaga uprawnionego zakończenia całej generacji.
- Terminal cleanup zapisuje pozytywne receipts i ścisły checkpoint przed
  pojedynczym SDK DeleteRoom, potem osobny fenced ACK; retry dotyczy tylko
  niezmiennej starej nazwy RTC. Limit 20 rzeczywistych wywołań SDK i 4 równoległe
  usunięcia na przebieg, bez odziedziczonego roster-fanout/automatycznych retry.
- `functions/servers/migration_plan.js`: czysty deterministyczny raport
  mapowania, **zawsze `applyReady:false`**, bez I/O i operacji modyfikacji.
- Ostatni wycinek `functions/servers/migration_inventory.js`: waliduje jedynie
  dostarczone metadane łańcuchów stron. Club: members/invites/channels;
  Room: roomMembers/participants/messages. Granice 1000 stron, 500 rekordów
  na stronę, 10000 łącznie; ścisłe timestampy/cursory/UTF-8. Brak strony ≠ pusta
  kolekcja. **`fullInventoryComplete:false`, `applyReady:false`, `writeCount:0`
  zawsze**. Digest nie stanowi uprawnienia, anonimizacji ani dowodu kompletności.
  Nie ma collectora, semantycznej migracji, apply, rollback ani aktywacji.

Ponownie potwierdzono w kodzie przy przekazaniu: brak rejestracji fabryk
`servers/` w `functions/index.js`; nowe ekrany są używane tylko wewnątrz
`lib/features/servers`; workspace ma niepodłączone `onInvite`/`channelBuilder`.
Held roots to `preparing/held`; runtime wymaga dokładnie `active/active`.
Nie „naprawiaj” tego przez samo włączenie eksportów albo usunięcie kontroli.

### Strona

Lokalny redesign strony i `/servers`, pięć koncepcji, zachowane `/clubs`
przez redirect, odpowiednie teksty Premium i informacja o planowanym free-20
są przygotowane. Nie opublikowano ich. Copy jasno oznacza moduły jako
opracowywane; `/updates` nie ogłasza nowego builda ani migracji. Historyczny
Build 20 w ledgerze nie jest obecnym wydaniem tej pracy. Przed publikacją
aktualizuj treść zgodnie z tym, co rzeczywiście działa i zostało wydane.

## 4. Co trzeba jeszcze dokończyć — nie redukuj zakresu

Wszystkie pozycje checklisty w `docs/Servers.md` pozostają obowiązkiem odbioru,
nawet jeśli część fundamentu ma już testy. W szczególności:

1. **Globalne podłączenie** selector/hub/workspace do prawdziwej nawigacji,
   zastąpienie widocznego Club słowem Server tam, gdzie uzgodniono; zachowanie
   kontraktów `clubId`, powiadomień, zgód i starych deep linków. Nowe
   `?server=&channel=` reautoryzują, nie migrują ani nie uruchamiają mikrofonu.
2. **Działające kanały i kontrola**: tekst, voice/stage, kategorie, create/
   rename/reorder/archive/delete, invite issue/revoke/preview, role, ban/remove,
   leave i ownership; faktyczne API oraz UI, nie nieaktywne wstawki.
3. **RTC/globalni konsumenci**: dispatcher, rejestracje/aktywacja po zgodzie,
   aktualizacja m.in. `functions/staff/voice_enforcement.js`,
   `functions/livekit/sessions.js`, `functions/achievements/livekit_http.js`
   i wszystkich mirrorów/webhooków/outboxów do server/channel/session.
   Wspólny istniejący koordynator rozmowy i stale dostępny kompaktowy dock;
   jawne źródła mic/camera/screen, cleanup/revocation/reconnect.
4. **Pięć rzeczywistych szablonów**, w kolejności Friends, Community, Podcast,
   Family, Company. Najpierw obejrzyj selector HTML i wszystkie pięć PNG
   w folderze referencji. Nie kopiuj ramek urządzeń i podpisów prezentacji.
   - Friends: różne kanały tekst/głos, obecność, kontekst czatu, wydarzenia RSVP.
   - Community: prawdziwa scena video 16:9, role/audience/chat/moderacja oraz
     odrębny zwykły lounge. Community i Broadcast pozostają różnymi produktami;
     enum `RoomExperience` ma nadal tylko dwie wartości.
   - Podcast: scena audio, kolejka gości, Q&A/votes/On air, program/reminders,
     faktyczne recording → processing → playback → publish i obsługa awarii.
   - Family: prywatne zdjęcia/głosowe wspomnienia, kalendarz/RSVP/reminders,
     współdzielona lista i zachowane check-ins, właściwy transfer właściciela.
   - Company: ograniczone HR/Zarząd, spotkania mic/camera/screen, chat/files,
     trwała współdzielona tablica, kursory i undo tylko własnych operacji.
5. **Moduły trwałe**: events + UTC/IANA timezone i unieważnianie przestarzałych
   reminderów; Q&A/votes; realne recording jobs/egress/callback validation;
   listy; whiteboard; pliki/wspomnienia. Sama obecność SDK egress nie oznacza
   działającego nagrywania. Weryfikuj rzeczywistą konfigurację usług.
6. **Prywatne media**: reservation → upload → probe → finalize → authorized
   read, także range requests → cleanup. Nie publikuj trwałych bearer URL do
   prywatnych plików. Określ realny czas ważności grantów i zachowanie po
   revocation; nie obiecuj zdalnego usunięcia już pobranych bajtów.
7. **Limity**: właściciel zatwierdził **do 20 Serwerów bez Premium**. Rodzina
   pozostaje bezpłatna; istniejące płatne prawa i historyczne dane pozostają.
   Wspólne księgowanie legacy/new przy create/delete/transfer/migrate; nie
   licz kanałów jako osobnych serwerów i nie gub alokacji po dodaniu `clubId`.
   Family transfer wymaga rezerwacji obecnego właściciela, bez zmiany IDs.
8. **Pełna bezpieczna migracja**: collector roots i wszystkich powiązanych
   danych/media generations/mirrors/bans/follows/allocations, wersjonowany
   manifest, source preconditions, konflikty/privaty/quoty, resumable apply,
   reconcile i bezpieczny rollback. Odkładaj aktywne sesje i sprawdzaj ponownie
   idle/version przy transakcji; nie kończ ich siłą, żeby migrować.
   Zachowaj historySource/IDs i jednego writera; transient listener nie staje
   się trwałym memberem/adminem. Usuń lub wygaś stare leases/upload tokens
   przed cutover. Nie zdejmuj wersji ani nie przywracaj szerokich legacy Rules
   nad nowymi prywatnymi danymi jako „rollback”. Produkcyjne wykonanie osobno.
9. **Kompatybilność**: stare szerokie zapytania kanałów nie zostaną automatycznie
   przefiltrowane przez Rules. Potrzebny prawdziwy capability/min-client gate,
   zachowanie starych spaces i kontrolowane idle upgrade. Nie osłabiaj ACL,
   żeby stare query przeszło. Reautoryzuj replay tokenów i wszystkich writerów.
10. **Wdrożeniowe zależności Reels/GIF**: rzeczywisty index own-feed READY,
    TTL `reelViews.expiresAt` i `gifQueryCache.expiresAt`, nigdy TTL na
    `gifAssets`; aktywny provider, klucz i smoke według ADR-173/DEPLOYMENT.
    GIPHY bytes są hotlinkowane z CDN, nie kopiowane do Storage; uwzględnij
    prywatność i zgodę. Retry GIF w bieżącym ekranie nie jest trwałym outboxem
    po ubiciu procesu. Skuteczność rankingu nie była oceniona na realnym ruchu.
11. **Otwarte przypadki testerów**: odtwórz i zweryfikuj DM text/voice/photo/
    video i aparat vs biblioteka, zakładki zapisanych mediów, awatary w listach/
    wyszukiwaniu/profilu, single-flight otwarcia profilu, znajomi, rozmowy 1:1
    audio/video Android↔Android i Android↔iOS, room prejoin i czat na dole,
    Voice Moments, Reels authorship/like/comments/share/report oraz composer
    crop/music/filters/text/links. Historyczne zgłoszenie nie dowodzi, że dziś
    błąd nadal istnieje — sprawdź kod i rzeczywisty scenariusz. Nie uznawaj też,
    że naprawiono go tylko dlatego, że są testy komponentu.
12. **Odbiór pozostałego UI i bezpieczeństwa**: banner nieweryfikowanego maila,
    błędny kod → czerwony krzyżyk i wyczyszczenie cyfr, nawigacja/gest powrotu,
    animowane górne powiadomienia, kompaktowy profil/odznaki/dock, obie palety,
    a11y/RTL/lokalizacja i uprawnienia OS/browser. Nie wymuszaj ponownie
    przyznanych uprawnień bez potrzeby, ale nie obchodź decyzji systemowych.
    Zweryfikuj istniejący zakres sonic/tutorial/branding z Roadmap zamiast
    samodzielnie usuwać lub projektować ponownie zaakceptowane elementy.

Nie składaj obietnic „200% bezpieczeństwa”, identycznej niezawodności Instagrama,
zgodności z każdą historyczną wersją bez capability gate ani braku spamu.
Wykonuj mierzalne testy, naprawiaj konkretne przyczyny i ujawniaj ograniczenia.

## 5. Wyniki, które można wykorzystać jako bazę

To ostatnie **nocne lokalne** wyniki. Przy przekazaniu ponownie przeczytano
logi i sprawdzono wybrane hashe, ale nie uruchamiano od nowa pełnych testów
ani kompilacji. Po dalszych zmianach potrzebne są nowe bramki na finalnym drzewie.

| Kategoria | Ostatni wynik | Granica dowodu |
| --- | --- | --- |
| Pełny Flutter | **3686/3686**, 0 fail/skip, 4m28s | Widget/unit/controlled transport, nie realny telefon |
| Analiza całego Dart | **No issues found** | Nie dowodzi działania usług |
| Pełny Functions | **1817/1817**, 120 suites, 127 plików, 0 fail/skip/cancel/todo, 341.642s | Świeże lokalne demo emulatory, Node 22.23.2 |
| Firestore Rules | **564/564** | Oddzielny wcześniejszy gate; pliki bez zmian przy nocnym final gate |
| Storage Rules | **67/67** | Jak wyżej |
| Family media | **11/11** | Jak wyżej |
| Dodatkowe Servers Rules | **31/31** | Oddzielna zgodna konfiguracja projektu emulatora |
| Web release compile | PASS, 80.9s | Izolowany output, bez Hosting |
| iOS release compile | PASS, 172.1s, unsigned arm64 Runner.app 89 MB | Bez archive/IPA/install/upload, nadal 2.0.0 (23) |
| Android release APK compile | PASS, 5m31s, 3 ABI, sprawdzony podpis v2 | Bez AAB/install/Play, nadal 2.0.0 (23) |
| Produkcyjne dependency audits | Functions i Rules harness: 0 znanych vulnerabilities | Nie audyt całej aplikacji ani gwarancja bezpieczeństwa |
| Website | Odnotowano 98 testów, lint i build 46 routes, lokalny render review | Nie publikacja i nie odbiór produkcji |

Focused wyniki **nakładają się** na powyższe pełne zestawy; nie dodawaj ich
do sumy: Home 326, Voice 132, Reels/Share 76, lokalizacja 748, runtime/bridge
128 + osobny root terminal QA 11, mapping 33, inventory/mapping 78 = 18 nowych
autora + 27 niezależnych + 33 mapowania. Nowe 45 inventory jest już w 1817.

Pierwszy późniejszy Flutter miał 3563 PASS / 41 FAIL w pięciu dawnych fixture/
layout suites Voice. Przyczyny jawnie poprawiono, nie wyciszono; zachowano
assertions prywatności/paging/retry/engagement. Następny pełny gate to 3686 PASS.
Nie przywracaj starych założeń layoutu ani nie kasuj testów tylko dla zieleni.

Wizualnie oglądano realne kontrolowane rendery Flutter Dark/Pearl,
wąskie/szerokie i 200% tekstu; istnieją pełne raporty z ograniczeniami. Nie
wszystkie setki wygenerowanych PNG oglądano niezależnie. Lokalizacja: 12
DE/NL/AR capture sprawdzonych; to nie native-speaker review wszystkich locale.
Brak nowych fizycznych testów VoiceOver/TalkBack, połączeń dwóch urządzeń,
LiveKit Cloud/egress, odbioru uploadu sklepów i dostępności testerom.

### Główne dowody i dokładne komendy

- `/tmp/yovoice-full-gate-20260911.pe6fZn/flutter-final.log`
  oraz `analyze-final.log`; komenda testów `flutter test --no-pub --reporter expanded`.
- `/tmp/yovoice-inventory-gate-20260911.odBTMR/gate-summary.md` — najnowsze
  pełne Functions; dokładne env/komenda/config, log, before/after manifesty.
- `/tmp/yovoice-inventory-independent-qa-20260911.DHYpiV/gate-summary.md`.
- `/tmp/yovoice-clean-backend-gate-20260911.6upGkR/gate-summary.md` — pełne
  Rules i starsze Functions 1744; Rules nie uruchamiano ponownie w gate 1817.
- `/tmp/yovoice-terminal-full-backend-20260911.LXGLAq/gate-summary.md` —
  historyczny pełny backend 1772 przed trzema plikami inventory.
- `/tmp/yovoice-ios-compile-preflight-20260911.ScpcBz/gate-summary.md`.
- `/tmp/yovoice-android-compile-preflight-20260911.skQLQ5/gate-summary.md`.
- `/tmp/yovoice-feed-localization-final-handoff-20260911.md` oraz
  `/tmp/yovoice-feed-locale-review.2AXmhI/report.md`.
- `/tmp/yovoice-website-release-copy.OQdRG7/report.md` — niezależny read-only
  przegląd twierdzeń o dostępności; nie jest testem funkcjonalnym strony.
- `test/.screenshots/visual-final-review.md` i sesje w `docs/Sessions/`.

Logi w `/tmp` mogą zniknąć po restarcie. Jeśli dowód jest niedostępny, oznacz
go jako historycznie odnotowany i uruchom potrzebne sprawdzenie ponownie;
nie wymyślaj logów ani wyników. Zachowaj istotne nowe evidence bez sekretów.

Najważniejsze hashe sprawdzone ponownie przy przekazaniu:

| Plik | SHA-256 |
| --- | --- |
| `functions/servers/migration_inventory.js` | `20e3a99a682875d48cd975510b06d307be4a5d73bb24740305aafd714b787f0e` |
| `functions/servers/session_livekit.js` | `658bcdb545e0c39169d4a03c67d431f9bc8abbef3f6239ea36bc38bad5e610e2` |
| `functions/servers/session_control.js` | `97b28be8d966e605c5867819dc7e9655545aad732573b3a8a3107b2519b142ed` |
| `lib/features/moments/presentation/widgets/moments_feed_view.dart` | `b00031bc8d394951887ccf7934260aa40df67fa8327ceb8e98e97f7532dda624` |
| `lib/features/reels/presentation/widgets/reel_card.dart` | `8a347c0bf10808bc7bfbe1b82bf11d8838dcfd9977d6bd9fb4482fd25c543db2` |

Nocny 290-file backend manifest before/after:
`bc39b5ab80d609e28e9a1cff7faa87f9f0ce0ea4b047ac2b93d13f86b8ee5ed2`.
To fingerprint tamtego gate, nie certyfikacja wszystkich plików aktualnego drzewa.

## 6. Środowisko i pułapki techniczne

- Flutter `/opt/homebrew/bin/flutter`, ostatnio 3.44.6 / Dart 3.12.2.
- Node dla backendu:
  `/Users/kamil/.npm/_npx/52027bd8fc0022aa/node_modules/node/bin/node`, 22.23.2.
  Domyślny Node 26 nie jest równoważnym środowiskiem; sprawdź wersję i obecność.
- Pełne backend tests uruchamiaj serialnie (`--test-concurrency=1`) jako
  **pierwszy** przebieg na świeżych lokalnych demo fixture. Ostatni używał
  Firestore 8086 / Auth 9097 / Storage 9197 / hub 4412, explicit
  `demo-yovoice.appspot.com`. Sprawdź wolne porty, nie wyłączaj cudzych emulatorów.
  Brak bucket i ponowne użycie brudnych fixtures dawały pozorne awarie.
  Cross-service Storage wymaga zgodności projektu startującego emulatora,
  nie tylko client project override. Pełną receptę skopiuj z gate-summary.
- Nocne własne build/test processes zakończono, własny hub zatrzymano. Przy
  przekazaniu wszyscy trzej dotychczasowi specjaliści zgłosili completed.
  Istnieją inne procesy użytkownika/emulatory; nie zabijaj zbiorczo Node/Java.
- Mac był zablokowany przy nocnych próbach UI. **Przy przekazaniu getState
  sterowania ekranem ponownie zadziałał i zwrócił aplikacje, m.in. Simulator**.
  Nie powtarzaj więc bez sprawdzenia, że nadal jest zablokowany. Nie otwierano
  jednak teraz ekranów aplikacji/sklepów i nie wykonano testu na urządzeniu.
  Preferuj sterowanie ekranem zgodnie z prośbą właściciela; login/2FA może
  wymagać jego działania. Nie obchodź blokady systemu.
- Natywne preflighty wykonano na checksum-identycznej kopii
  `/tmp/yovoice-ios-isolated-20260911.HpBM2A`. Flutter iOS helper usuwa
  rekurencyjnie atrybuty Finder/provenance nawet bez codesigning; nie uruchamiaj
  tego bezmyślnie nad oryginalnym katalogiem z archiwami użytkownika.
- Android Gradle plan zawiera automatyczny upload mapowania Crashlytics.
  W compile-only preflight wyłączono tylko ten task przez CLI; nie zmieniono
  konfiguracji. Tymczasową kopię zaszyfrowanego klucza usunięto; oryginalny
  keystore został nienaruszony. Nie zapisuj haseł do logów ani repo.
- **`ios/ExportOptionsUpload.plist` ma `destination=upload`.** Polecenie
  eksportu może naprawdę wysłać aplikację, zamiast utworzyć nowy lokalny IPA.
  Po niejednoznacznej odpowiedzi najpierw sprawdź App Store Connect; nie
  ponawiaj na ślepo. Stary IPA może pozostać na dysku i mieć inny numer.
- Oryginalne AAB/archive z 8 września to **23 bez tych zmian**. Izolowane
  preflight APK/Runner też celowo mają 23. Nie uploaduj ich i nie uznawaj za
  nowy release. Odczytuj numer i identyfikator z gotowego artifactu.
- Push aplikacji nie wdraża sam backendu/Hosting. **Push strony na main może
  uruchomić produkcyjne Vercel**, więc nie traktuj go jak niewinnego backupu.

## 7. Zalecana kolejność wznowienia

1. Potwierdź aktualny stan obu drzew, aktywnych zadań i dostęp do UI. Przeczytaj
   powyższe źródła. Zapisz checklistę „w kodzie / podłączone / testowane /
   na urządzeniu / wdrożone”; nie oznaczaj modułu Done po dodaniu samego pliku.
2. Zamknij plan integracji Serwerów: API, shared quotas, katalog/restricted ACL,
   globalni konsumenci RTC i lifecycle, moduły oraz migracja. Korzystaj z
   przetestowanych fundamentów; nie osłabiaj held boundary i ADR-174/175.
3. Dokończaj pionowe, działające wycinki z niezależną QA/review i aktualizacją
   dokumentacji/lokalizacji. Wszystkie pięć typów musi przejść swoje acceptance.
   Równolegle można przygotować bezpieczne narzędzia migracyjne i backend
   w środowisku testowym, bez działania na produkcyjnych danych.
4. Zweryfikuj istniejące krytyczne regresje testerów i nowy Home/Voice/Reels
   w prawdziwej aplikacji, z pomiarami cold/warm start, startu mediów,
   wysyłki wiadomości, czasu połączenia, liczby listenerów/decoderów i pamięci.
   Nie dodawaj agresywnych retry, które multiplikują zapytania/opóźnienia.
5. Przeprowadź realne testy dwóch kont na iOS i Androidzie: oba kierunki
   połączeń i mediów, starszy/nowy zgodny klient, wolna sieć/offline/reconnect,
   deny permission, foreground/background, wyjście/koniec/ban/demotion,
   cleanup mic/camera i wygasanie dostępu. Jeśli brak urządzenia/usługi,
   zapisz konkretny UNVERIFIED i potrzebę użytkownika; nie udawaj sukcesu.
6. Po zamrożeniu finalnej rewizji uruchom świeże pełne testy Flutter/Functions/
   Rules, analizę i odpowiednie audyty oraz buildy. Dla UI obejrzyj actual
   renders 320/390/768/1100/1440/1920, 200% tekst, PL/EN/RTL, oba motywy,
   keyboard/safe area, empty/loading/denied/error/content. Uzyskaj wszystkie
   wymagane read-only review i usuń potwierdzone release blockers.
7. Zaktualizuj stronę, privacy, release notes i `updates` do prawdziwego zakresu.
   Przed realnym recording skoryguj istniejące twierdzenie privacy, że audio
   live-room nie jest nagrywane; opisz faktyczną zgodę, retention/audience/
   deletion i provider. Nie ogłaszaj jeszcze gotowego builda przed dystrybucją.
8. Sprawdź pełną zgodę wydaniową. Gdy potrzebny produkcyjny backend/aktywacja/
   migracja, przedstaw precyzyjny plan, raport dry-run i rollback oraz uzyskaj
   osobne wymagane potwierdzenie. To nie powód do pomijania funkcji lub kontroli.

## 8. Wydanie dla testerów — dopiero po wszystkich bramkach

1. Zweryfikuj aktualne wersje/build numbers **w obu sklepach**, nie z tego
   promptu. Nie zakładaj automatycznie, że następny wolny numer to 24.
2. Przygotuj jasną finalną rewizję i kontrolowany zakres commitu bez sekretów
   i obcych materiałów. Commit/push zgodnie z polityką, obserwuj CI na tej
   rewizji i popraw failure; nie deklaruj, że push to deploy. Uważaj na Vercel.
3. W zatwierdzonym zakresie wdrażaj kompatybilny backend/Rules/indexes przed
   klientem zależnym od nich; sprawdź actual exports, READY indexes/TTL,
   uprawnienia, monitoring/rollback i served Web bytes. Produkcyjna migracja
   oraz aktywacja mają własne zatwierdzenie i kontrolę idle/source generation.
4. Zbuduj nowe właściwie podpisane AAB i iOS archive/export z ustalonym numerem,
   zweryfikuj package/bundle ID `app.yovoice`, wersję, build i hashe artifacts.
   Zachowaj stare wydania do porównania/rollbacku. Nie wysyłaj preflight23.
5. Upload i dystrybucja tylko istniejącym testerom. Osobno potwierdź Apple
   processing/Beta App Review/grupy i Play processing/track/grupy. Historyczne
   15 testerów Androida to punkt odniesienia, nie aktualna lista; odczytaj
   rzeczywiste przypisania, nie duplikuj grup i nie usuwaj testerów Apple.
   Nie myl internal/external Apple i nie eskaluj niepotrzebnie ich uprawnień.
6. Zweryfikuj, że tester może rzeczywiście pobrać tę konkretną nową wersję
   na obu platformach. „Uploaded”/„Processing” nie znaczy „Available”.
   Jeśli konieczne logowanie/2FA/review, podaj dokładną potrzebę bez obietnicy
   samodzielnego obejścia. Nie wysyłaj podwójnie po niejednoznacznym uploadzie.
7. Dopiero po dostępności wyślij istniejącej, aktualnie odczytanej i
   pozbawionej duplikatów liście testerów krótką wiadomość **po angielsku,
   bez linków i załączników**, np. po wstawieniu rzeczywiście wydanej wersji:

   Subject: YO Voice update is ready

   A new YO Voice update is now available for testing. Please update the app
   in TestFlight or Google Play. Thank you for your feedback!

   Nie wpisuj adresów testerów do repo/promptu. Sprawdź istniejący dziennik
   wysyłek, żeby uniknąć duplikatów i zbędnych wiadomości obok automatycznych
   powiadomień sklepu. Użyj zweryfikowanego kanału nadawcy. Krótszy tekst/brak
   linków nie gwarantuje ominięcia spamu/blokady; po błędzie sprawdź przyczynę,
   nie wysyłaj wielokrotnie. Nie obiecuj dostarczalności bez dowodu.
8. Zapisz w dokumentacji rewizję, finalne testy, hashe, osobny status Apple/
   Android/website/backend/migracji oraz wynik powiadomień. Właściciel chce
   wiedzieć, co faktycznie otrzymali testerzy, a nie tylko co skompilowano.

## Komunikacja i ostatnia granica

Pisz do właściciela po polsku, rzeczowo i bez ciągłych mikroaktualizacji.
Nie obiecuj konkretnej godziny ukończenia bez podstaw. Gdy brakuje decyzji,
urządzenia lub autoryzacji, wskaż konkretny blocker i kontynuuj inne bezpieczne
prace, nie poszerzając samodzielnie uprawnień. Nie kupuj narzędzi, kont ani
resetów limitu. Ten prompt upoważnia do kontynuacji już przyjętego zakresu,
nie do wysyłania kodu/danych na nowe zewnętrzne usługi.

Zakończ dopiero po rzeczywistym dokończeniu i zweryfikowanym wydaniu obu grupom
testerów albo uczciwie zgłoś nierozwiązywalną bez właściciela przeszkodę.
Nigdy nie pisz „wszystko działa” tylko na podstawie zielonych testów i buildu.
