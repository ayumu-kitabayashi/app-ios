/**
 * ReliefNote Service Worker
 * ==========================================================
 * 目的:
 *  - 新しいデプロイを確実にユーザーへ届ける（HTML を network-first）
 *  - 画像やロゴなどの静的アセットはオフラインでも使えるようにキャッシュ
 *
 * ポリシー:
 *  1. index.html / ルート / ?クエリ付きURL → network-first
 *     （ネットワーク取得を優先し、失敗時だけキャッシュにフォールバック）
 *  2. 画像 (*.png, *.jpg, *.svg, *.webp) → cache-first
 *  3. その他 → network-first
 *
 * バージョン管理:
 *  - index.html は /sw.js?v=APP_VERSION として登録する。
 *  - SW は自身の URL から `v` パラメータを取り出し、キャッシュ名に使う。
 *  - APP_VERSION を更新するだけでブラウザは別 SW として再インストールし、
 *    activate で古いキャッシュを DROP する。
 */

function _readVersionFromSelfUrl() {
    try {
        const u = new URL(self.location.href);
        const v = u.searchParams.get('v');
        if (v) return v;
    } catch (e) {}
    return 'rn-sw-default';
}

const VERSION = _readVersionFromSelfUrl();
const STATIC_CACHE = VERSION + '-static';
const HTML_CACHE = VERSION + '-html';

// インストール時: skipWaitingですぐに新SWを有効化
self.addEventListener('install', (event) => {
    self.skipWaiting();
});

// アクティベート時: 古いバージョンのキャッシュを削除
self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) => {
            return Promise.all(
                keys
                    .filter((k) => k !== STATIC_CACHE && k !== HTML_CACHE)
                    .map((k) => caches.delete(k))
            );
        }).then(() => self.clients.claim())
    );
});

function isHtmlRequest(request) {
    if (request.mode === 'navigate') return true;
    const accept = request.headers.get('accept') || '';
    if (accept.includes('text/html')) return true;
    const url = new URL(request.url);
    if (url.pathname === '/' || url.pathname.endsWith('/index.html')) return true;
    return false;
}

function isStaticAsset(request) {
    const url = new URL(request.url);
    return /\.(png|jpg|jpeg|svg|webp|gif|ico|woff2?|ttf)$/i.test(url.pathname);
}

self.addEventListener('fetch', (event) => {
    const request = event.request;

    // GET以外は素通し
    if (request.method !== 'GET') return;

    // 外部APIはキャッシュしない（Supabase / Worker など）
    const url = new URL(request.url);
    if (url.origin !== self.location.origin) return;

    if (isHtmlRequest(request)) {
        // network-first: 新版を必ず取りに行く
        event.respondWith(
            fetch(request)
                .then((response) => {
                    // 成功したらキャッシュ更新
                    const clone = response.clone();
                    caches.open(HTML_CACHE).then((cache) => cache.put(request, clone));
                    return response;
                })
                .catch(() => {
                    // オフラインならキャッシュから
                    return caches.match(request).then((cached) => {
                        return cached || caches.match('/index.html');
                    });
                })
        );
        return;
    }

    if (isStaticAsset(request)) {
        // cache-first: アセットは変わらない前提
        event.respondWith(
            caches.match(request).then((cached) => {
                if (cached) return cached;
                return fetch(request).then((response) => {
                    if (response && response.status === 200) {
                        const clone = response.clone();
                        caches.open(STATIC_CACHE).then((cache) => cache.put(request, clone));
                    }
                    return response;
                });
            })
        );
        return;
    }

    // その他は network-first フォールバック
    event.respondWith(
        fetch(request).catch(() => caches.match(request))
    );
});

// アプリ側から skipWaiting を要求するメッセージ
self.addEventListener('message', (event) => {
    if (event.data === 'SKIP_WAITING') {
        self.skipWaiting();
    }
});
