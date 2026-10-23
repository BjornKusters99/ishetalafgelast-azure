import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const image = 'ishetalafgelast:test';
const containerName = `ishetalafgelast-smoke-${process.pid}`;

function docker(args) {
  const result = spawnSync('docker', args, { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result.stdout.trim();
}

try {
  docker([
    'run', '--detach', '--rm', '--name', containerName,
    '--publish', '127.0.0.1::8080', image,
  ]);
  const address = docker(['port', containerName, '8080/tcp']);
  const port = address.match(/:(\d+)$/)?.[1];
  assert.ok(port, `Could not read published port: ${address}`);

  const base = `http://127.0.0.1:${port}`;
  const expected = new Map([
    ['/', 'IsHetAlAfgelast.nl'],
    ['/plaatsen/', 'Plaatsen'],
    ['/plaatsen/alkmaar.html', 'Alkmaar'],
    ['/privacy.html', 'Hosting'],
    ['/manifest.webmanifest', 'name'],
    ['/sw.js', 'CACHE'],
    ['/healthz', 'ok'],
  ]);

  for (const [path, bodyText] of expected) {
    let response;
    for (let attempt = 0; attempt < 20; attempt += 1) {
      try {
        response = await fetch(`${base}${path}`);
        break;
      } catch (error) {
        if (attempt === 19) throw error;
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }
    assert.equal(response.status, 200, `${path}: HTTP ${response.status}`);
    assert.match(await response.text(), new RegExp(bodyText, 'i'), path);
    assert.equal(response.headers.get('x-robots-tag'), 'noindex, nofollow');
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  }

  const missing = await fetch(`${base}/does-not-exist`);
  assert.equal(missing.status, 404);
  assert.match(await missing.text(), /Buitenspel/i);
  console.log('Container smoke tests passed.');
} finally {
  spawnSync('docker', ['rm', '--force', containerName], { stdio: 'ignore' });
}
