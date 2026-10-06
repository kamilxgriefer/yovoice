/**
 * Server-side push localisation (ADR-237): which language a recipient's push
 * is written in, for every push type, in every one of the 43 languages.
 *
 * The pure half needs nothing; the last two tests drive the real push
 * handler against the Firestore emulator:
 *
 *   firebase emulators:exec --only firestore --project demo-yovoice \
 *     "cd functions && node --test --test-concurrency=1 test/push_localisation.test.js"
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");

const COPY = require("../notifications/push_copy.json");
const {
  LABELLED_TYPES,
  PLAIN_TYPES,
  PUSH_LOCALES,
  PUSH_TEMPLATE_IDS,
  SURFACE_TEMPLATES,
  TRANSLATED_PUSH_LOCALES,
  fillTemplate,
  localizedPushSurface,
  localizedPushTitle,
  normalizePushLocale,
  pushTitleTemplateId,
  recipientPushLocale,
} = require("../notifications/push_locale");
const {
  DEFAULT_PUSH_SURFACE,
  PUSH_BODY_TYPES,
  buildPushMessage,
} = require("../notifications/push_payload");
const { PUSH_TITLES, handleNotificationCreated } = require("../notifications/push");
const { db } = require("../utils/firestore");

const ROOT = path.resolve(__dirname, "..", "..");
// lib/core/localization/app_language.dart, `localeKey` of every selectable
// language, in picker order.
const APP_LOCALE_KEYS = [
  "en", "pl", "de", "es", "pt", "pt_BR", "fr", "it", "uk", "ru",
  "cs", "sk", "bg", "nl", "ro", "tr", "el", "hu", "hr", "sr",
  "sv", "da", "nb", "fi", "lt", "lv", "et", "id", "vi", "zh_CN",
  "zh_TW", "ja", "ko", "ar", "hi", "bn", "ur", "th", "ms", "fil",
  "he", "fa", "sw",
];

test("the table covers exactly the 43 app languages", () => {
  assert.equal(APP_LOCALE_KEYS.length, 43);
  assert.deepEqual([...PUSH_LOCALES].sort(), [...APP_LOCALE_KEYS].sort());
  assert.equal(TRANSLATED_PUSH_LOCALES.length, 42);
  assert.equal(TRANSLATED_PUSH_LOCALES.includes("en"), false);
  assert.equal(COPY.schemaVersion, 1);
  // The rules accept the same closed set the server understands.
  const rules = fs.readFileSync(path.join(ROOT, "firestore.rules"), "utf8");
  const block = rules.slice(
    rules.indexOf("function appLanguageValueAllowed()"),
    rules.indexOf("function userCreateAllowed("),
  );
  const allowed = [...block.matchAll(/'([A-Za-z_]+)'/gu)]
    .map((match) => match[1])
    .filter((value) => value !== "appLanguage");
  assert.deepEqual([...allowed].sort(), [...APP_LOCALE_KEYS].sort());
  // And the app's own list is that set.
  const app = fs.readFileSync(
    path.join(ROOT, "lib/core/localization/app_language.dart"),
    "utf8",
  );
  for (const key of ["pt_BR", "zh_CN", "zh_TW"]) {
    assert.match(app, new RegExp(`'${key}'`, "u"), key);
  }
});

test("locale selection: stored key, English only when unknown", () => {
  assert.equal(recipientPushLocale({ appLanguage: "pl" }), "pl");
  assert.equal(recipientPushLocale({ appLanguage: "pt_BR" }), "pt_BR");
  assert.equal(recipientPushLocale({ appLanguage: "zh_TW" }), "zh_TW");
  assert.equal(recipientPushLocale({ appLanguage: "en" }), "en");
  // Builds 40/41 never wrote the field; a deleted or malformed value is the
  // same "unknown".
  for (const data of [
    undefined, null, {}, { appLanguage: null }, { appLanguage: 7 },
    { appLanguage: "" }, { appLanguage: "system" }, { appLanguage: "xx" },
    { appLanguage: "PL" }, { appLanguage: "pl " }, { appLanguage: "pt-BR" },
    { appLanguage: "pl".repeat(40) }, { appLanguage: ["pl"] },
    { appLanguage: "__proto__" }, { appLanguage: "constructor" },
  ]) {
    assert.equal(recipientPushLocale(data), "en", JSON.stringify(data));
  }
  for (const key of APP_LOCALE_KEYS) assert.equal(normalizePushLocale(key), key);
});

test("every template the server can ask for exists in all 42 languages", () => {
  const wanted = new Set([
    ...PLAIN_TYPES,
    ...LABELLED_TYPES.flatMap((type) => [type, `${type}.label`]),
    "directCall", "directCall.video", "missedCall", "missedCall.video",
    "moderation", "actor.unknown",
    ...Object.values(SURFACE_TEMPLATES),
  ]);
  assert.deepEqual([...wanted].sort(), PUSH_TEMPLATE_IDS);
  for (const id of wanted) {
    const row = COPY.templates[id];
    assert.ok(row, id);
    assert.deepEqual(Object.keys(row).sort(), [...TRANSLATED_PUSH_LOCALES].sort(), id);
    const wantsLabel = id.endsWith(".label");
    const wantsActor = !["serverEventReminder", "serverEventReminder.label",
      "achievementUnlocked", "achievementUnlocked.label", "moderation",
      "actor.unknown", ...Object.values(SURFACE_TEMPLATES)].includes(id);
    for (const locale of TRANSLATED_PUSH_LOCALES) {
      const text = row[locale];
      assert.equal(typeof text, "string", `${id} ${locale}`);
      assert.ok(text.trim().length > 0, `${id} ${locale}`);
      assert.equal(text.includes("{actor}"), wantsActor, `${id} ${locale}: ${text}`);
      assert.equal(text.includes("{label}"), wantsLabel, `${id} ${locale}: ${text}`);
      assert.deepEqual(
        (text.match(/\{[a-zA-Z]+\}/gu) ?? []).filter((token) =>
          !["{actor}", "{label}"].includes(token)),
        [],
        `${id} ${locale}`,
      );
    }
  }
});

test("every push title has a template id, and pass-through types have none", () => {
  for (const type of Object.keys(PUSH_TITLES)) {
    const plain = pushTitleTemplateId(type, null);
    const labelled = pushTitleTemplateId(type, "Label");
    if (type === "system") {
      assert.equal(plain, null);
      assert.equal(labelled, null);
      continue;
    }
    assert.ok(PUSH_TEMPLATE_IDS.includes(plain), `${type} -> ${plain}`);
    if (type === "moderation") {
      // A moderator's own words are passed through as written.
      assert.equal(labelled, null);
    } else {
      assert.ok(PUSH_TEMPLATE_IDS.includes(labelled), `${type} -> ${labelled}`);
    }
  }
  assert.equal(pushTitleTemplateId("directCall", "Incoming video call"), "directCall.video");
  assert.equal(pushTitleTemplateId("directCall", "Incoming voice call"), "directCall");
  assert.equal(pushTitleTemplateId("missedCall", "Missed video call"), "missedCall.video");
  assert.equal(pushTitleTemplateId("missedCall", null), "missedCall");
  assert.equal(pushTitleTemplateId("clubInvite", "Nocne Granie"), "clubInvite.label");
  assert.equal(pushTitleTemplateId("clubInvite", ""), "clubInvite");
  assert.equal(pushTitleTemplateId("brandNewType", null), null);
  assert.equal(pushTitleTemplateId(undefined, null), null);
});

test("every type renders a complete title in every language", () => {
  for (const locale of PUSH_LOCALES) {
    for (const type of Object.keys(PUSH_TITLES)) {
      for (const label of [null, "Nocne Granie", "Incoming video call", "Missed video call"]) {
        const localized = localizedPushTitle({
          type,
          locale,
          actorName: "Ola Nowak",
          targetLabel: label,
        });
        const title = localized ?? PUSH_TITLES[type]("Ola Nowak", label);
        assert.equal(typeof title, "string", `${type} ${locale}`);
        assert.ok(title.trim().length > 0, `${type} ${locale}`);
        assert.doesNotMatch(title, /\{actor\}|\{label\}|\bundefined\b|\bnull\b/u,
          `${type} ${locale}`);
        if (locale === "en") assert.equal(localized, null, `${type} en uses PUSH_TITLES`);
      }
    }
  }
});

test("Polish, German and Japanese say what the bell says", () => {
  const title = (type, locale, label = null, actorName = "Ola") =>
    localizedPushTitle({ type, locale, actorName, targetLabel: label });
  assert.equal(title("pagePostPublished", "pl", "New post from a Page you follow: X", "Pracownia Glina"),
    "Pracownia Glina dodaje post");
  assert.equal(title("friendRequest", "pl"), "Ola wysyła Ci zaproszenie do znajomych");
  assert.equal(title("clubInvite", "pl", "Nocne Granie"), "Ola zaprasza Cię do serwera Nocne Granie");
  assert.equal(title("roomInvite", "pl", "Kanał"), "Ola zaprasza Cię do kanału głosowego Kanał");
  assert.equal(title("broadcastInvite", "pl"), "Ola zaprasza Cię do transmisji");
  assert.equal(title("directMessage", "pl"), "Ola wysyła Ci wiadomość");
  assert.equal(title("directCall", "pl", "Incoming video call"), "Ola dzwoni do Ciebie z wideo");
  assert.equal(title("directCall", "pl", "Incoming voice call"), "Ola dzwoni do Ciebie");
  assert.equal(title("missedCall", "pl", "Missed video call"), "Nieodebrane połączenie wideo od Ola");
  assert.equal(title("achievementUnlocked", "pl", "First Voice"), "Odblokowano osiągnięcie: First Voice");
  assert.equal(title("achievementUnlocked", "pl"), "Odblokowano osiągnięcie");
  assert.equal(title("serverEventReminder", "pl", "Wieczór pytań"), "Niedługo start: Wieczór pytań");
  assert.equal(title("pagePostComment", "pl"), "Ola komentuje Twój post na stronie");
  assert.equal(title("moderation", "pl"), "Moderator wykonał działanie na Twoim koncie");
  assert.equal(title("friendRequest", "de"), "Ola hat dir eine Freundschaftsanfrage gesendet");
  assert.equal(title("pagePostPublished", "ja", null, "Pracownia Glina"),
    "Pracownia Glina が新しい投稿を公開しました");
  // No name on the row: the language's own "YO Voice user".
  assert.equal(title("follow", "pl", null, ""), "Użytkownik YO Voice zaczyna Cię obserwować");
  for (const actorName of [undefined, null, "   ", 7]) {
    assert.equal(
      localizedPushTitle({ type: "follow", locale: "pl", actorName, targetLabel: null }),
      "Użytkownik YO Voice zaczyna Cię obserwować",
      String(actorName),
    );
  }
  // Server-authored text is never run through a template.
  assert.equal(title("system", "pl", "Planned maintenance"), null);
  assert.equal(title("moderation", "pl", "Your post was removed"), null);
  // English and anything unknown fall to the English builder.
  assert.equal(title("friendRequest", "en"), null);
  assert.equal(title("friendRequest", "xx"), null);
  assert.equal(title("brandNewType", "pl"), null);
});

test("substitution is single pass: a name cannot inject a placeholder", () => {
  assert.equal(fillTemplate("{actor} → {label}", { actor: "{label}", label: "{actor}" }),
    "{label} → {actor}");
  assert.equal(localizedPushTitle({
    type: "clubInvite",
    locale: "pl",
    actorName: "{label}",
    targetLabel: "{actor} $& $1",
  }), "{label} zaprasza Cię do serwera {actor} $& $1");
});

test("lock-screen sentences are localized and keep the brand", () => {
  assert.equal(localizedPushSurface("en"), null);
  assert.equal(localizedPushSurface("xx"), null);
  assert.deepEqual(localizedPushSurface("pl"), {
    defaultBody: "Dotknij, aby otworzyć YO Voice",
    incomingCallTitle: "Połączenie przychodzące w YO Voice",
    incomingCallBody: "Otwórz YO Voice, aby odebrać.",
    missedCallTitle: "Nieodebrane połączenie w YO Voice",
    missedCallBody: "Otwórz YO Voice, aby zobaczyć połączenie.",
  });
  for (const locale of TRANSLATED_PUSH_LOCALES) {
    const surface = localizedPushSurface(locale);
    assert.deepEqual(Object.keys(surface).sort(), Object.keys(DEFAULT_PUSH_SURFACE).sort(), locale);
    for (const [key, text] of Object.entries(surface)) {
      assert.match(text, /YO Voice/u, `${locale} ${key}`);
      assert.notEqual(text, DEFAULT_PUSH_SURFACE[key], `${locale} ${key} is English`);
    }
  }
});

test("payload: localized call notices stay private; only a Page post carries words", () => {
  const base = {
    tokens: ["token"],
    targetId: "target",
    actorId: "actor",
    notificationId: "row",
    collapseId: "collapse",
  };
  const call = buildPushMessage({
    ...base,
    type: "directCall",
    title: "Ola dzwoni do Ciebie z wideo",
    surface: localizedPushSurface("pl"),
  });
  // APNs / Web: no caller name, in Polish.
  assert.deepEqual(call.notification, {
    title: "Połączenie przychodzące w YO Voice",
    body: "Otwórz YO Voice, aby odebrać.",
  });
  assert.equal(call.webpush.notification.title, "Połączenie przychodzące w YO Voice");
  assert.equal(call.apns.payload.aps.alert.title, "Połączenie przychodzące w YO Voice");
  // Android: the caller, behind private visibility.
  assert.equal(call.android.notification.title, "Ola dzwoni do Ciebie z wideo");
  assert.equal(call.android.notification.body, "Dotknij, aby otworzyć YO Voice");
  assert.equal(call.android.notification.visibility, "private");

  const missed = buildPushMessage({
    ...base,
    type: "missedCall",
    title: "Nieodebrane połączenie od Ola",
    surface: localizedPushSurface("pl"),
  });
  assert.deepEqual(missed.notification, {
    title: "Nieodebrane połączenie w YO Voice",
    body: "Otwórz YO Voice, aby zobaczyć połączenie.",
  });

  assert.deepEqual([...PUSH_BODY_TYPES], ["pagePostPublished"]);
  const post = buildPushMessage({
    ...base,
    type: "pagePostPublished",
    title: "Pracownia Glina dodaje post",
    body: "  Nowe kubki już w pracowni  ",
    surface: localizedPushSurface("pl"),
  });
  assert.deepEqual(post.notification, {
    title: "Pracownia Glina dodaje post",
    body: "Nowe kubki już w pracowni",
  });
  assert.equal(post.webpush.notification.body, "Nowe kubki już w pracowni");
  assert.equal(post.android.notification.channelId, "yovoice_social_v1");
  // A photo post without a caption falls back to the generic sentence.
  for (const body of [null, undefined, "", "   ", 7]) {
    assert.equal(buildPushMessage({
      ...base,
      type: "pagePostPublished",
      title: "t",
      body,
      surface: localizedPushSurface("pl"),
    }).notification.body, "Dotknij, aby otworzyć YO Voice");
  }
  assert.equal(buildPushMessage({ ...base, type: "pagePostPublished", title: "t", body: "x".repeat(900) })
    .notification.body.length, 240);
  // Every other type ignores a body: a comment's words never enter a push.
  for (const type of ["momentComment", "pagePostComment", "directMessage", "reply", "system"]) {
    assert.equal(buildPushMessage({ ...base, type, title: "t", body: "secret words" })
      .notification.body, "Tap to open YO Voice", type);
  }
  // No surface (English recipient): exactly the pre-localisation payload.
  assert.deepEqual(buildPushMessage({ ...base, type: "follow", title: "Ada started following you" })
    .notification, { title: "Ada started following you", body: "Tap to open YO Voice" });
  // A partial surface keeps English for the missing slot only.
  assert.deepEqual(buildPushMessage({
    ...base,
    type: "follow",
    title: "t",
    surface: { defaultBody: "  ", incomingCallTitle: "x" },
  }).notification, { title: "t", body: "Tap to open YO Voice" });
});

test("English titles are untouched (builds without a stored language)", () => {
  assert.equal(PUSH_TITLES.friendRequest("Ada"), "Ada sent you a friend request");
  assert.equal(PUSH_TITLES.roomInvite("Ada", null), "Ada invited you to a conversation");
  assert.equal(PUSH_TITLES.directCall("Ada", "Incoming video call"), "Ada is video calling you");
  assert.equal(PUSH_TITLES.pagePostPublished("Pracownia Glina"), "Pracownia Glina published a post");
});

// ------------------------------------------------ the real push handler

function messagingSpy() {
  const messages = [];
  return {
    messages,
    sendEachForMulticast: async (message) => {
      messages.push(message);
      return { responses: message.tokens.map(() => ({ success: true })) };
    },
  };
}

async function deliver(recipientId, row, messaging) {
  const reference = db.doc(`users/${recipientId}/notifications/${row.id}`);
  await reference.set(row.data);
  const snapshot = await reference.get();
  await handleNotificationCreated({
    id: `evt-${row.id}`,
    params: { userId: recipientId, notificationId: row.id },
    data: snapshot,
  }, { messaging });
  return (await reference.get()).data();
}

test("the handler writes the push in the recipient's stored language", async () => {
  const stamp = Date.now();
  const messaging = messagingSpy();
  const cases = [
    { locale: "pl", title: "Odblokowano osiągnięcie: First Voice", body: "Dotknij, aby otworzyć YO Voice" },
    { locale: "de", title: "Erfolg freigeschaltet: First Voice", body: "Tippe, um YO Voice zu öffnen" },
    { locale: "en", title: "Achievement unlocked: First Voice", body: "Tap to open YO Voice" },
    // Never stored (builds 40/41) and a value the server does not know.
    { locale: undefined, title: "Achievement unlocked: First Voice", body: "Tap to open YO Voice" },
    { locale: "klingon", title: "Achievement unlocked: First Voice", body: "Tap to open YO Voice" },
  ];
  for (const [index, entry] of cases.entries()) {
    const uid = `locale-recipient-${stamp}-${index}`;
    await db.doc(`users/${uid}`).set({
      uid,
      displayName: "Kasia",
      ...(entry.locale === undefined ? {} : { appLanguage: entry.locale }),
    });
    await db.doc(`users/${uid}/fcmTokens/token-${index}`).set({ updatedAt: Timestamp.now() });
    const row = await deliver(uid, {
      id: `achievementUnlocked_first_${stamp}_${index}`,
      data: {
        type: "achievementUnlocked",
        actorId: "yovoice-system",
        actorName: "YO Voice",
        targetId: "moments_1",
        targetLabel: "First Voice",
        isRead: false,
        bellSuppressed: false,
      },
    }, messaging);
    assert.equal(row.pushDeliveryStatus, "sent", String(entry.locale));
    const message = messaging.messages.at(-1);
    assert.deepEqual(message.notification, { title: entry.title, body: entry.body },
      String(entry.locale));
    assert.equal(message.webpush.notification.title, entry.title);
    assert.equal(message.data.type, "achievementUnlocked");
  }
  assert.equal(messaging.messages.length, cases.length);
});

test("a system notice keeps its own words in every language", async () => {
  const stamp = Date.now();
  const uid = `locale-system-${stamp}`;
  await db.doc(`users/${uid}`).set({ uid, displayName: "Kasia", appLanguage: "pl" });
  await db.doc(`users/${uid}/fcmTokens/token-system`).set({ updatedAt: Timestamp.now() });
  const messaging = messagingSpy();
  await deliver(uid, {
    id: `system-${stamp}`,
    data: {
      type: "system",
      actorId: "",
      actorName: "YO Voice",
      targetLabel: "Planned maintenance tonight",
      isRead: false,
      bellSuppressed: false,
    },
  }, messaging);
  assert.deepEqual(messaging.messages[0].notification, {
    title: "Planned maintenance tonight",
    body: "Dotknij, aby otworzyć YO Voice",
  });
});
