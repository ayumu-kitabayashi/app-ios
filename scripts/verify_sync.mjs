import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

/**
 * index.html 埋め込みCSVブロックの検証スクリプト
 *
 * task_content_master / locale_override_master の列数が揃っているか、
 * 地域固有キーワードが task_content_master に紛れ込んでいないかを確認する。
 *
 * 使い方: npm run verify-csv
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const HTML_PATH = path.resolve(__dirname, '..', 'index.html');
const html = fs.readFileSync(HTML_PATH, 'utf8');

function extractBlock(keyName, nextKey) {
    const start = html.indexOf(`${keyName}: String.raw\``);
    if (start === -1) return null;
    const contentStart = start + `${keyName}: String.raw\``.length;
    const end = html.indexOf(`\`,\n            ${nextKey}:`, contentStart);
    return html.slice(contentStart, end);
}

function checkCsv(label, content, expectedCols) {
    const lines = content.split('\n');
    const colCounts = {};
    lines.forEach((line) => {
        let count = 0, inQ = false;
        for (const c of line) {
            if (c === '"') inQ = !inQ;
            else if (c === ',' && !inQ) count++;
        }
        const cols = count + 1;
        colCounts[cols] = (colCounts[cols] || 0) + 1;
    });
    console.log(`${label}: ${lines.length} rows, col distribution = ${JSON.stringify(colCounts)}`);
    if (expectedCols && colCounts[expectedCols] !== lines.length) {
        console.log(`  WARNING: expected all rows to have ${expectedCols} columns`);
        return false;
    }
    return true;
}

const taskBlock = extractBlock('task_content_master', 'phase_master');
const localeBlock = extractBlock('locale_override_master', 'channel_override_master');

let ok = true;
ok = checkCsv('task_content_master', taskBlock, 12) && ok;
ok = checkCsv('locale_override_master', localeBlock, 4) && ok;

// 地域固有キーワードが task_content_master に紛れ込んでいないか
const regional = ['旭川', '北竜', '深川', '砂川', '雨竜', 'きたそらち', '0164-', '0125-', '0166-'];
const hits = regional.filter((r) => taskBlock.includes(r));
if (hits.length) {
    console.log('  WARNING: regional keywords in task_content_master:', hits);
    ok = false;
} else {
    console.log('regional keywords in task_content_master: NONE');
}

process.exit(ok ? 0 : 1);
