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
const packageVersions = new Map();

function parseVersion(value) {
  const match = value.match(/(\d+)\.(\d+)\.(\d+)/);
  if (!match) return null;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

function compareVersions(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index];
  }
  return 0;
}

function incrementCaretUpperBound(version) {
  if (version[0] > 0) return [version[0] + 1, 0, 0];
  if (version[1] > 0) return [0, version[1] + 1, 0];
  return [0, 0, version[2] + 1];
}

function constraintSupportsVersion(constraint, version) {
  const normalized = constraint.replaceAll('"', '').replaceAll("'", '').trim();
  if (normalized === '' || normalized === 'any' || normalized === '*') return true;
  if (normalized.startsWith('path:') || normalized.startsWith('git:')) return true;

  const current = parseVersion(version);
  if (!current) return true;
  const terms = normalized.match(/(?:\^|>=|<=|>|<|=)?\d+\.\d+\.\d+(?:\+\d+)?/g);
  if (!terms || terms.length === 0) return true;

  return terms.every((term) => {
    const operator = term.match(/^(\^|>=|<=|>|<|=)?/)?.[1] ?? '';
    const target = parseVersion(term);
    if (!target) return true;
    const comparison = compareVersions(current, target);
    if (operator === '^') {
      return comparison >= 0 &&
          compareVersions(current, incrementCaretUpperBound(target)) < 0;
    }
    if (operator === '>=') return comparison >= 0;
    if (operator === '<=') return comparison <= 0;
    if (operator === '>') return comparison > 0;
    if (operator === '<') return comparison < 0;
    return comparison === 0;
  });
}

for (const manifestPath of manifests) {
  const manifest = read(manifestPath);
  const name = manifest.match(/^name:\s*(\S+)\s*$/m)?.[1];
  const version = manifest.match(/^version:\s*(\S+)\s*$/m)?.[1];
  if (!name || !version) {
    failures.push(`${path.relative(repoRoot, manifestPath)} is missing name/version`);
    continue;
  }
  packageVersions.set(name, version);

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

function siteDocs(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...siteDocs(entryPath));
    } else if (entry.name.endsWith('.mdx')) {
      files.push(entryPath);
    }
  }
  return files;
}

const documentationFiles = [
  ...readmes(packagesRoot),
  ...siteDocs(path.join(docsDir, '..', 'docs')),
];

for (const documentationPath of documentationFiles) {
  const contents = read(documentationPath);
  const relativePath = path.relative(repoRoot, documentationPath);
  if (documentationPath.startsWith(packagesRoot)) {
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

  for (const line of contents.split('\n')) {
    const dependency = line.match(/^\s{2}([A-Za-z0-9_]+):\s*(.+?)\s*$/);
    if (!dependency) continue;
    const [_, name, constraint] = dependency;
    const version = packageVersions.get(name);
    if (version && !constraintSupportsVersion(constraint, version)) {
      failures.push(
        `${relativePath} advertises ${name} with ${constraint}, which does not admit ${version}`,
      );
    }
  }
}

if (failures.length > 0) {
  console.error('Documentation audit failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `Documentation audit passed (${manifests.length} package manifests and ` +
  `${documentationFiles.length} user-facing documents checked).`,
);
