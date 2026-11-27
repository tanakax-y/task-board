// TaskBoard のオフライン用：アプリ本体と部品（Preact / Supabase）を端末に保存する。
// データ（タスク・記録など）は index.html 側で保存している。
const SHELL = 'tb-shell-v1'
const CDN = /^https:\/\/(unpkg\.com|esm\.sh)\//
const CORE = ['./', './manifest.webmanifest', './icon.svg', './icon-180.png', './icon-512.png',
  'https://unpkg.com/htm@3.1.1/preact/standalone.module.js', 'https://esm.sh/@supabase/supabase-js@2.49.4']

self.addEventListener('install', e => {
  e.waitUntil(caches.open(SHELL).then(c => Promise.allSettled(CORE.map(u => c.add(u)))))
  self.skipWaiting()
})

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith('tb-shell-') && k !== SHELL) await caches.delete(k)
    await self.clients.claim()
  })())
})

// ページが読み込んだ部品（esm.sh の中で読み込まれる分も含む）を教えてもらって保存する
self.addEventListener('message', e => {
  if (e.data?.type !== 'cache' || !Array.isArray(e.data.urls)) return
  e.waitUntil(caches.open(SHELL).then(c => Promise.allSettled(
    e.data.urls.filter(u => CDN.test(u)).map(u => c.match(u).then(hit => hit || c.add(u))))))
})

self.addEventListener('fetch', e => {
  const r = e.request
  if (r.method !== 'GET') return
  if (r.mode === 'navigate') return e.respondWith(networkFirst(r, true))
  if (CDN.test(r.url)) return e.respondWith(cacheFirst(r))
  if (new URL(r.url).origin === location.origin) return e.respondWith(networkFirst(r, false))
  // Supabase などはそのまま通す
})

// 版番号つきの部品は中身が変わらないので、保存済みならそれを使う
async function cacheFirst(req) {
  const c = await caches.open(SHELL)
  const hit = await c.match(req)
  if (hit) return hit
  const res = await fetch(req)
  if (res.ok) c.put(req, res.clone())
  return res
}

// アプリ本体はいつも最新を取りに行き、電波がない（4秒待っても返ってこない）ときだけ保存済みを使う
async function networkFirst(req, nav) {
  const c = await caches.open(SHELL)
  const url = req.url.split('#')[0]
  const net = fetch(url, { cache: 'no-cache', credentials: 'same-origin' }).then(res => {
    if (res.ok && !res.redirected) c.put(url, res.clone())
    return res
  })
  try {
    const res = await Promise.race([net, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 4000))])
    return res.redirected ? Response.redirect(res.url, 302) : res
  } catch (err) {
    const hit = await c.match(url, { ignoreSearch: true }) || (nav && await c.match(new URL('./', self.registration.scope).href))
    if (hit) return hit
    return net   // 保存がなければ、そのまま通信の結果を待つ
  }
}
