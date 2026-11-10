# Training tracker (PWA)

## Put it online (GitHub Pages, free)
1. Create a new public repository on github.com, e.g. `training-tracker`.
2. Upload every file in this folder to the repository.
3. Go to the repository's **Settings → Pages**, set **Source** to *Deploy from a branch*, pick `main` and `/ (root)`, then save.
4. After a minute your app is at `https://<your-username>.github.io/training-tracker/`.

## Install on your phone
- **iPhone:** open the link in Safari → Share → **Add to Home Screen**.
- **Android:** open the link in Chrome → ⋮ menu → **Install app** (or Add to Home screen).

## Notes
- Data is stored on the device for now (no accounts yet). Each phone has its own data.
- When you deploy an update, bump `CACHE` in `sw.js` (e.g. `tt-v3`) so phones pick up the new version.
