#!/usr/bin/env node
// DevNav bootstrap installer.
//
// This package is a transient delivery channel: it carries the canonical
// DevNav Inno Setup installers (built once by the release workflow) inside the
// npm tarball, verifies their SHA-256 hashes against release-manifest.json and
// delegates the actual installation to Inno. npm/Bun/pnpm/Yarn never own the
// installed files under %LOCALAPPDATA%\Programs\DevNav.
//
// Runtime dependencies: none. Only Node/Bun standard library APIs are used so
// the package works with lifecycle scripts disabled (no postinstall).

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createReadStream, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const PACKAGE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const INSTALLER_ARGS = ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'];

const ARCH_TO_ARTIFACT = new Map([
  ['x64', 'installer-x64'],
  ['arm64', 'installer-arm64'],
]);

const HELP = `DevNav bootstrap installer

Usage:
  devnav install      Verify and run the DevNav installer for this machine
  devnav --version    Print the bundled DevNav version
  devnav --help       Show this help

Package managers:
  bunx --bun @jacoboptimiza/devnav install
  npx --yes @jacoboptimiza/devnav install
  pnx @jacoboptimiza/devnav install
  yarn dlx -p @jacoboptimiza/devnav devnav install
`;

export class DevnavError extends Error {}

export function loadReleaseManifest(root = PACKAGE_ROOT) {
  const manifestPath = join(root, 'release-manifest.json');
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(manifestPath, 'utf8'));
  } catch (cause) {
    throw new DevnavError(`Cannot read release-manifest.json: ${cause.message}`);
  }
  if (parsed.schemaVersion !== 1 || typeof parsed.version !== 'string' || typeof parsed.artifacts !== 'object') {
    throw new DevnavError('release-manifest.json does not match schema version 1.');
  }
  return parsed;
}

export function selectInstallerArtifact(manifest, arch) {
  const artifactName = ARCH_TO_ARTIFACT.get(arch);
  if (!artifactName) {
    throw new DevnavError(`Unsupported Windows architecture: ${arch}. DevNav supports x64 and ARM64.`);
  }
  const artifact = manifest.artifacts[artifactName];
  if (!artifact || typeof artifact.file !== 'string' || typeof artifact.sha256 !== 'string') {
    throw new DevnavError(`release-manifest.json has no entry for ${artifactName}.`);
  }
  return artifact;
}

export async function sha256File(filePath) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk);
  }
  return hash.digest('hex');
}

export function installedExecutablePath(env = process.env) {
  const localAppData = env.LOCALAPPDATA;
  if (!localAppData) {
    throw new DevnavError('LOCALAPPDATA is not defined; cannot locate the DevNav installation.');
  }
  return join(localAppData, 'Programs', 'DevNav', 'dev.exe');
}

export async function install({
  platform = process.platform,
  arch = process.arch,
  env = process.env,
  root = PACKAGE_ROOT,
  spawn = spawnSync,
  log = console.log,
} = {}) {
  if (platform !== 'win32') {
    throw new DevnavError(`DevNav only runs on Windows; this platform is ${platform}.`);
  }
  const manifest = loadReleaseManifest(root);
  const artifact = selectInstallerArtifact(manifest, arch);
  const installerPath = join(root, 'payload', artifact.file);

  log(`Verifying ${artifact.file} (SHA-256)...`);
  const actualHash = await sha256File(installerPath);
  if (actualHash.toLowerCase() !== artifact.sha256.toLowerCase()) {
    throw new DevnavError(`SHA-256 mismatch for ${artifact.file}; the package is corrupted or tampered with. Aborting.`);
  }

  log(`Running the DevNav ${arch} installer silently...`);
  const installerResult = spawn(installerPath, INSTALLER_ARGS, { stdio: 'inherit' });
  if (installerResult.error) {
    throw new DevnavError(`Could not start the installer: ${installerResult.error.message}`);
  }
  if (installerResult.status !== 0) {
    throw new DevnavError(`The DevNav installer exited with code ${installerResult.status}.`);
  }

  const devExe = installedExecutablePath(env);
  const versionResult = spawn(devExe, ['--version'], { encoding: 'utf8' });
  if (versionResult.error) {
    throw new DevnavError(`The installer finished but dev.exe could not be started: ${versionResult.error.message}`);
  }
  const installedVersion = String(versionResult.stdout).trim();
  const expectedVersion = `dev-nav ${manifest.version}`;
  if (versionResult.status !== 0 || installedVersion !== expectedVersion) {
    throw new DevnavError(`Post-install verification failed: expected "${expectedVersion}", got "${installedVersion}".`);
  }

  log(`DevNav ${manifest.version} installed successfully. Open a new PowerShell 7 window and run: dev`);
  return 0;
}

export function bundledVersion(root = PACKAGE_ROOT) {
  return loadReleaseManifest(root).version;
}

async function main(argv) {
  const command = argv[0];
  try {
    switch (command) {
      case 'install':
        return await install();
      case '--version':
      case '-v':
      case 'version':
        console.log(bundledVersion());
        return 0;
      case '--help':
      case '-h':
      case 'help':
      case undefined:
        process.stdout.write(HELP);
        return 0;
      default:
        process.stderr.write(`devnav: unknown command "${command}"\n\n${HELP}`);
        return 1;
    }
  } catch (error) {
    if (error instanceof DevnavError) {
      process.stderr.write(`devnav: ${error.message}\n`);
      return 1;
    }
    throw error;
  }
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : '';
if (invokedPath && invokedPath === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      process.stderr.write(`devnav: unexpected failure: ${error.stack ?? error}\n`);
      process.exitCode = 1;
    },
  );
}
