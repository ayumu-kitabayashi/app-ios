# ReliefNote iOS（App Store）ビルド手順

既存の Web 版（`index.html`）を **Capacitor** でネイティブ iOS アプリに包んで App Store に出す。
`index.html` が正本。`www/` と `ios/App/App/public/` はビルド生成物（gitignore 済み）。

> ⚠️ **Bodilab とは別 toolchain**。Bodilab は Expo managed で EAS クラウドビルド（`eas build`/`eas submit`・`ios/` を持たない・OTA可）。ReliefNote は Capacitor で `ios/` を同梱し **Xcode で Archive**（or Capacitor 対応クラウド）。手順を混同しない。

## 仕組み
- `scripts/build-www.sh` … 正本アセット（index.html / data / images / favicon / logo / sw.js）を `www/` に組み立てる
- `capacitor.config.json` … appId `com.reliefnote.app` / appName `ReliefNote` / webDir `www`
- `ios/App/App.xcodeproj` … Xcode プロジェクト（Capacitor 8＝Swift Package Manager。**CocoaPods 不要**）

## まだ必要な準備
1. **Xcode（フル版）を App Store からインストール** ← 現在は Command Line Tools のみ。これが無いとビルド/提出不可
2. **Apple Developer Program**（$99/年・Bodilab の口座を流用）
3. **アプリアイコン 1024×1024 PNG**（`ios/App/App/Assets.xcassets/AppIcon.appiconset/` の中身を差し替え）

## 提出までの流れ
```bash
# 1. Web を変更したら www→ios へ同期（毎回）
npm run cap:copy

# 2. Xcode で開く
npm run cap:open      # = npx cap open ios
```
Xcode 側で:
3. **Signing & Capabilities** → Team を選択、Bundle Identifier 確認（`com.reliefnote.app`）
4. **AppIcon** を 1024px 版に差し替え、起動画面（LaunchScreen）を調整
5. 実機 or シミュレータで動作確認（localStorage・オフラインCSV・共有シートが動くこと）
6. **Product → Archive** → Distribute App → App Store Connect へアップロード
7. App Store Connect でメタデータ・スクショ・**App Privacy** ラベル・プライバシーポリシーURL を入力
8. **TestFlight** で自分の端末に入れて確認 → 公開審査に提出

## 審査の要注意点（ガイドライン 4.2）
「ただの Web ラッパー」に見えるとリジェクト。ReliefNote は本物のオフラインツールなので勝てるが、ネイティブ価値を足すと安全:
- ✅ 完全オフライン動作 / ✅ ネイティブ共有シート（navigator.share）
- ➕ **Face ID / 生体認証ロック**（機微情報保護＝製品価値かつ審査対策）
- ⚠️ Web 版サイト（reliefnote.github.io）を開くだけのリンクは入れない

## アプリアイコン・スプラッシュ
- 素案は `assets/icon.svg`（1024）と `assets/splash.svg`（2732）。ブランド＝インク#3A3E31 ×クリーム葉×金の葉脈。
- SVG を編集 → `npm run assets:ios` で iOS の AppIcon / Splash（ライト・ダーク）を一括再生成（`@capacitor/assets`）。
- 生成物は `ios/App/App/Assets.xcassets/` に入る。デザインを差し替えるなら SVG（または `assets/icon.png` 1024 を直接置換）→ 再生成。

## Face ID（生体認証）を有効にする
アプリロックの暗証番号は Web/ネイティブ両方で動く。Face ID を足すにはネイティブプラグインを入れる:
```bash
npm i @aparajita/capacitor-biometric-auth   # または capacitor-native-biometric
npm run cap:copy
```
コード側は `window.Capacitor.Plugins.BiometricAuth` があれば自動で「Face ID で解除」ボタンを出す実装済み（`appLockBiometric()`）。プラグインのメソッド名が異なる場合は `appLockBiometric()` を合わせて調整。iOS は Info.plist に `NSFaceIDUsageDescription` を追加。

## メモ
- ログイン無し ＝ Sign in with Apple 不要
- プライバシー：端末保存中心。App Privacy では「匿名イベントログ・家族共有(Supabase)」を正直に申告
- カテゴリ：ライフスタイル想定
