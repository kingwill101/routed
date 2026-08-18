import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const docsDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(docsDir, '..', '..');
const packagesRoot = path.join(repoRoot, 'packages');
const catalogPath = path.join(docsDir, '..', 'package-catalog.md');

const failures = [];

function read(file) {
  return fs.readFileSync(file, 'utf8');
}

function packageManifests(directory) {
  const manifests = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    if (entry.name === 'example' || entry.name === 'examples') continue;
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      manifests.push(...packageManifests(entryPath));
      continue;
    }
    if (entry.name === 'pubspec.yaml') manifests.push(entryPath);
  }
  return manifests;
}

const catalog = read(catalogPath);
const manifests = packageManifests(packagesRoot);

for (const manifestPath of manifests) {
  const manifest = read(manifestPath);
  const name = manifest.match(/^name:\s*(\S+)\s*$/m)?.[1];
  const version = manifest.match(/^version:\s*(\S+)\s*$/m)?.[1];
  if (!name || !version) {
    failures.push(`${path.relative(repoRoot, manifestPath)} is missing name/version`);
    continue;
  }

  const row = catalog
    .split('\n')
    .find((line) => line.includes(`[\`${name}\`]`));
  if (!row) {
    failures.push(`${name} is missing from docs/package-catalog.md`);
  } else if (!row.includes(`\`${version}\``)) {
    failures.push(`${name} catalog version does not match ${version}`);
  }
}

function readmes(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...readmes(entryPath));
    } else if (entry.name.toLowerCase() === 'readme.md') {
      files.push(entryPath);
    }
  }
  return files;
}

for (const readmePath of readmes(packagesRoot)) {
  const contents = read(readmePath);
  const relativePath = path.relative(repoRoot, readmePath);
  for (const pattern of [
    /package:[^\s)`]+\/src/,
    /routed\/src/,
    /server_data\/src/,
    /\brouter\.(get|post|put|patch|delete)\(/,
    /\bEngine\(\)/,
  ]) {
    if (pattern.test(contents)) {
      failures.push(`${relativePath} contains disallowed public example/path: ${pattern}`);
    }
  }
}

if (failures.length > 0) {
  console.error('Documentation audit failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Documentation audit passed (${manifests.length} package manifests checked).`);
