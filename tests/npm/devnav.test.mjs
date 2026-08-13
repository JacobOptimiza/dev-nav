import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  DevnavError,
  install,
  loadReleaseManifest,
  selectInstallerArtifact,
  sha256File,
} from '../../packaging/npm/bin/devnav.mjs';

// Fixture manifests reuse the real package version so the tests can never hide
// a version desynchronization between the package and its release manifest.
const PACKAGE_JSON = join(dirname(fileURLToPath(import.meta.url)), '../../packaging/npm/package.json');
const VERSION = JSON.parse(readFileSync(PACKAGE_JSON, 'utf8')).version;

async function makeFixture({ corrupt = false } = {}) {
  const root = await mkdtemp(join(tmpdir(), 'devnav-npm-test-'));
  await mkdir(join(root, 'payload'), { recursive: true });
  const artifacts = {};
  for (const [name, file] of [
    ['installer-x64', 'DevNavSetup-x64.exe'],
    ['installer-arm64', 'DevNavSetup-arm64.exe'],
  ]) {
    const content = `fake installer bytes for ${file}`;
    await writeFile(join(root, 'payload', file), content);
    let sha256 = createHash('sha256').update(content).digest('hex');
    if (corrupt && name === 'installer-x64') {
      sha256 = '0'.repeat(64);
    }
    artifacts[name] = { file, sha256 };
  }
  const manifest = { schemaVersion: 1, version: VERSION, artifacts };
  await writeFile(join(root, 'release-manifest.json'), JSON.stringify(manifest, null, 2));
  return {
    root,
    manifest,
    env: { LOCALAPPDATA: join(root, 'local-appdata') },
    cleanup: () => rm(root, { recursive: true, force: true }),
  };
}

function spawnRecorder({ installerStatus = 0, versionOutput = `dev-nav ${VERSION}` } = {}) {
  const calls = [];
  const spawn = (file, args) => {
    calls.push({ file, args });
    if (args[0] === '--version') {
      return { status: versionOutput === null ? 1 : 0, stdout: versionOutput ?? '', error: null };
    }
    return { status: installerStatus, error: null };
  };
  return { calls, spawn };
}

test('selectInstallerArtifact maps x64 and arm64 to their payloads', async () => {
  const fixture = await makeFixture();
  try {
    assert.equal(selectInstallerArtifact(fixture.manifest, 'x64').file, 'DevNavSetup-x64.exe');
    assert.equal(selectInstallerArtifact(fixture.manifest, 'arm64').file, 'DevNavSetup-arm64.exe');
  } finally {
    await fixture.cleanup();
  }
});

test('selectInstallerArtifact rejects unsupported architectures', async () => {
  const fixture = await makeFixture();
  try {
    assert.throws(() => selectInstallerArtifact(fixture.manifest, 'ia32'), DevnavError);
    assert.throws(() => selectInstallerArtifact(fixture.manifest, 's390x'), /x64 and ARM64/);
  } finally {
    await fixture.cleanup();
  }
});

test('loadReleaseManifest rejects a foreign schema', async () => {
  const fixture = await makeFixture();
  try {
    await writeFile(join(fixture.root, 'release-manifest.json'), JSON.stringify({ schemaVersion: 99 }));
    assert.throws(() => loadReleaseManifest(fixture.root), /schema version 1/);
  } finally {
    await fixture.cleanup();
  }
});

test('sha256File computes the lowercase hex digest', async () => {
  const fixture = await makeFixture();
  try {
    const expected = createHash('sha256').update('fake installer bytes for DevNavSetup-x64.exe').digest('hex');
    assert.equal(await sha256File(join(fixture.root, 'payload', 'DevNavSetup-x64.exe')), expected);
  } finally {
    await fixture.cleanup();
  }
});

test('install refuses non-Windows platforms before touching the disk', async () => {
  const fixture = await makeFixture();
  try {
    await assert.rejects(
      install({ platform: 'linux', root: fixture.root, env: fixture.env }),
      /only runs on Windows/,
    );
  } finally {
    await fixture.cleanup();
  }
});

test('install aborts on a SHA-256 mismatch and never starts the installer', async () => {
  const fixture = await makeFixture({ corrupt: true });
  const { calls, spawn } = spawnRecorder();
  try {
    await assert.rejects(
      install({ platform: 'win32', arch: 'x64', root: fixture.root, env: fixture.env, spawn }),
      /SHA-256 mismatch/,
    );
    assert.equal(calls.length, 0);
  } finally {
    await fixture.cleanup();
  }
});

test('install aborts when the installer exits with a non-zero code', async () => {
  const fixture = await makeFixture();
  const { spawn } = spawnRecorder({ installerStatus: 5 });
  try {
    await assert.rejects(
      install({ platform: 'win32', arch: 'x64', root: fixture.root, env: fixture.env, spawn }),
      /exited with code 5/,
    );
  } finally {
    await fixture.cleanup();
  }
});

test('install aborts when the installed executable reports the wrong version', async () => {
  const fixture = await makeFixture();
  const { spawn } = spawnRecorder({ versionOutput: 'dev-nav 0.9.1' });
  try {
    await assert.rejects(
      install({ platform: 'win32', arch: 'x64', root: fixture.root, env: fixture.env, spawn }),
      /Post-install verification failed/,
    );
  } finally {
    await fixture.cleanup();
  }
});

test('install verifies, installs and validates the x64 payload with silent Inno flags', async () => {
  const fixture = await makeFixture();
  const { calls, spawn } = spawnRecorder();
  try {
    const code = await install({ platform: 'win32', arch: 'x64', root: fixture.root, env: fixture.env, spawn, log: () => {} });
    assert.equal(code, 0);
    assert.equal(calls.length, 2);
    assert.ok(calls[0].file.endsWith(join('payload', 'DevNavSetup-x64.exe')));
    assert.deepEqual(calls[0].args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
    assert.ok(calls[1].file.endsWith(join('Programs', 'DevNav', 'dev.exe')));
    assert.deepEqual(calls[1].args, ['--version']);
  } finally {
    await fixture.cleanup();
  }
});

test('install selects the ARM64 payload on ARM64 machines', async () => {
  const fixture = await makeFixture();
  const { calls, spawn } = spawnRecorder();
  try {
    await install({ platform: 'win32', arch: 'arm64', root: fixture.root, env: fixture.env, spawn, log: () => {} });
    assert.ok(calls[0].file.endsWith(join('payload', 'DevNavSetup-arm64.exe')));
  } finally {
    await fixture.cleanup();
  }
});

test('reinstall and upgrade run the same verified installer flow', async () => {
  const fixture = await makeFixture();
  const { calls, spawn } = spawnRecorder();
  try {
    await install({ platform: 'win32', arch: 'x64', root: fixture.root, env: fixture.env, spawn, log: () => {} });
    await install({ platform: 'win32', arch: 'x64', root: fixture.root, env: fixture.env, spawn, log: () => {} });
    assert.equal(calls.length, 4);
    assert.deepEqual(calls[2].args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
  } finally {
    await fixture.cleanup();
  }
});
