#!/usr/bin/env node
// Reconstruct string-concatenation expressions so dynamic UI and log output
// can be audited as complete messages rather than isolated literals.
const fs = require('fs');
const path = require('path');

async function main() {
  const {Parser} = await import('./vendor/acorn/acorn.mjs');
  const sourcePath = path.resolve(process.argv[2] || 'chinese-patch/source/app-asar/game/lowmoor.js');
  const outputPath = path.resolve(process.argv[3] || 'chinese-patch/translation/dynamic-text-templates.json');
  const source = fs.readFileSync(sourcePath, 'utf8');
  const ast = Parser.parse(source, {
    ecmaVersion: 'latest', sourceType: 'script', allowAwaitOutsideFunction: true, allowHashBang: true
  });
  const rows = [];

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
    const property = [...ancestors].reverse().find(node => node.type === 'Property');
    if (property) parts.push(`property:${propertyName(property.key)}`);
    const call = [...ancestors].reverse().find(node => node.type === 'CallExpression');
    if (call) parts.push(`call:${calleeName(call.callee)}`);
    const assignment = [...ancestors].reverse().find(node =>
      node.type === 'AssignmentExpression' && node.left?.type === 'MemberExpression');
    if (assignment) parts.push(`assign:${propertyName(assignment.left.property)}`);
    return parts.filter(part => !part.endsWith(':')).join('|');
  };
  const dynamicLabel = node => {
    const raw = source.slice(node.start, node.end).replace(/\s+/g, ' ').trim();
    return raw.length <= 120 ? raw : `${raw.slice(0, 117)}...`;
  };
  const flatten = (node, parts) => {
    if (node.type === 'BinaryExpression' && node.operator === '+') {
      flatten(node.left, parts);
      flatten(node.right, parts);
      return;
    }
    if (node.type === 'TemplateLiteral') {
      node.quasis.forEach((quasi, index) => {
        if (quasi.value.cooked) parts.push({type: 'text', value: quasi.value.cooked});
        if (index < node.expressions.length) parts.push({type: 'dynamic', value: dynamicLabel(node.expressions[index])});
      });
      return;
    }
    if (node.type === 'Literal' && typeof node.value === 'string') {
      if (node.value) parts.push({type: 'text', value: node.value});
      return;
    }
    parts.push({type: 'dynamic', value: dynamicLabel(node)});
  };
  const add = (node, ancestors) => {
    const parts = [];
    flatten(node, parts);
    const staticText = parts.filter(part => part.type === 'text').map(part => part.value).join('');
    if (!/[A-Za-z]{2,}/.test(staticText) || !parts.some(part => part.type === 'dynamic')) return;
    let dynamicIndex = 0;
    const template = parts.map(part => part.type === 'text' ? part.value : `{D${++dynamicIndex}}`).join('');
    rows.push({
      id: `D${String(rows.length + 1).padStart(5, '0')}`,
      line: source.slice(0, node.start).split('\n').length,
      offset: node.start,
      context: describeContext(ancestors),
      template,
      staticText,
      dynamics: parts.filter(part => part.type === 'dynamic').map(part => part.value),
      source: source.slice(node.start, node.end)
    });
  };
  const walk = (node, ancestors = []) => {
    if (!node || typeof node !== 'object') return;
    const parent = ancestors[ancestors.length - 1];
    if (node.type === 'BinaryExpression' && node.operator === '+' &&
        !(parent?.type === 'BinaryExpression' && parent.operator === '+')) add(node, ancestors);
    if (node.type === 'TemplateLiteral' && node.expressions.length &&
        !(parent?.type === 'BinaryExpression' && parent.operator === '+')) add(node, ancestors);
    for (const [key, value] of Object.entries(node)) {
      if (key === 'start' || key === 'end' || key === 'loc') continue;
      if (Array.isArray(value)) value.forEach(child => walk(child, ancestors.concat(node)));
      else if (value && typeof value === 'object') walk(value, ancestors.concat(node));
    }
  };

  walk(ast);
  fs.writeFileSync(outputPath, JSON.stringify(rows, null, 2) + '\n', 'utf8');
  console.log(`Dynamic text templates: ${rows.length}`);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
