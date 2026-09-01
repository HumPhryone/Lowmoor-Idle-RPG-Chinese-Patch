#!/usr/bin/env node
// Independent coverage pass: verify every text-bearing ASAR resource is
// represented in the candidate inventory. It deliberately does not decide
// whether a string is visible; that decision belongs to the visibility audit.
const fs = require('fs');
const path = require('path');

const root = path.resolve(process.argv[2] || 'chinese-patch/source/app-asar');
const candidatesPath = path.resolve(process.argv[3] || 'chinese-patch/translation/text-candidates.json');
const reportPath = path.resolve(process.argv[4] || 'chinese-patch/inventory/resource-coverage.json');
const candidates = JSON.parse(fs.readFileSync(candidatesPath, 'utf8'));
const candidateFiles = new Set(candidates.map(item => item.file));
const textExtensions = new Set(['.js', '.html', '.htm']);
const files = [];
const visit = directory => {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) visit(full); else files.push(full);
  }
};
visit(root);
const rows = files.map(full => {
  const relative = path.relative(root, full).replaceAll(path.sep, '/');
  const extension = path.extname(full).toLowerCase();
  const size = fs.statSync(full).size;
  const textLike = textExtensions.has(extension);
  const ignoredTextResource = ['.json', '.css'].includes(extension);
  const hasCandidates = candidateFiles.has(relative);
  return {file: relative, size, extension, textLike, ignoredTextResource, hasCandidates};
});
const uncoveredText = rows.filter(row => row.textLike && !row.hasCandidates);
const report = {
  root,
  files: rows,
  summary: {
    totalFiles: rows.length,
    textLikeFiles: rows.filter(row => row.textLike).length,
    coveredTextFiles: rows.filter(row => row.textLike && row.hasCandidates).length,
    uncoveredTextFiles: uncoveredText.length,
    uncoveredText
  }
};
fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n', 'utf8');
console.log(JSON.stringify(report.summary, null, 2));
process.exitCode = uncoveredText.length ? 1 : 0;
