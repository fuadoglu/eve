import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const files = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (['.git', 'node_modules', '.next'].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.md')) files.push(full);
  }
}
walk(root);
const errors = [];
for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  for (const match of source.matchAll(/\]\(([^)]+)\)/g)) {
    const target = match[1].split('#')[0];
    if (!target || /^(https?:|mailto:)/.test(target)) continue;
    const resolved = path.resolve(path.dirname(file), target);
    if (!resolved.startsWith(root + path.sep) || !fs.existsSync(resolved)) {
      errors.push(path.relative(root, file) + ': ' + target);
    }
  }
}
const prd = fs.readFileSync(path.join(root, 'docs/01-product/PRD.md'), 'utf8');
const tests = fs.readFileSync(path.join(root, 'docs/04-quality/ACCEPTANCE.md'), 'utf8');
const backlog = fs.readFileSync(path.join(root, 'docs/05-delivery/BACKLOG.md'), 'utf8');
for (let i = 1; i <= 16; i++) if (!prd.includes('| R' + String(i).padStart(2, '0') + ' |')) errors.push('Missing R' + i);
for (let i = 1; i <= 36; i++) if (!tests.includes('| AT' + String(i).padStart(2, '0') + ' |')) errors.push('Missing AT' + i);
for (let i = 1; i <= 30; i++) if (!backlog.includes('| EVE-' + String(i).padStart(3, '0') + ' |')) errors.push('Missing EVE-' + i);
if (errors.length) {
  process.stderr.write(errors.join('\n') + '\n');
  process.exitCode = 1;
} else {
  process.stdout.write('Docs OK: ' + files.length + ' Markdown files; R01-16, AT01-36, EVE-001-030.\n');
}
