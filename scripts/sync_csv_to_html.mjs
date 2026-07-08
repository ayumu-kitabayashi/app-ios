import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

/**
 * CSVマスター → index.html 埋め込みブロックへの同期スクリプト
 *
 * data/task_content_master.csv と data/locale_override_master.csv の内容を
 * index.html 内の対応する String.raw ブロックに書き戻す。
 *
 * 使い方: npm run sync-csv
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');
const HTML_PATH = path.join(ROOT, 'index.html');
const TASK_CSV = path.join(ROOT, 'data', 'task_content_master.csv');
const LOCALE_CSV = path.join(ROOT, 'data', 'locale_override_master.csv');

function loadCsv(p) {
    let s = fs.readFileSync(p, 'utf8');
    // 末尾の空行を削って、閉じバッククォートが最終行直後に来るようにする
    s = s.replace(/\s+$/, '');
    return s;
}

function replaceBlock(html, keyName, newContent, nextKeyName) {
    const startMarker = `${keyName}: String.raw\``;
    const startIdx = html.indexOf(startMarker);
    if (startIdx === -1) throw new Error(`start marker not found: ${keyName}`);
    const contentStart = startIdx + startMarker.length;
    const endMarker = `\`,\n            ${nextKeyName}:`;
    const endIdx = html.indexOf(endMarker, contentStart);
    if (endIdx === -1) throw new Error(`end marker not found: ${keyName} -> ${nextKeyName}`);
    const before = html.slice(0, contentStart);
    const after = html.slice(endIdx);
    const oldLen = endIdx - contentStart;
    console.log(`[${keyName}] old length: ${oldLen}, new length: ${newContent.length}`);
    return before + newContent + after;
}

let html = fs.readFileSync(HTML_PATH, 'utf8');
const originalLen = html.length;

const taskCsv = loadCsv(TASK_CSV);
const localeCsv = loadCsv(LOCALE_CSV);

console.log(`task_content_master: ${taskCsv.split('\n').length} rows`);
console.log(`locale_override_master: ${localeCsv.split('\n').length} rows`);

html = replaceBlock(html, 'task_content_master', taskCsv, 'phase_master');
html = replaceBlock(html, 'locale_override_master', localeCsv, 'channel_override_master');

fs.writeFileSync(HTML_PATH, html);
console.log(`html length: ${originalLen} -> ${html.length}`);
console.log('done.');
