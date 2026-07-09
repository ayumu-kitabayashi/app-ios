// www/index.html を圧縮する（起動時パースを軽くする）。
// 正本 index.html は無加工のまま。www/ はビルド生成物なのでここで圧縮する。
// テンプレートリテラル内（INLINE_CSV や読み物本文）は terser が保持するので安全。
import { minify } from 'html-minifier-terser';
import fs from 'fs';

const target = process.argv[2] || 'www/index.html';
const src = fs.readFileSync(target, 'utf8');
const before = Buffer.byteLength(src);

const out = await minify(src, {
  collapseWhitespace: true,
  conservativeCollapse: true, // 表示テキストの単一スペースは保持
  removeComments: true,
  minifyCSS: true,
  minifyJS: { compress: { drop_console: false }, mangle: false }, // 名前は保持（安全側）
});

fs.writeFileSync(target, out);
const after = Buffer.byteLength(out);
console.log(
  `minify: ${(before / 1024 / 1024).toFixed(2)}MB -> ${(after / 1024 / 1024).toFixed(2)}MB ` +
  `(-${(100 * (1 - after / before)).toFixed(0)}%)`
);
