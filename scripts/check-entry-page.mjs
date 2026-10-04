import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDirectory, '..');
const abilityPath = join(projectRoot, 'entry', 'src', 'main', 'ets', 'entryability', 'EntryAbility.ets');
const profilePath = join(projectRoot, 'entry', 'src', 'main', 'resources', 'base', 'profile', 'main_pages.json');

const abilitySource = readFileSync(abilityPath, 'utf8');
const loadContentMatch = abilitySource.match(/windowStage\.loadContent\(\s*['"]([^'"]+)['"]/);

if (loadContentMatch === null) {
  throw new Error(`Unable to find windowStage.loadContent() in ${abilityPath}`);
}

const entryPage = loadContentMatch[1];
const pageProfile = JSON.parse(readFileSync(profilePath, 'utf8'));

if (!Array.isArray(pageProfile.src)) {
  throw new Error(`${profilePath} must contain a src array`);
}

if (!pageProfile.src.includes(entryPage)) {
  throw new Error(
    `Startup page "${entryPage}" is not registered in main_pages.json. Registered pages: ${pageProfile.src.join(', ')}`
  );
}

const entrySourcePath = join(projectRoot, 'entry', 'src', 'main', 'ets', `${entryPage}.ets`);
if (!existsSync(entrySourcePath)) {
  throw new Error(`Registered startup page source does not exist: ${entrySourcePath}`);
}

console.log(`Startup page contract valid: ${entryPage}`);
