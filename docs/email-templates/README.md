# Firebase Auth email templates

Branded HTML bodies for the Authentication emails, plus the one console
setting that makes emailed links open YO Voice's own action pages instead
of Firebase's generic white `__/auth/action` page.

**Why these are paste-into-console files instead of code:** Firebase Auth
has no deploy/CLI/API surface in our toolchain for email templates — they
live in Console state. The message body is editable **only because this
project sends through a custom SMTP server** (Resend — configured and
verified working; the SMTP username must stay literally `resend`, see
docs/Decisions.md). On the default Firebase sender, the body is locked
for anti-phishing reasons and only the action URL / sender name are
customizable.

## One-time console steps (in order)

All under **Firebase Console → Authentication**.

1. **Settings → Authorized domains** — confirm `yovoice.app` is listed
   (it should be already: the website performs sign-in on that domain).

2. **Templates → any template → pencil → "Customize action URL"** — set:

   ```
   https://yovoice.app/auth/action
   ```

   This is ONE project-wide setting shared by password reset, email
   verification and email-change emails. After saving it, every emailed
   link goes straight to the website's `/auth/action` dispatcher, which
   routes by `mode` to `/reset-password`, `/verify-email` or
   `/recover-email`. Nothing user-facing remains on
   `yovoice-ec54a.firebaseapp.com`.

3. **Templates → Password reset**
   - Sender name: `YO Voice`
   - Subject: `Reset your YO Voice password`
   - Message: paste `password-reset.html` (switch the editor to HTML).

4. **Templates → Email address verification**
   - Sender name: `YO Voice`
   - Subject: `Verify your email — YO Voice`
   - Message: paste `verify-email.html`.

Keep `%LINK%` and `%EMAIL%` exactly as written — Firebase substitutes
them at send time.

## After changing the action URL, send yourself both emails

The full loop needs a real inbox, which no automated session here has:
request a password reset from the app or website, click the emailed
button, and confirm you land on `yovoice.app/reset-password` (dark page,
YO Voice logo) — not on a white firebaseapp.com page. Do the same for a
fresh registration's verification email.

## Rendering caveats

The HTML is table-based with inline styles (email clients ignore
stylesheets). Verified in a browser; real-client rendering (Gmail strips
some styles, Outlook uses Word's engine) should be spot-checked with the
first live email. Dark backgrounds are declared with both `bgcolor` and
inline `background-color` for maximum client coverage; Gmail's "dark
mode" may still recolor — the layout stays legible either way because
text colors are explicit.
