import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

/**
 * docs/*.md の動的な数値・リストを最新コードベースから再生成する。
 *
 * docs ファイル内の以下のマーカーで囲まれた領域を置換する:
 *   <!-- AUTO:KEY -->
 *   ...自動生成される内容...
 *   <!-- /AUTO:KEY -->
 *
 * 使い方:
 *   npm run docs:update     (ローカルで手動実行)
 *   GitHub Actions で週次 cron + push trigger で自動実行
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, '..');
const DOCS = path.join(ROOT, 'docs');
const DATA = path.join(ROOT, 'data');
const MIGRATIONS = path.join(ROOT, 'supabase', 'migrations');
const HTML_PATH = path.join(ROOT, 'index.html');

// ===== Helpers =====

function fileExists(p) {
    try { fs.accessSync(p); return true; } catch { return false; }
}

function readUtf8(p) {
    return fs.readFileSync(p, 'utf8');
}

function countCsvRows(csvPath) {
    const text = readUtf8(csvPath);
    // CSV は改行を含む quoted field を持ち得るため、簡易的にデータ行を数える。
    // 引用符の状態をトラッキングして行数を厳密に数える。
    let inQuotes = false;
    let rows = 0;
    for (let i = 0; i < text.length; i++) {
        const ch = text[i];
        if (ch === '"') {
            // エスケープ ""
            if (inQuotes && text[i + 1] === '"') { i++; continue; }
            inQuotes = !inQuotes;
        } else if (ch === '\n' && !inQuotes) {
            rows++;
        }
    }
    // 最終行が改行で終わらないケース
    if (text.length > 0 && text[text.length - 1] !== '\n') rows++;
    // ヘッダ行を引く
    return Math.max(0, rows - 1);
}

function todayJst() {
    // GitHub Actions の TZ は UTC。日本時間に補正
    const now = new Date(Date.now() + 9 * 3600 * 1000);
    const yyyy = now.getUTCFullYear();
    const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(now.getUTCDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
}

function getAppVersion() {
    const html = readUtf8(HTML_PATH);
    const m = html.match(/window\.APP_VERSION\s*=\s*['"]([^'"]+)['"]/);
    return m ? m[1] : 'unknown';
}

function getIndexHtmlStats() {
    const text = readUtf8(HTML_PATH);
    const lines = text.split('\n').length;
    const sizeKb = Math.round(text.length / 1024);
    return { lines, sizeKb };
}

// CSV を業務的に意味のある順序で並べる (tasks → rules → questions → … )
const CSV_ORDER = [
    'tasks_master.csv',
    'rules_master.csv',
    'questions_master.csv',
    'task_content_master.csv',
    'phase_master.csv',
    'message_master.csv',
    'task_expert_map.csv',
    'channel_override_master.csv',
    'locale_override_master.csv',
];

function listCsvFiles() {
    const all = fs.readdirSync(DATA)
        .filter(f => f.endsWith('.csv'));
    // CSV_ORDER に列挙された順 → 残りはアルファベット順で末尾追加
    const ordered = [];
    for (const name of CSV_ORDER) {
        if (all.includes(name)) ordered.push(name);
    }
    for (const name of all.sort()) {
        if (!ordered.includes(name)) ordered.push(name);
    }
    return ordered.map(f => ({
        name: f,
        rows: countCsvRows(path.join(DATA, f))
    }));
}

function listMigrations() {
    if (!fileExists(MIGRATIONS)) return [];
    return fs.readdirSync(MIGRATIONS)
        .filter(f => f.endsWith('.sql'))
        .sort()
        .map(f => {
            const text = readUtf8(path.join(MIGRATIONS, f));
            // 最初のコメント行を要約として拾う
            const m = text.match(/^--\s*(?:=+\s*)?(?:\n--\s*)?(?:[^\n]*?:|--)?\s*([^\n]+)/m);
            const summary = (m ? m[1] : '').trim();
            return { name: f, summary };
        });
}

// ===== マーカー置換 =====

function replaceMarker(content, key, newBody) {
    const open = `<!-- AUTO:${key} -->`;
    const close = `<!-- /AUTO:${key} -->`;
    const re = new RegExp(
        escapeRegExp(open) + '[\\s\\S]*?' + escapeRegExp(close),
        'g'
    );
    if (!re.test(content)) return content; // マーカー無し → スキップ
    return content.replace(re, () => `${open}\n${newBody.trim()}\n${close}`);
}

function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// ===== 各セクションの生成 =====

function buildCsvStatsTable(csvs) {
    const lines = ['| ファイル | データ行数 |', '|---|---|'];
    for (const c of csvs) {
        lines.push(`| \`${c.name}\` | ${c.rows} |`);
    }
    return lines.join('\n');
}

function buildMigrationList(migrations) {
    if (migrations.length === 0) return '_(マイグレーションなし)_';
    return migrations.map(m => `- \`${m.name}\``).join('\n');
}

function buildIndexStats(stats) {
    return `- 行数: 約 ${Math.round(stats.lines / 1000)}k 行 (実測 ${stats.lines.toLocaleString()} 行)\n- ファイルサイズ: 約 ${stats.sizeKb} KB`;
}

function buildAppVersion(v) {
    return `\`${v}\``;
}

function buildLastUpdated(date) {
    return date;
}

// ===== メイン =====

function processFile(filePath, replacements) {
    if (!fileExists(filePath)) return false;
    const original = readUtf8(filePath);
    let content = original;
    for (const [key, body] of Object.entries(replacements)) {
        content = replaceMarker(content, key, body);
    }
    if (content !== original) {
        fs.writeFileSync(filePath, content, 'utf8');
        return true;
    }
    return false;
}

function main() {
    console.log('[docs:update] collecting metrics...');
    const csvs = listCsvFiles();
    const migrations = listMigrations();
    const indexStats = getIndexHtmlStats();
    const appVersion = getAppVersion();
    const date = todayJst();

    console.log(`  CSVs:           ${csvs.length} files`);
    console.log(`  Migrations:     ${migrations.length} files`);
    console.log(`  index.html:     ${indexStats.lines} lines, ${indexStats.sizeKb}KB`);
    console.log(`  APP_VERSION:    ${appVersion}`);
    console.log(`  date:           ${date}`);

    const replacements = {
        'last-updated': buildLastUpdated(date),
        'csv-stats': buildCsvStatsTable(csvs),
        'migrations-list': buildMigrationList(migrations),
        'app-version': buildAppVersion(appVersion),
        'index-stats': buildIndexStats(indexStats),
    };

    const targets = [
        'README.md',
        'architecture.md',
        'business-logic.md',
        'data-model.md',
        'migration-options.md',
    ].map(f => path.join(DOCS, f));

    let changed = 0;
    for (const t of targets) {
        if (processFile(t, replacements)) {
            console.log(`  updated: ${path.relative(ROOT, t)}`);
            changed++;
        }
    }
    console.log(`[docs:update] done. ${changed} file(s) updated.`);
}

main();
