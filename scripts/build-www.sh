#!/usr/bin/env bash
# Capacitor 用の www/ を、Web 版の正本アセットから組み立てる。
# index.html は reliefnote_app 直下が正本。www/ はビルド生成物（gitignore 対象）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"

rm -rf "$WWW"
mkdir -p "$WWW"

# 必要なアセットだけをコピー（node_modules / ios / www 自身は含めない）
cp "$ROOT/index.html"      "$WWW/"
cp "$ROOT/favicon.png"     "$WWW/" 2>/dev/null || true
cp "$ROOT/logo.png"        "$WWW/" 2>/dev/null || true
cp "$ROOT/sw.js"           "$WWW/" 2>/dev/null || true
cp -R "$ROOT/data"         "$WWW/" 2>/dev/null || true
cp -R "$ROOT/images"       "$WWW/" 2>/dev/null || true

echo "www/ を組み立てました: $WWW"
