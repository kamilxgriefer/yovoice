// Firebase Messaging service worker — required for web push. Without a
// file at exactly this path and name, the browser has nothing to hand a
// background push to, and `getToken()` has no registration to attach to.
//
// The compat builds are what firebase_messaging expects in a service
// worker: the modular SDK is not usable from this context. Keep the two
// versions identical to each other.
//
// The values below are the WEB app's public Firebase config — the same
// values already compiled into main.dart.js from lib/firebase_options.dart
// and visible in any browser's network tab. They identify the project;
// they do not authorize anything on their own (Security Rules do). Only
// the four keys Messaging actually needs are duplicated here.
//
// NOTE: the VAPID key is NOT part of this file and must never be added
// to it. The client passes it to getToken() at runtime from
// --dart-define=YOVOICE_WEB_PUSH_VAPID_KEY.

importScripts(
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js",
);
importScripts(
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js",
);

firebase.initializeApp({
  apiKey: "AIzaSyD-tDFTRzkrKthxTXsskFM8tBwI4au9xHI",
  appId: "1:80235878542:web:d0710da80b23e6051351df",
  messagingSenderId: "80235878542",
  projectId: "yovoice-ec54a",
});

// Registering the instance is what lets the browser deliver background
// pushes. Messages carrying a `notification` payload — which is what
// onNotificationCreated sends — are rendered by the browser itself, so
// there is deliberately no onBackgroundMessage handler drawing a second
// notification on top of it.
firebase.messaging();
