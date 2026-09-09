const CACHE="atlas-v50";
const ASSETS=["./","./index.html","./assets/app.css","./assets/app.js","./assets/cloud-mode.js","./assets/release-readiness.js","./assets/workflow-audit.js","./assets/integral-audit.js","./assets/migration-mapper.js","./assets/cloud-import-executor.js","./assets/cloud-auth.js","./assets/cloud-import.js","./assets/migration.js","./assets/data.js","./assets/config.js","./assets/supabase.js","./assets/repositories.js","./assets/sync.js"];
self.addEventListener("install",e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS))));
self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))));
self.addEventListener("fetch",e=>{
 if(e.request.url.includes("supabase.co")||e.request.url.includes("esm.sh")) return;
 e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)));
});
