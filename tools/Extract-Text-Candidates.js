#!/usr/bin/env node
// Reliable candidate extraction for compressed JavaScript. Acorn is vendored
// under tools/vendor so this audit does not depend on a global npm install.
const fs = require('fs');
const path = require('path');

async function main() {
  const {Parser} = await import('./vendor/acorn/acorn.mjs');
  const root = path.resolve(process.argv[2] || 'chinese-patch/source/app-asar');
  const outJson = path.resolve(process.argv[3] || 'chinese-patch/translation/text-candidates.json');
  const outCsv = path.resolve(process.argv[4] || 'chinese-patch/translation/text-candidates.csv');
  const rows = [];
  let nextId = 1;
  const add = (file, line, kind, text, offset, context = '') => {
    if (typeof text !== 'string') return;
    const clean = text.replace(/\\([\\'"`])/g, '$1').trim();
    if (clean.length < 2 || !/[A-Za-z]{2,}|\s/.test(clean)) return;
    if (/^[A-Za-z_$][A-Za-z0-9_$.-]*$/.test(clean)) return;
    rows.push({id:`T${String(nextId++).padStart(6,'0')}`, file, line, offset,
      kind, context, text:clean,
      review:'translate only when rendered/logged; preserve placeholders, tags, keys and control words'});
  };
  const propertyName = node => {
    if (!node) return '';
    if (node.type === 'Identifier') return node.name;
    if (node.type === 'Literal') return String(node.value ?? '');
    return '';
  };
  const calleeName = node => {
    if (!node) return '';
    if (node.type === 'Identifier') return node.name;
    if (node.type === 'MemberExpression') return propertyName(node.property);
    return '';
  };
  const describeContext = ancestors => {
    const parts = [];
    for (let i = ancestors.length - 1; i >= 0; i--) {
      const n = ancestors[i];
      if (n.type === 'Property') {
        const name = propertyName(n.key);
        if (name) parts.push(`property:${name}`);
        break;
      }
    }
    for (let i = ancestors.length - 1; i >= 0; i--) {
      const n = ancestors[i];
      if (n.type === 'CallExpression') {
        const name = calleeName(n.callee);
        if (name) parts.push(`call:${name}`);
        break;
      }
    }
    for (let i = ancestors.length - 1; i >= 0; i--) {
      const n = ancestors[i];
      if (n.type === 'AssignmentExpression' && n.left?.type === 'MemberExpression') {
        const name = propertyName(n.left.property);
        if (name) parts.push(`assign:${name}`);
        break;
      }
    }
    return parts.join('|');
  };
  // A literal embedded in a concatenation with a runtime value is not a
  // standalone player-visible string. It is audited by
  // Extract-Dynamic-Text-Templates.js as part of the assembled message.
  const hasDynamicConcat = node => {
    if (!node) return false;
    if (node.type === 'TemplateLiteral') return node.expressions.length > 0;
    if (node.type !== 'BinaryExpression' || node.operator !== '+') return false;
    const isStaticString = child => child?.type === 'Literal' && typeof child.value === 'string';
    return !isStaticString(node.left) || !isStaticString(node.right) ||
      hasDynamicConcat(node.left) || hasDynamicConcat(node.right);
  };
  const walk = (node, file, source, ancestors = []) => {
    if (!node || typeof node !== 'object') return;
    const embeddedInDynamic = ancestors.some(ancestor =>
      (ancestor.type === 'BinaryExpression' && ancestor.operator === '+' && hasDynamicConcat(ancestor)) ||
      (ancestor.type === 'TemplateLiteral' && ancestor.expressions.length > 0));
    if (node.type === 'Literal' && typeof node.value === 'string' && !embeddedInDynamic) {
      const line = source.slice(0, node.start).split('\n').length;
      add(file, line, 'js-string', node.value, node.start, describeContext(ancestors));
    } else if (node.type === 'TemplateLiteral' && !embeddedInDynamic) {
      for (const q of node.quasis) {
        const line = source.slice(0, q.start).split('\n').length;
        add(file, line, 'js-template', q.value.raw, q.start, describeContext(ancestors));
      }
    }
    for (const [key, value] of Object.entries(node)) {
      if (key === 'start' || key === 'end' || key === 'loc') continue;
      if (Array.isArray(value)) value.forEach(v => walk(v, file, source, ancestors.concat(node)));
      else if (value && typeof value === 'object') walk(value, file, source, ancestors.concat(node));
    }
  };
  const files = [];
  const visit = dir => {
    for (const ent of fs.readdirSync(dir, {withFileTypes:true})) {
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) visit(full); else files.push(full);
    }
  };
  visit(root);
  for (const full of files) {
    const rel = path.relative(root, full).replaceAll(path.sep, '/');
    const ext = path.extname(full).toLowerCase();
    const source = fs.readFileSync(full, 'utf8');
    if (ext === '.js') {
      let ast;
      try {
        ast = Parser.parse(source, {ecmaVersion:'latest', sourceType:'script', allowAwaitOutsideFunction:true, allowHashBang:true});
      } catch (err) {
        console.error(`parse failed: ${rel}: ${err.message}`);
        continue;
      }
      walk(ast, rel, source);
    } else if (ext === '.html' || ext === '.htm') {
      for (const m of source.matchAll(/(?:^|>)([^<]+)(?=<)/gis)) {
        const offset = m.index + (m[0].startsWith('>') ? 1 : 0);
        add(rel, source.slice(0,offset).split('\n').length, 'html-text', m[1], offset, 'html:text');
      }
      for (const m of source.matchAll(/(data-help|data-helptitle|aria-label|placeholder|title)\s*=\s*["']([^"']+)/gis)) add(rel, source.slice(0,m.index).split('\n').length, `html-${m[1].toLowerCase()}`, m[2], m.index, `html:${m[1].toLowerCase()}`);
    }
  }
  const seen = new Set();
  const unique = rows.filter(row => { const key = `${row.file}|${row.offset}|${row.text}`; if (seen.has(key)) return false; seen.add(key); return true; });
  fs.writeFileSync(outJson, JSON.stringify(unique, null, 2), 'utf8');
  const csvEsc = s => `"${String(s ?? '').replaceAll('"','""')}"`;
  fs.writeFileSync(outCsv, ['id,file,line,offset,kind,context,text,review', ...unique.map(r => [r.id,r.file,r.line,r.offset,r.kind,r.context,r.text,r.review].map(csvEsc).join(','))].join('\n')+'\n', 'utf8');
  console.log(`Text candidates: ${unique.length}`);
}
main().catch(err => { console.error(err); process.exit(1); });
