import { resolve, sep } from 'node:path';

// Research-only static server: never proxies production or executes the Worker.
const root = resolve(import.meta.dir, '../../../web/public');
Bun.serve({
  hostname: '127.0.0.1',
  port: Number(process.env.SITE_SHOTS_PORT || 43932),
  async fetch(request) {
    const pathname = decodeURIComponent(new URL(request.url).pathname);
    const path = resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`);
    if (!path.startsWith(root + sep)) return new Response('Forbidden', { status: 403 });
    const file = Bun.file(path);
    return await file.exists() ? new Response(file) : new Response('Not found', { status: 404 });
  },
});
