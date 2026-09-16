const CACHE_NAME = 'travel-planner-v13';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './apple-touch-icon.png',
  './icon-192.png',
  './icon-512.png',
  './state.json'
];

self.addEventListener('install', (e) => {
  self.skipWaiting();
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return Promise.all(
        ASSETS.map((url) => {
          return cache.add(url).catch((err) => {
            console.warn('SW: Optional asset cache failure:', url, err);
          });
        })
      );
    })
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('SW: Purging old cache', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  if (event.data && event.data.type === 'CLEAR_CACHE') {
    caches.keys().then(keys => Promise.all(keys.map(k => caches.delete(k))));
  }
});

// Network-first for documents and JSON data, cache-first with background revalidation for icons/images
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;

  const url = new URL(e.request.url);

  // Always bypass cache for API calls
  if (url.pathname.startsWith('/api/')) {
    return;
  }

  // Network-first for HTML navigation, JSON state, and roots
  if (e.request.mode === 'navigate' || url.pathname.endsWith('.html') || url.pathname.endsWith('.json') || url.pathname === '/' || url.pathname === '') {
    e.respondWith(
      fetch(e.request).then((networkResponse) => {
        if (networkResponse.status === 200) {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(e.request, responseToCache);
          });
        }
        return networkResponse;
      }).catch(() => {
        return caches.match(e.request, { ignoreSearch: true }).then((cachedResponse) => {
          if (cachedResponse) return cachedResponse;
          if (e.request.mode === 'navigate') {
            return caches.match('./index.html') || caches.match('./');
          }
        });
      })
    );
    return;
  }

  // Cache fallback with background update for other assets
  e.respondWith(
    caches.match(e.request, { ignoreSearch: true }).then((cachedResponse) => {
      if (cachedResponse) {
        fetch(e.request).then((networkResponse) => {
          if (networkResponse.status === 200) {
            caches.open(CACHE_NAME).then((cache) => cache.put(e.request, networkResponse));
          }
        }).catch(() => {});
        return cachedResponse;
      }
      return fetch(e.request).then((networkResponse) => {
        if (networkResponse.status === 200) {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(e.request, responseToCache));
        }
        return networkResponse;
      });
    })
  );
});
