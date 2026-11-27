// Only an anonymous, static offline notice and app icon are cached.
// Never cache authentication, API requests, user pages, private photos, or mutations.
const CACHE='agriconnect-offline-v1';
const STATIC=['/offline.html','/icons/icon-192.png'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(STATIC)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil((async()=>{for(const key of await caches.keys())if(key.startsWith('agriconnect-offline-')&&key!==CACHE)await caches.delete(key);await self.clients.claim()})()));
self.addEventListener('fetch',event=>{
 const req=event.request,url=new URL(req.url);
 if(req.method!=='GET'||url.origin!==self.location.origin)return;
 if(req.mode==='navigate'&&(url.pathname==='/'||url.pathname==='/index.html')){
  event.respondWith(fetch(req).catch(async()=>await caches.match('/offline.html')||new Response('Offline. Reconnect to use AgriConnect.',{status:503,headers:{'Content-Type':'text/plain'}})));
 }else if(STATIC.includes(url.pathname)&&!url.search){
  event.respondWith(caches.match(req).then(hit=>hit||fetch(req)));
 }
});
