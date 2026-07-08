import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const HTML_PATH = path.resolve(__dirname, '..', 'index.html');

const html = fs.readFileSync(HTML_PATH, 'utf8');
const scripts = html.match(/<script[^>]*>([\s\S]*?)<\/script>/g) || [];
let ok = 0, fail = 0;
scripts.forEach((s, i) => {
    const body = s.replace(/^<script[^>]*>/, '').replace(/<\/script>$/, '');
    if (!body.trim()) return;
    try {
        // eslint-disable-next-line no-new-func
        new Function(body);
        ok++;
    } catch (e) {
        fail++;
        console.log('script[' + i + ']:', e.message);
    }
});
console.log('Scripts OK:', ok, '/', (ok + fail));
process.exit(fail > 0 ? 1 : 0);
