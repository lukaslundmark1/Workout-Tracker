// Bump this when you deploy a new version so old caches are cleared.
const CACHE = 'tt-v36';
const ASSETS = [
  './',
  './index.html',
  './app.js?v=24121872da',
  './manifest.webmanifest',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
  './firebase-346e04e6.js',
];

self.addEventListener('install', e => {
  // cache: 'reload' skips the browser's HTTP cache so an update never stores stale files
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS.map(u => new Request(u, { cache: 'reload' })))));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.registration.navigationPreload && self.registration.navigationPreload.disable().catch(() => {}))
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;

  // Pages: open instantly from this version's cache (no waiting on the network, even on bad gym Wi-Fi).
  // A new version arrives as a new sw.js: it installs in the background and the app switches over (see app.js).
  if (req.mode === 'navigate') {
    e.respondWith(
      caches.open(CACHE).then(c => c.match('./index.html')).then(hit => hit || fetch(req).catch(() => caches.match('./index.html')))
    );
    return;
  }
  // Everything else: cache first.
  e.respondWith(caches.match(req).then(hit => hit || fetch(req)));
});
