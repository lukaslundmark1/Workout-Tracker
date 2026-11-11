# Training as a native iPhone app

This folder is a small iPhone app (made with Capacitor) that opens the live Training app
(https://lukaslundmark1.github.io/Workout-Tracker/) full screen. Inside it, the app uses the iPhone's real haptics
(every pattern, wheel ticks, pull and drag ticks) and sets the status bar to match light/dark. Everything else is the same app.

- **Updates come by themselves.** The app loads the live web app, so after a new version is pushed you just close and reopen it,
  like now. You only rebuild in Xcode if something in this `native` folder changes (you'll be told).
- **Offline:** it needs the internet the very first time it opens; after that it opens offline like the web app.
- **Sign-in:** email and password. Google doesn't allow its sign-in inside apps like this. If you normally use Google,
  tap "Forgot password?" with your Google email to give the same account a password, then sign in with that.
- **Your data** syncs through your account, so sign in and your training appears. The web app keeps working alongside.
- **Free Apple ID limits:** the app has to be re-installed from Xcode at least every 7 days (one click, see below), and a phone
  can have at most 3 apps installed this way.

## One-time setup on the MacBook (about 30–45 minutes, mostly downloading)

1. **Xcode:** install it from the Mac App Store (free, large). Open it once, accept, and let it install the iOS components.
2. **Node.js:** download the LTS installer from nodejs.org and install it.
3. **The code:** on https://github.com/lukaslundmark1/Workout-Tracker click the green **Code** button → **Download ZIP**,
   and unzip it (e.g. in Downloads).
4. **Terminal** (find it with Spotlight, ⌘-space, "Terminal"). Type `cd ` (with a space), drag the `native` folder from the
   unzipped folder into the Terminal window, and press Enter. Then run these three, one at a time:
   ```
   npm install
   npx cap sync ios
   npx cap open ios
   ```
   The last one opens the project in Xcode.
5. **Your Apple ID in Xcode:** menu **Xcode → Settings… → Accounts**, click **+**, choose **Apple ID**, sign in.
6. **Signing:** in Xcode's left column click **App** (the blue icon at the top), then under TARGETS click **App**, open the
   **Signing & Capabilities** tab and set **Team** to *your name (Personal Team)*.
   If it says the bundle identifier isn't available, change **Bundle Identifier** to something unique,
   e.g. `io.github.lukaslundmark1.training2`.
7. **iPhone:** connect it with a cable, unlock it and tap **Trust**. Turn on **Settings → Privacy & Security → Developer Mode**
   (it appears after the iPhone has been connected to Xcode; the phone restarts).
8. **Install:** at the top of Xcode pick your iPhone as the destination and press **▶** (Run). The first build takes a few
   minutes (it downloads Capacitor). If the iPhone says *Untrusted Developer*: **Settings → General → VPN & Device Management**
   → your Apple ID → **Trust**, then press ▶ again.
9. **Without the cable from now on:** **Window → Devices and Simulators**, select your iPhone, tick **Connect via network**.

"Training" is now on your home screen. Sign in with email and password.

## Every week (before 7 days are up)

Open Xcode (the project is under recent projects), keep the iPhone on the same Wi-Fi (or plug it in), press **▶**.
That's it: your data stays. If you miss it, the app just won't open until you do this.

## For whoever works on this next

- `capacitor.config.json`: app id `io.github.lukaslundmark1.training`, `server.url` = the live site, `errorPath` = `www/offline.html`
  (shown only if the very first load fails; it retries).
- `ios/App/App/Info.plist`: `WKAppBoundDomains` lists the live site (and the Firebase auth domain). Together with
  `limitsNavigationsToAppBoundDomains` this is what lets the web app's service worker (offline) run inside the app.
  iPhone only, portrait only. The launch screen is plain `systemGroupedBackgroundColor` (= the app's background in light and dark).
- Plugins: `@capacitor/haptics`, `@capacitor/status-bar` (Swift Package Manager, no CocoaPods). app.js calls them through the
  bridge Capacitor injects (`window.Capacitor.nativePromise`), only when `NATIVE` is true, so the web app needs no extra code.
- After changing anything here: `npx cap sync ios`, rebuild in Xcode. Generated files (`ios/App/App/public`, the copied config)
  are git-ignored and recreated by `cap sync`.
- App icon: `ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png` (1024×1024, redrawn from icon-512.png).
- 120 Hz: `AppViewController` in `ios/App/App/AppDelegate.swift` (the storyboard's custom class) turns off WebKit's 60 fps cap (`PreferPageRenderingUpdatesNear60FPSEnabled`, private API, guarded) before the web view is made; Info.plist has `CADisableMinimumFrameDurationOnPhone`. The Xcode log says "Training: drawing at the screen's full refresh rate" when it worked.
