import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('../dist', import.meta.url)));
const host = process.env.HOST ?? '127.0.0.1';
const port = Number(process.env.PORT ?? 5174);

if (!existsSync(join(root, 'index.html'))) {
  throw new Error('web_admin/dist is missing. Run npm run build first.');
}

const mimeTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.png', 'image/png'],
  ['.ico', 'image/x-icon'],
]);

const server = createServer((request, response) => {
  const url = new URL(request.url ?? '/', `http://${host}:${port}`);
  const decodedPath = decodeURIComponent(url.pathname);
  const cleanPath = normalize(decodedPath).replace(/^(\.\.[/\\])+/, '');
  let filePath = resolve(join(root, cleanPath));

  if (!filePath.startsWith(root + sep) && filePath !== root) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }

  if (!existsSync(filePath) || statSync(filePath).isDirectory()) {
    filePath = join(root, 'index.html');
  }

  const type = mimeTypes.get(extname(filePath)) ?? 'application/octet-stream';
  response.writeHead(200, {
    'cache-control': 'no-cache',
    'content-type': type,
  });
  createReadStream(filePath).pipe(response);
});

server.listen(port, host, () => {
  console.log(`FlowPlanV2 Admin static server: http://${host}:${port}`);
});
