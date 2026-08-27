# Firebase Auth email templates

Branded HTML bodies for Firebase Authentication emails and the project-wide
action callback that replaces Firebase's generic white `__/auth/action` page.

> **SOURCE READY — NOT DEPLOYED (2026-08-27):** the website handlers and these
> templates are tested locally, but production still points at Firebase's
> default handler. Deploy the website first; only then change Auth config.

The project uses custom SMTP through Resend, so Firebase permits custom HTML.
The SMTP username must remain literally `resend` (see `docs/Decisions.md`).
Never export or overwrite the write-only SMTP password while changing email
templates.

## Mandatory rollout order

1. Deploy `yovoice-website` with all five token routes:
   `/auth/action`, `/reset-password`, `/verify-email`, `/recover-email`, and
   `/revert-second-factor`.
2. Probe those production routes and confirm `private, no-store`,
   `no-referrer`, and `noindex` headers. Confirm every supported Firebase mode
   reaches the intended branded page. In particular,
   `revertSecondFactorAddition` must reach `/revert-second-factor`; otherwise a
   global callback change would break Firebase's protective MFA-revert email.
3. Take a restricted pre-change snapshot of only the callback and template
   fields. Do not include SMTP credentials.
4. Patch only the following leaf fields through the Identity Toolkit Admin
   API:

   ```text
   notification.sendEmail.callbackUri
   notification.sendEmail.resetPasswordTemplate.senderDisplayName
   notification.sendEmail.resetPasswordTemplate.subject
   notification.sendEmail.resetPasswordTemplate.bodyFormat
   notification.sendEmail.resetPasswordTemplate.body
   notification.sendEmail.verifyEmailTemplate.senderDisplayName
   notification.sendEmail.verifyEmailTemplate.subject
   notification.sendEmail.verifyEmailTemplate.bodyFormat
   notification.sendEmail.verifyEmailTemplate.body
   ```

   Set `callbackUri` to `https://yovoice.app/auth/action`. Use a narrow
   `updateMask`; never patch the parent `notification` or `sendEmail` object.
5. Read the configuration back immediately and compare the callback, sender
   names, subjects, body formats, and complete HTML bodies to the intended
   values. Roll back with the restricted snapshot and the same leaf mask on
   any mismatch.
6. Run a real password-reset smoke using a controlled non-staff account, then
   a fresh verification-email smoke. Do not log, paste, capture, or retain an
   `oobCode`, email address, or password. Probe the MFA-revert route with a
   non-production diagnostic code; applying a real MFA-revert action requires
   separate explicit authorization.

The Firebase Console remains an emergency manual recovery path, but the API
procedure above is the reproducible release path. Confirm `yovoice.app`
remains in Auth authorized domains and CUSTOM_SMTP remains enabled before and
after the change.

## Template values

Password reset:

- Sender name: `YO Voice`
- Subject: `Reset your YO Voice password`
- Body: `password-reset.html` in HTML mode

Email verification:

- Sender name: `YO Voice`
- Subject: `Verify your email — YO Voice`
- Body: `verify-email.html` in HTML mode

Keep `%LINK%` and `%EMAIL%` exactly as written — Firebase substitutes
them at send time.

## Rendering caveats

The HTML is table-based with inline styles (email clients ignore
stylesheets). Verified in a browser; real-client rendering (Gmail strips
some styles, Outlook uses Word's engine) should be spot-checked with the
first live email. Dark backgrounds are declared with both `bgcolor` and
inline `background-color` for maximum client coverage; Gmail's "dark
mode" may still recolor — the layout stays legible either way because
text colors are explicit.
