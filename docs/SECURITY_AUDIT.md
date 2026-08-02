# YoVoice — audyt bezpieczeństwa

Zakres: `firestore.rules`, `storage.rules`, `functions/**`, warstwa danych w `lib/**/data`.
Commit: `34144d3` (Big changes, admin room etc.)

**Uwaga wstępna:** repozytorium jest rozjechane z produkcją (patrz #13). Poniższe ustalenia
dotyczą kodu w repo. Zanim cokolwiek wdrożysz, sprawdź, co faktycznie jest zdeployowane.

---

## Podsumowanie

| Priorytet | Liczba | Czego dotyczy |
|---|---|---|
| Krytyczne | 3 | przejęcie pokoju, przejęcie klubu, obejście całej moderacji głosu |
| Wysokie | 3 | samodzielna promocja na speakera, bootstrap superadmina, brak walidacji pól |
| Średnie | 6 | manipulacja licznikami, wymuszona znajomość, wycieki, martwe reguły |
| Bug (nie security) | 1 | kontrakt klient ↔ Cloud Function się nie zgadza |

Dobre wiadomości na start: sekrety LiveKit są w Secret Managerze, nie w kodzie. Wszystkie
funkcje admina mają poprawnie nałożone `requireRole`. Role czytane są z custom claims
(`auth.token.role`), a nie z dokumentu użytkownika — to odcina najczęstszą ścieżkę
eskalacji uprawnień. Fundament jest sensowny, dziury są punktowe.

---

## KRYTYCZNE

### 1. Token LiveKit nadaje uprawnienia, o które poprosi klient

`functions/livekit/token.js:71-84`

```js
const canPublish = request.data?.canPublish !== false;
const canSubscribe = request.data?.canSubscribe !== false;
const canPublishData = request.data?.canPublishData !== false;
const hidden = request.data?.hidden === true;
const recorder = request.data?.recorder === true;
```

Funkcja sprawdza wyłącznie, czy użytkownik jest zalogowany. Nie sprawdza, czy pokój
istnieje, czy wywołujący jest jego uczestnikiem, ani jaką ma w nim rolę. `roomName`
przychodzi z requestu i nie jest z niczym konfrontowany.

Co można zrobić dowolnym kontem:

- dołączyć do **każdego** pokoju, znając jego identyfikator, bez wpisu w Firestore,
- ustawić `canPublish: true` w Broadcast Roomie i mówić z pominięciem kolejki Raise Hand
  i zgody hosta,
- ustawić `hidden: true` i słuchać niewidzialnie — nie pojawiając się na liście uczestników,
- wrócić natychmiast po wyrzuceniu przez moderatora,
- ustawić `recorder: true`.

To unieważnia całą moderację opisaną w `docs/ROOMS_REBUILD_PLAN.md`. Mute, remove,
move-to-audience i kolejka Raise Hand działają na Firestore, ale dźwięk leci przez LiveKit,
a LiveKit ufa temu, co klient sobie zażyczył w tokenie. Wyciszony użytkownik po prostu
prosi o nowy token.

**Poprawka.** Uprawnienia muszą być wyliczone na serwerze:

```js
const roomSnapshot = await db.collection("rooms").doc(roomId).get();
if (!roomSnapshot.exists) {
  throw new HttpsError("not-found", "Room does not exist.");
}
const room = roomSnapshot.data();

const participantSnapshot = await roomSnapshot.ref
  .collection("participants").doc(authenticatedUser.uid).get();
if (!participantSnapshot.exists) {
  throw new HttpsError("permission-denied", "You are not a participant of this room.");
}
const participant = participantSnapshot.data();

if (participant.isBanned === true) {
  throw new HttpsError("permission-denied", "You were removed from this room.");
}

const isHost = room.hostId === authenticatedUser.uid;
const isSpeaker = participant.role === "speaker" || participant.role === "moderator";

const canPublish = (isHost || isSpeaker) && participant.isMuted !== true;
const canSubscribe = true;
const canPublishData = true;
const hidden = false;   // nigdy z klienta
const recorder = false; // nigdy z klienta
```

Nazwa pokoju w LiveKit powinna być wyprowadzona z `roomId`, nie przyjęta jako dowolny string.

Dodatkowo: gdy moderator wycisza uczestnika, trzeba unieważnić jego aktywne uprawnienia
przez LiveKit Server API (`RoomServiceClient.updateParticipant`), bo token już wydany
zachowuje ważność.

---

### 2. Dowolny użytkownik może zostać właścicielem dowolnego klubu

`firestore.rules:174-181`

```
allow create: if isSignedIn() &&
    request.auth.uid == memberId &&
    (
      get(/databases/$(database)/documents/clubs/$(clubId)/invites/$(memberId)).data.inviteeId == memberId ||
      request.resource.data.role == 'owner'
    );
```

Drugi warunek istnieje po to, żeby `createClub()` mógł zapisać dokument członka-właściciela
(`club_service.dart:123`). Ale nie jest w żaden sposób związany z tym, kto faktycznie założył
klub. Wystarczy utworzyć `/clubs/{dowolnyKlub}/members/{swojeUid}` z polem `role: 'owner'`.

Skutek: `clubRole()` zwraca `owner`, `canManageClub()` przepuszcza, `clubRolePower()` daje 60 —
czyli maksimum. Atakujący dostaje prawo do edycji klubu, kasowania członków, zarządzania
kanałami i czytania wszystkich wiadomości w kanałach. Cały system RBAC ze Stage 9 obchodzi
się jednym zapisem.

**Poprawka:**

```
allow create: if isSignedIn() &&
    request.auth.uid == memberId &&
    (
      get(/databases/$(database)/documents/clubs/$(clubId)/invites/$(memberId)).data.inviteeId == memberId ||
      (
        request.resource.data.role == 'owner' &&
        get(/databases/$(database)/documents/clubs/$(clubId)).data.ownerId == request.auth.uid
      )
    );
```

---

### 3. Dowolny uczestnik może nadpisać cały dokument pokoju

`firestore.rules:252-266`

```
allow update: if isSignedIn() &&
    (
      resource.data.hostId == request.auth.uid ||
      isRoomParticipant(roomId) ||
      isRoomMember(roomId) ||
      ( ... )
    );
```

Gałęzie `isRoomParticipant` i `isRoomMember` nie ograniczają, **które pola** wolno zmienić.
Precyzyjna gałąź z `hasOnly(['participantCount', 'updatedAt'])` poniżej jest martwa — dwie
szersze reguły przed nią i tak przepuszczą wszystko.

A uczestnikiem zostaje się trywialnie: `/rooms/{roomId}/participants/{swojeUid}` wymaga
wyłącznie `request.auth.uid == participantId` (linia 272).

Ścieżka ataku: dołącz do dowolnego pokoju → ustaw `hostId` na swoje uid → jesteś hostem.
Możesz wyrzucać uczestników, wyciszać, kasować pokój. Możesz też podmienić tytuł, opis
i obrazek cudzego pokoju.

**Poprawka** — rozbić na host i nie-hosta:

```
allow update: if isSignedIn() && (
  resource.data.hostId == request.auth.uid
    ? request.resource.data.hostId == resource.data.hostId
    : request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['participantCount', 'speakerCount', 'updatedAt'])
);
```

Host też nie powinien móc zmienić `hostId` bezpośrednio — przekazanie własności należy
przenieść do Cloud Function.

---

## WYSOKIE

### 4. Uczestnik pokoju sam nadaje sobie rolę

`firestore.rules:270-277`

```
match /participants/{participantId} {
  allow read: if isSignedIn();
  allow create, update, delete: if isSignedIn() &&
      (request.auth.uid == participantId || isRoomHost(roomId));
}
```

Zero walidacji pól. Użytkownik zapisuje sobie `role: 'speaker'`, `isMuted: false`,
`isModerator: true`. W połączeniu z #1 (token nie sprawdza roli) daje to pełne obejście.
Nawet po naprawie #1 ten zapis pozostaje dziurą, bo poprawiony token będzie czytał
właśnie to pole.

**Poprawka:** rozdzielić, kto co może zmienić:

```
allow create: if request.auth.uid == participantId &&
    request.resource.data.userId == request.auth.uid &&
    request.resource.data.role == 'listener' &&
    request.resource.data.isMuted == true;

allow update: if
    (request.auth.uid == participantId &&
     request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['isSpeaking', 'updatedAt', 'lastSeenAt'])) ||
    isRoomHost(roomId);
```

Promocja na speakera powinna iść przez hosta albo przez Cloud Function.

---

### 5. `bootstrapSuperAdmin` nie sprawdza, czy adres e-mail jest zweryfikowany

`functions/admin/users.js:78-86`

```js
const callerEmail = normalizeEmail(authenticatedUser.token.email);
if (callerEmail !== SUPER_ADMIN_EMAIL) { throw ... }
```

Jeśli w projekcie włączone jest logowanie e-mail/hasło, ktoś może zarejestrować konto na
`grieferxgriefer@gmail.com` bez potwierdzania skrzynki i wywołać tę funkcję, dostając rolę
`superAdmin`. Przez Google Sign-In adres jest weryfikowany, ale reguła musi to wymuszać
niezależnie od tego, jakie metody logowania są aktywne dziś.

**Poprawka:**

```js
if (authenticatedUser.token.email_verified !== true) {
  throw new HttpsError("permission-denied", "Verify your e-mail address first.");
}
```

Warto też, żeby funkcja odmawiała działania, gdy superadmin już istnieje.

---

### 6. Dokument użytkownika bez walidacji pól

`firestore.rules:106-109`

```
match /users/{userId} {
  allow read: if isSignedIn();
  allow create, update: if isOwner(userId);
```

Użytkownik może wpisać w swój dokument dowolne pole o dowolnej wartości — w tym `role`,
`messageCount`, `unlockedTitleIds`, liczniki osiągnięć czy status weryfikacji.

Funkcje admina czytają rolę z custom claims, więc realnej eskalacji uprawnień tu nie ma —
i to jest zasługa poprawnej architektury. Ale:

- jeśli klient gdziekolwiek pokazuje UI na podstawie `user.role` z Firestore, atakujący
  zobaczy panel admina (kosmetycznie — wywołania i tak odbiją się od Functions),
- cały system osiągnięć ze Stage 5.4 jest do sfałszowania jednym zapisem,
- `allow read: if isSignedIn()` udostępnia każdemu zalogowanemu wszystkie dokumenty
  użytkowników. Sprawdź, czy nie trzymasz tam adresów e-mail, tokenów FCM ani danych
  z providera logowania.

**Poprawka:** wypisać dozwolone pola jawnie i zabronić zmiany pól kontrolowanych serwerowo:

```
allow update: if isOwner(userId) &&
    request.resource.data.diff(resource.data).affectedKeys()
      .hasOnly(['displayName', 'username', 'bio', 'photoUrl',
                'selectedTitleId', 'language', 'updatedAt']);
```

Liczniki i osiągnięcia przenieść do Cloud Function albo triggera Firestore.

---

## ŚREDNIE

### 7. Liczniki polubień do dowolnej podmiany

`firestore.rules:306-308`

```
allow update: if isSignedIn() &&
    (resource.data.authorId == request.auth.uid ||
     request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['likeCount', 'commentCount', 'updatedAt']));
```

Ograniczenie dotyczy tylko tego, *które* pola, nie *jakie wartości*. Każdy może ustawić
`likeCount` na dowolną liczbę w cudzym momencie — w górę lub w dół — bez związku
z podkolekcją `likes`. Jeśli Discover sortuje po popularności, feed da się dowolnie ustawić.

**Poprawka:** wymusić inkrement o 1 i zgodność z faktycznym zapisem w `likes`, albo
przenieść liczniki do triggera `onDocumentWritten` na `/voiceMoments/{id}/likes/{uid}`.
To drugie jest odporniejsze.

### 8. Wymuszona znajomość

`firestore.rules:121-125`

```
match /friends/{friendId} {
  allow create, update, delete: if isOneOfUsers(userId, friendId) && userId != friendId;
}
```

Warunek pozwala pisać w cudzej podkolekcji znajomych — potrzebne przy obustronnym zapisie
po akceptacji zaproszenia, ale nigdzie nie sprawdza, czy zaproszenie w ogóle istniało.
Dowolny użytkownik może dopisać się do listy znajomych dowolnej osoby, a także **usunąć**
cudze znajomości.

**Poprawka:** przenieść akceptację zaproszenia do Cloud Function, która zapisuje obie strony
atomowo, i zablokować bezpośredni zapis z klienta.

### 9. Wiadomości w pokojach czytelne dla każdego

`firestore.rules:290-291` — `allow read: if isSignedIn()` bez sprawdzenia, czy wywołujący
jest w pokoju. Do zaakceptowania przy pokojach publicznych, ale jeśli planujesz pokoje
prywatne lub klubowe, to wyciek. Zmienić na `isRoomParticipant(roomId) || isRoomMember(roomId)`.

### 10. Kolekcje używane w kodzie, dla których nie ma reguł

Kod odwołuje się do kolekcji nieobecnych w `firestore.rules`:

| Kolekcja | Wystąpień w `lib/` |
|---|---|
| `sentFriendRequests` | 5 |
| `following` | 5 |
| `handRequests` | 4 |
| `followers` | 3 |

Domyślnie Firestore odmawia dostępu do niedopasowanych ścieżek, więc albo te funkcje
nie działają, albo reguły na produkcji różnią się od pliku w repo. `handRequests` to
kolejka Raise Hand dla Broadcast Roomów — czyli kluczowy element Stage 3.

Ustal, która wersja jest prawdziwa, i zsynchronizuj repo.

### 11. Reguły Storage nie pasują do ścieżek w kodzie

Dwa niedopasowania:

| Kod zapisuje | Reguła oczekuje | Efekt |
|---|---|---|
| `room_images/{roomId}/{uid}_...` (`room_image_service.dart:41`) | `room_images/{userId}/...` z `uid == userId` | warunek nigdy nie jest spełniony — upload odrzucony |
| `clubs/{uid}/{clubId}/...` (`club_service.dart:219`) | brak reguły | odrzucone domyślnie |

Poza tym `allow read: if true` na `users/{userId}/profile/**` i `room_images/**` — awatary
i obrazki pokoi są publiczne dla całego internetu, bez logowania. Dla awatarów zwykle to
świadoma decyzja; upewnij się, że to Twoja.

### 12. `enforceAppCheck: false` we wszystkich funkcjach

Każdy `onCall` ma App Check wyłączony, łącznie z `createLiveKitToken`. Bez tego dowolny
skrypt z ważnym tokenem Firebase Auth może wołać backend poza aplikacją. Nie jest to
samo w sobie luka, ale usuwa warstwę, która znacząco podnosi koszt wykorzystania #1.

---

## BUG — kontrakt klient ↔ funkcja się nie zgadza

### 13. `createLiveKitToken` nie może działać z `voice_token_service.dart`

Trzy niezgodności naraz:

| | Klient (`voice_token_service.dart`) | Funkcja (`livekit/token.js`) |
|---|---|---|
| Nazwa pola wejściowego | wysyła `roomId` (linia 25) | czyta `roomName` (linia 62) |
| Zwracany token | oczekuje `participantToken` | zwraca `token` |
| Adres serwera | oczekuje `serverUrl` | nie zwraca w ogóle |

`normalizeText(undefined)` daje `""`, więc funkcja od razu rzuca
`invalid-argument: "A LiveKit room name is required."` Gdyby nawet przeszła,
`VoiceConnectionInfo.fromMap` rzuciłby `FormatException`.

Skoro w historii gita jest commit „Voice is live. HUGE", to znaczy, że **wdrożona funkcja
różni się od tej w repozytorium**. To najpoważniejszy problem organizacyjny w projekcie:
nie da się z tego repo odtworzyć produkcji ani wiarygodnie zaudytować tego, co działa.

Zsynchronizuj repo z produkcją, zanim zabierzesz się za poprawki 1–12.

---

## Kolejność naprawiania

1. **#13** — najpierw ustal, co faktycznie jest na produkcji. Bez tego reszta to zgadywanie.
2. **#1** — jedna funkcja, największy zysk. Naprawia moderację głosu w całości.
3. **#2 i #3** — dwie poprawki w regułach, obie krótkie, obie zamykają przejęcie zasobu.
4. **#4 i #6** — walidacja pól. Wymaga przejrzenia zapisów w `lib/**/data/services`,
   żeby nie zablokować działających ścieżek.
5. **#5, #7–#12** — reszta.

Po zmianach w regułach warto dopisać testy w `@firebase/rules-unit-testing` — reguły
Firestore to jedyna warstwa, którą da się sensownie testować bez emulatora całej aplikacji,
a ten projekt ma obecnie jeden domyślny plik testowy.
