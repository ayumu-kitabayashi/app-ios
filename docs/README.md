# ReliefNote 技術ドキュメント

ReliefNote の技術仕様・設計・移行プランをまとめたディレクトリです。

**最終自動更新**: <!-- AUTO:last-updated -->
2026-07-20
<!-- /AUTO:last-updated --> / **現在のアプリバージョン**: <!-- AUTO:app-version -->
`rn-2026-04-23-phase7c`
<!-- /AUTO:app-version -->

## 目的別ガイド

### 「全体像を知りたい」
→ [`architecture.md`](./architecture.md)
スタック構成・各コンポーネントの責務・データフロー・依存サービス。
新規参加するエンジニアや CTO 候補に最初に渡す書類。

### 「ロジックを理解 / 移植したい」
→ [`business-logic.md`](./business-logic.md)
ルール DSL の文法・三値論理・タスク状態遷移・依存解決。
別言語に書き直す際の言語非依存仕様書。

### 「データ構造を理解したい」
→ [`data-model.md`](./data-model.md)
CSV マスター 9 本のスキーマ・Supabase テーブル・localStorage キー一覧。
DB 移行時の対応表として利用。

### 「将来の引き継ぎ・移行を計画したい」
→ [`migration-options.md`](./migration-options.md)
A: 現状維持 / B: フロント維持+API分離 / C: 全面書き換え の比較。
CTO 候補との会話に持参する資料。

### 「機能別の設計詳細」
- [`family-sharing-design.md`](./family-sharing-design.md) — 家族共有 (E2E 暗号化)
- [`partner-dashboard-design.md`](./partner-dashboard-design.md) — 葬儀社向けダッシュボード設計案
- [`ocr-extension-design.md`](./ocr-extension-design.md) — OCR 拡張 (将来)
- [`supabase-rls.md`](./supabase-rls.md) — Supabase RLS ポリシー

---

## 読む順番 (新規参加者向け)

1. **`architecture.md`** — 何が何をしているか
2. **`data-model.md`** — どんなデータを持っているか
3. **`business-logic.md`** — どう動いているか
4. **`migration-options.md`** — どこへ向かうか
5. その他、関心ある機能の設計書

各 30 分程度で読み切れる分量に整理しています。

---

## 更新ルール

- すべて Markdown、UTF-8、改行 LF
- 仕様変更時は対応するドキュメントも同じ PR で更新
- 「最終更新日」のフィールドを毎回更新
- 機能設計の新規ドキュメントは `<feature>-design.md` 命名規則
- ドキュメントが古くなったら `(更新が必要)` を冒頭に書く

---

## 関連リソース

- アプリ本体: `/index.html` (約 28k 行)
- データマスター: `/data/*.csv`
- AI チャット Worker: `/ai-chat-worker/`
- Supabase マイグレーション: `/supabase/migrations/`
- LP リポジトリ (別管理): `reliefnote-lp/`
