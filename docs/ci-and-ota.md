# ReliefNote — クラウドビルド(Codemagic) ＋ OTA(Capgo)

「段1.5」構成。**手元 Xcode なしでストアに出し、以後の更新は審査なしで即配信**する。
Bodilab(EAS)とは別 toolchain（[[project_app_build_toolchains]] 参照）。リポジトリ側の設定は導入済み。以下は**あなたの手動作業**（アカウント・鍵）。

---

## 1回だけの初期設定

### A. App Store Connect API キー（署名の自動化に使う）
1. App Store Connect → ユーザとアクセス → **Integrations / Keys** → App Store Connect API → 鍵を発行（Role: App Manager 以上）
2. 控える：**Issuer ID / Key ID / .p8 秘密鍵ファイル**

### B. App Store Connect に ReliefNote の App レコードを作成
1. `appstoreconnect.apple.com/apps` → 「＋」→ 新規App
2. プラットフォーム iOS / 名前「ReliefNote」/ Bundle ID **com.reliefnote.app**（Developer portal に無ければ先に登録）/ SKU 任意

### C. Codemagic（クラウドビルド）
1. codemagic.io に GitHub でログイン → リポジトリ **reliefnote** を接続
2. Teams → Integrations → **App Store Connect** に A の鍵を登録（名前を付ける）
3. リポジトリ直下の `codemagic.yaml` の **`<ASC_KEY_NAME>`** をその名前に置換（このファイル）
4. ビルド開始 → 成功すると自動で **TestFlight** に上がる（`submit_to_testflight: true`）

### D. Capgo（OTA / ライブアップデート）
1. capgo.app でアカウント作成 → APIトークン取得
2. リポジトリで:
   ```bash
   npx @capgo/cli login <APIトークン>
   npx @capgo/cli app add com.reliefnote.app
   ```
3. プラグインは導入済み（`@capgo/capacitor-updater`・`capacitor.config.json` に `autoUpdate:true`・`index.html` で `notifyAppReady()` 呼び出し済み）

---

## 定常運用（ここが「楽」の本体）

### ネイティブに触らない変更（HTML/CSS/JS/画像＝ほぼ全部）→ OTAで即配信・審査なし
```bash
npm run build:www
npx @capgo/cli bundle upload --channel production
```
→ 端末が次回起動時に自動ダウンロード＆適用（`notifyAppReady()` が起動確認、失敗時は自動ロールバック）。

### ネイティブを変えた時だけ（プラグイン追加・iOS設定変更・初回提出）→ 再ビルド＋審査
- Codemagic で再ビルド（`codemagic.yaml`）→ TestFlight/審査。
- ⚠️ Apple 規約：OTA はアプリの主目的を変えない範囲（JS/アセット更新）に限る。大きな機能追加は再提出。

---

## まとめ
| 変更の種類 | 手順 | 審査 |
|---|---|---|
| 文言・UI・ロジック・画像 | `@capgo/cli bundle upload` | 不要（即時） |
| プラグイン/ネイティブ設定/初回 | Codemagic 再ビルド | 必要 |
