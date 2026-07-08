# OCR 拡張フレームワーク設計書

**ステータス**: 設計ドラフト (未実装)
**前提**: Step 1 (死亡日 OCR MVP) 完了済み
**方針**: 死亡診断書の MVP 基盤を再利用し、他の書類にも対応を広げる

---

## 1. 対象書類と抽出フィールド

### Phase 1 (MVP 完了済み)

| 書類 | 抽出フィールド | 精度目標 | 状態 |
|---|---|---|---|
| 死亡診断書 (死体検案書) | 死亡日 (`Q-DOD-01`) | 80%+ | 実装済み |

### Phase 2 (次期)

| 書類 | 抽出フィールド | 関連 Q-ID | 優先度 |
|---|---|---|---|
| 健康保険証 | 被保険者氏名, 保険者番号, 記号・番号 | - | 高 |
| 年金手帳 (基礎年金番号通知書) | 基礎年金番号 | - | 高 |
| 運転免許証 | 氏名, 生年月日, 有効期限, 免許番号 | `Q-DL-01` | 中 |

### Phase 3 (将来)

| 書類 | 抽出フィールド | 関連 Q-ID | 優先度 |
|---|---|---|---|
| 通帳 (表紙) | 銀行名, 支店名, 口座番号, 名義 | - | 中 |
| 役所からの通知書 | 差出人, 期限, 手続き名 | - | 低 |
| 保険証券 | 保険会社名, 証券番号, 契約者名 | - | 低 |
| 戸籍謄本 | (OCR 困難、参考のみ) | - | 低 |

---

## 2. プラグインアーキテクチャ

### DocumentExtractor インターフェース

```javascript
// 各書類タイプごとに 1 つの Extractor を定義
var DocumentExtractor = {
    // 書類タイプの識別子
    type: 'death-certificate',

    // 表示名
    label: '死亡診断書',

    // OCR 画面のガイダンステキスト
    guidance: {
        title: '死亡診断書を撮って日付を自動入力',
        description: '書類を撮影するだけで、死亡日を読み取って入力欄に反映します。',
        privacyNote: 'この画像はあなたのスマホから外に出ません。'
    },

    // OCR 言語 (Tesseract の lang パラメータ)
    ocrLang: 'jpn',

    // OCR 結果テキストからフィールドを抽出する関数
    // @param {string} text - OCR で読み取ったテキスト
    // @returns {ExtractedField[]} - 抽出されたフィールドの配列
    extract: function(text) {
        return extractDatesFromOcrText(text).map(function(iso) {
            return {
                fieldId: 'Q-DOD-01',
                fieldLabel: '死亡日',
                value: iso,
                confidence: 'medium'
            };
        });
    },

    // 確定時にどの answers キーに書き込むか
    targetFields: ['Q-DOD-01'],

    // 画像の前処理 (Canvas 操作)
    // @param {HTMLCanvasElement} canvas
    // @returns {HTMLCanvasElement}
    preprocess: null  // null = 前処理なし (デフォルト)
};
```

### ExtractedField 型

```javascript
// extract() の戻り値
var ExtractedField = {
    fieldId: 'Q-DOD-01',        // answers のキー or カスタムキー
    fieldLabel: '死亡日',        // UI 表示用ラベル
    value: '2024-03-15',         // 抽出された値
    confidence: 'high',          // 'high' | 'medium' | 'low'
    displayValue: '2024年3月15日' // 表示用フォーマット (optional)
};
```

### レジストリ

```javascript
var OCR_DOCUMENT_REGISTRY = {
    'death-certificate': {
        type: 'death-certificate',
        label: '死亡診断書',
        guidance: { ... },
        ocrLang: 'jpn',
        extract: function(text) { ... },
        targetFields: ['Q-DOD-01'],
        preprocess: null
    },
    'health-insurance-card': {
        type: 'health-insurance-card',
        label: '健康保険証',
        guidance: {
            title: '健康保険証を撮って自動入力',
            description: '保険証の情報を読み取ります。',
            privacyNote: 'この画像はあなたのスマホから外に出ません。'
        },
        ocrLang: 'jpn',
        extract: function(text) {
            var fields = [];
            // 保険者番号: 8 桁の数字
            var insurer = text.match(/保険者番号\s*[：:]*\s*(\d{6,8})/);
            if (insurer) {
                fields.push({
                    fieldId: 'insurer_number',
                    fieldLabel: '保険者番号',
                    value: insurer[1],
                    confidence: 'medium'
                });
            }
            // 記号・番号
            var symbol = text.match(/記号\s*[：:]*\s*(\S+)/);
            var number = text.match(/番号\s*[：:]*\s*(\S+)/);
            if (symbol) {
                fields.push({
                    fieldId: 'insurance_symbol',
                    fieldLabel: '記号',
                    value: symbol[1],
                    confidence: 'medium'
                });
            }
            if (number) {
                fields.push({
                    fieldId: 'insurance_number',
                    fieldLabel: '番号',
                    value: number[1],
                    confidence: 'medium'
                });
            }
            return fields;
        },
        targetFields: ['insurer_number', 'insurance_symbol', 'insurance_number'],
        preprocess: null
    },
    'pension-book': {
        type: 'pension-book',
        label: '年金手帳',
        guidance: {
            title: '年金手帳を撮って番号を読み取り',
            description: '基礎年金番号を自動で読み取ります。',
            privacyNote: 'この画像はあなたのスマホから外に出ません。'
        },
        ocrLang: 'jpn',
        extract: function(text) {
            var fields = [];
            // 基礎年金番号: 4 桁 - 6 桁 のパターン
            var pension = text.match(/(\d{4})\s*[-ー]\s*(\d{6})/);
            if (pension) {
                fields.push({
                    fieldId: 'pension_number',
                    fieldLabel: '基礎年金番号',
                    value: pension[1] + '-' + pension[2],
                    confidence: 'medium'
                });
            }
            return fields;
        },
        targetFields: ['pension_number'],
        preprocess: null
    }
};
```

---

## 3. 汎用 OCR 画面の拡張

### 現在の `openOcrCapture()` を拡張

```javascript
// Before (MVP)
openOcrCapture({ returnScreen, onConfirm })

// After (拡張版)
openOcrCapture({
    documentType: 'death-certificate',  // レジストリのキー
    returnScreen: 'screen-calendar',
    onConfirm: function(extractedFields) {
        // extractedFields = [{ fieldId, fieldLabel, value, confidence }]
    }
})
```

### UI の動的変更

`documentType` に応じて以下が変わる:
- ガイダンステキスト (title, description)
- 結果確認画面のフィールド (1 個 vs 複数)
- 確定時の保存先

### 結果確認画面 (複数フィールド対応)

```html
<!-- 死亡診断書: 1フィールド (現状) -->
<p class="ocr-result-field-label">死亡日</p>
<input type="date" value="2024-03-15">

<!-- 健康保険証: 3フィールド -->
<p class="ocr-result-field-label">保険者番号</p>
<input type="text" value="12345678">
<p class="ocr-result-field-label">記号</p>
<input type="text" value="100">
<p class="ocr-result-field-label">番号</p>
<input type="text" value="999">
```

---

## 4. 画像前処理パイプライン

### Canvas ベースの前処理

OCR 精度を上げるために、Tesseract に渡す前に画像を処理する。

```javascript
function preprocessImage(canvas, extractorConfig) {
    // 1. リサイズ (長辺 2000px 以下に)
    var maxDim = 2000;
    if (canvas.width > maxDim || canvas.height > maxDim) {
        var scale = maxDim / Math.max(canvas.width, canvas.height);
        var newCanvas = document.createElement('canvas');
        newCanvas.width = Math.round(canvas.width * scale);
        newCanvas.height = Math.round(canvas.height * scale);
        var ctx = newCanvas.getContext('2d');
        ctx.drawImage(canvas, 0, 0, newCanvas.width, newCanvas.height);
        canvas = newCanvas;
    }

    // 2. グレースケール化
    var ctx = canvas.getContext('2d');
    var imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    var data = imgData.data;
    for (var i = 0; i < data.length; i += 4) {
        var gray = data[i] * 0.299 + data[i+1] * 0.587 + data[i+2] * 0.114;
        data[i] = data[i+1] = data[i+2] = gray;
    }
    ctx.putImageData(imgData, 0, 0);

    // 3. コントラスト強調 (オプション)
    // 文字がかすれている場合に有効

    // 4. Extractor 固有の前処理
    if (extractorConfig && typeof extractorConfig.preprocess === 'function') {
        canvas = extractorConfig.preprocess(canvas);
    }

    return canvas;
}
```

### 手書き文字への対応

死亡診断書の日付は手書きの場合がある。Tesseract の jpn モデルは活字向けのため:

1. **MVP**: 手書きが読めなくても手入力にフォールバック (現在の実装)
2. **Phase 2**: 日付欄の領域をユーザーに指定させる (タップで矩形選択)
3. **Phase 3**: 手書き認識に特化したモデル (例: Google Cloud Vision API) をオプションで使う
   - ただしサーバーに画像を送ることになるため、ユーザーの明示的同意が必要
   - 「画像を送信して精度を上げますか？」のオプトイン UI

---

## 5. 精度計測の仕組み

### イベントログで自動計測

```javascript
logEvent('ocr_run_finished', {
    document_type: 'death-certificate',
    candidate_count: 3,
    has_match: true,
    text_len: 450
});

logEvent('ocr_result_confirmed', {
    document_type: 'death-certificate',
    used_candidate: true,  // 自動抽出結果をそのまま使ったか
    manual_edit: false,     // 手で修正したか
    candidate_count: 3
});

logEvent('ocr_skipped_to_manual', {
    document_type: 'death-certificate'
});
```

### 精度 KPI

| 指標 | 計算方法 | 目標 |
|---|---|---|
| OCR 成功率 | `ocr_run_finished` で `has_match: true` の割合 | 80%+ |
| 自動抽出採用率 | `ocr_result_confirmed` で `used_candidate: true` の割合 | 70%+ |
| 手入力フォールバック率 | `ocr_skipped_to_manual` / 全 OCR 試行 | 20%未満 |
| 手修正率 | `manual_edit: true` の割合 | 30%未満 |

---

## 6. リファクタリング計画

### 現在のコード構造 (MVP)

```
extractDatesFromOcrText()  → 死亡日に特化
openOcrCapture()           → 死亡日に特化
_renderOcrResult()         → date 型 input 1 つ
confirmOcrResult()         → Q-DOD-01 に直接保存
```

### 拡張後のコード構造

```
OCR_DOCUMENT_REGISTRY      → 書類タイプ辞書
openOcrCapture({ documentType, ... })
  → _currentExtractor = OCR_DOCUMENT_REGISTRY[documentType]
  → guidance テキストを動的設定
  → OCR 完了後: _currentExtractor.extract(text)
  → 結果: _renderOcrMultiFieldResult(extractedFields)
confirmOcrResult()
  → onConfirm(extractedFields) を呼ぶ

// 旧 extractDatesFromOcrText() はそのまま残す (death-certificate の extract 内で使用)
```

### 移行の互換性

- `openOcrCapture({ returnScreen, onConfirm })` の既存呼び出しは `documentType` 省略時に `'death-certificate'` をデフォルトとする
- `onConfirm(isoDate)` の既存コールバックシグネチャも互換維持 (death-certificate の場合のみ string を渡す)

---

## 7. プライバシー原則 (全書類共通)

1. **画像はブラウザの外に出ない**: すべての書類で Tesseract.js によるブラウザ内 OCR
2. **OCR 生テキストは保存しない**: 抽出された構造化フィールドのみ保存
3. **確定後に画像データを破棄**: `_ocrState.imageDataUrl = null; _ocrState.imageBlob = null;`
4. **サーバーに送る場合は明示的同意**: Phase 3 で外部 API を使う場合のみ、オプトインで
5. **抽出されたフィールドの用途を明示**: 「この番号は◯◯の手続きに使います」

---

## 8. 今後の検討事項

| 課題 | 対応案 | 優先度 |
|---|---|---|
| 書類の自動分類 | 撮影された画像がどの書類か自動判定 (キーワードベース or 画像分類 ML) | 低 (当面はユーザーが書類種別を選択) |
| 複数ページ対応 | 死亡診断書の裏面、保険証券の複数ページ等 | 中 |
| バーコード/QR 読取 | マイナンバーカード、通知カード等のバーコード | 中 (jsQR ライブラリ) |
| 多言語対応 | 英語の書類 (在留外国人) | 低 |
| A/B テスト | 前処理あり/なしで OCR 精度を比較 | 中 |
