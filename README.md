# Training tracker (PWA)

A workout tracker and planner that runs in the browser and installs on iPhone and Android.
Hosted on GitHub Pages; accounts, sync and friends use a free Firebase project.

## Files
- `index.html`: the page and all styles. Contains the Content-Security-Policy.
- `app.js`: all the app's code.
- `firebase-<hash>.js`: the Firebase SDK, bundled locally (rename with a new hash whenever it's rebuilt).
- `sw.js`: service worker (offline support and updates).
- `firestore.rules`: Firestore security rules. **Paste into Firebase console → Firestore → Rules → Publish whenever they change.**
- `build.py`: run before every deploy (see below).

## Deploying an update
```
python3 build.py
```
This stamps `app.js` with a content hash in `index.html`, lists the files in `sw.js`, bumps the service worker
cache so installed apps update, and checks the security policy is still in place. Then commit and push.

## Install on your phone
- **iPhone:** open the link in Safari → Share → **Add to Home Screen**.
- **Android:** open the link in Chrome → ⋮ menu → **Install app**.

## Security
- The Content-Security-Policy in `index.html` only lets the app's own code run (plus Google sign-in), so an injected
  script can't run even if some text slipped through. Keep code in `app.js`, never inline `<script>` or `onclick=""`.
- Everything that comes from other people (friends' training, shared database entries, received plans, imported
  backups) is cleaned before use, and all text is escaped when shown.
- Firestore rules only allow known fields and collections; friends can only read what you share; only friends can send
  you things. The Firebase web config in `app.js` is meant to be public, so security comes from the rules.
- Settings → Delete account removes everything about you from the cloud.
