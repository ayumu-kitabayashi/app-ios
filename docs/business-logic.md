# ビジネスロジック仕様

**最終更新**: <!-- AUTO:last-updated -->
2026-07-08
<!-- /AUTO:last-updated --> / **対象読者**: ロジック改修・移植・テスト追加を行うエンジニア

ReliefNote の中核は「**遺族の状況に応じて、必要なタスクだけを出す**」ルールエンジンです。
本書はそのロジック仕様 (DSL文法・タスク状態遷移・依存解決) を定義します。

---

## 1. 全体像

```
[ユーザー回答]               [タスクマスター]
      │                            │
      └────────┬───────────────────┘
               ▼
       [ルールエンジン評価]
               ▼
       [タスク状態を算出]
   OPEN / NEED_CONFIRM / AUTO_DONE
   / NOT_APPLICABLE / BLOCKED / DONE
               ▼
        [画面に表示・並べ替え]
```

ルールは `data/rules_master.csv` に記述され、各タスクに最大 4 種類の条件式 (DSL) が紐づきます。

---

## 2. ルール DSL 文法

### 2.1 基本構文

DSL は単純な式言語で、CSV のセルに 1 行で書く。

```
<expression> ::= <atom>
              | <atom> "AND" <expression>
              | <atom> "OR" <expression>
              | "(" <expression> ")"

<atom>       ::= <question_id> "==" <value>
              | <question_id> "!=" <value>
              | <question_id> "INCLUDES" <value>
              | <question_id> "NOT_INCLUDES" <value>
              | "TRUE" | "FALSE"

<question_id> ::= "Q-" + 識別子        (例: Q-REL-01, Q-DOD-01)
<value>       ::= 識別子 (大文字)        (例: SPOUSE, YES, UNKNOWN)
```

### 2.2 評価例

| DSL 式 | 意味 |
|---|---|
| `Q-REL-01 == SPOUSE` | 故人との関係が配偶者なら true |
| `Q-PEN-01 == YES AND Q-PEN-EMP-01 == YES` | 年金受給中 かつ 会社員経験あり |
| `Q-FIN-01 INCLUDES BANK` | 故人名義の金融資産に「銀行口座」を含むなら true |
| `Q-AGRI-01 != YES` | 農地が「ある」以外なら true |
| `(Q-CHILD-U18-01 == YES) OR (Q-SPOUSE-01 == YES)` | 18歳未満の子 または 配偶者がいる |

### 2.3 三値論理 (重要)

評価結果は `true / false / 'UNKNOWN'` の **三値**:
- 質問にまだ回答していない → `UNKNOWN`
- 質問の回答が `'UNKNOWN'` (= 「わからない」を選択) → `UNKNOWN`
- それ以外は `true` / `false`

論理演算子の三値テーブル:

| A | B | A AND B | A OR B |
|---|---|---|---|
| true | true | true | true |
| true | false | false | true |
| true | UNKNOWN | UNKNOWN | true |
| false | false | false | false |
| false | UNKNOWN | false | UNKNOWN |
| UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |

「短絡評価」が効くパターン (例: `false AND ?` → `false`、`true OR ?` → `true`) は通常の二値論理と同じ。

### 2.4 `INCLUDES` / `NOT_INCLUDES` (multi_select 用)

質問 `answer_type` が `multi_select` の場合、回答は配列として保存される。
`INCLUDES X` は配列に X が含まれるかを判定。

```
Q-FIN-01 == ["BANK", "CARD"]   ← 回答
Q-FIN-01 INCLUDES BANK          → true
Q-FIN-01 INCLUDES SECURITIES    → false
Q-FIN-01 NOT_INCLUDES BANK      → false
```

---

## 3. ルール 4 種

各タスクは以下 4 つの DSL を持てる (CSV `rules_master.csv` の列):

| 列 | 意味 | 評価タイミング |
|---|---|---|
| `applies_when` | このタスクが「該当する」条件 | 常に評価 (デフォルト TRUE) |
| `not_applicable_when` | このタスクが「明確に該当しない」条件 | 最優先で評価 |
| `auto_done_when` | このタスクが「すでに自動的に完了とみなせる」条件 | applies_when より先に評価 |
| `fallback_status` | applies_when が `UNKNOWN` のときに割り当てる状態 | デフォルト `NEED_CONFIRM` |

`required_questions` 列もあるが、これは「**この条件評価に必要な質問 ID 一覧**」のメタデータ (UI 側で「この質問に答えると XX タスクが確定する」を表示するために使用)。

---

## 4. タスク状態遷移

### 4.1 状態の種類

| 状態 | 意味 | UI 表示 |
|---|---|---|
| `OPEN` | 該当確定。未着手 | 通常表示 (チェックボックス○) |
| `DONE` | ユーザーが「完了にする」で完了 | 完了済み ✓ |
| `AUTO_DONE` | 回答に基づき自動的に完了扱い | 「質問の回答に基づき完了」 |
| `NOT_APPLICABLE` | 該当しないことが確定 | 非表示 (設定で表示可) |
| `NEED_CONFIRM` | applies_when が UNKNOWN のため確認が必要 | 「確認が必要な手続き」セクション |
| `BLOCKED` | applies_when は true だが depends_on が未完了 | グレーアウト + 「先に完了するタスクがあります」 |

### 4.2 状態判定アルゴリズム (`determineTaskStatus(task)`)

```
1. taskStatuses[id] が DONE → DONE を維持して終了
2. not_applicable_when を評価
   - true → NOT_APPLICABLE で終了
   - UNKNOWN/false → 次へ
3. auto_done_when を評価
   - true → AUTO_DONE で終了
   - UNKNOWN/false → 次へ
4. applies_when を評価
   - true → 次の depends_on チェックへ
     - depends_on が全て解決済み → OPEN
     - 未解決の依存あり → BLOCKED
   - UNKNOWN → fallback_status (デフォルト NEED_CONFIRM) を返す
     ※ NEED_CONFIRM でも BLOCKED 判定は行う
   - false → NOT_APPLICABLE
```

実装は `index.html` の `determineTaskStatus()` 関数。

### 4.3 依存解決 (`depends_on`)

`tasks_master.csv` の `depends_on` 列に `;` 区切りで先行タスク ID を列挙。
`depends_logic` 列で AND / OR / SINGLE を指定。

| depends_logic | 意味 |
|---|---|
| `SINGLE` | 1 件だけ。それが解決済みでないと BLOCKED |
| `AND` | 全件が解決済みでないと BLOCKED |
| `OR` | いずれか 1 件が解決済みなら OK |
| `NONE` | 依存なし |

「解決済み」の定義: `DONE`, `AUTO_DONE`, `NOT_APPLICABLE` のいずれか。

### 4.4 状態遷移図

```
       (起動 / 回答変更)
              │
              ▼
    ┌──────────────────┐
    │ determineTaskStatus │
    └──────────────────┘
              │
              ▼
    ┌─ NOT_APPLICABLE (not_applicable_when=true)
    │
    ├─ AUTO_DONE       (auto_done_when=true)
    │
    ├─ NEED_CONFIRM    (applies_when=UNKNOWN)
    │      │
    │      └─ ユーザーが回答 → 再評価
    │
    ├─ OPEN            (applies_when=true, deps OK)
    │      │
    │      └─ ユーザーが「完了にする」→ DONE
    │
    └─ BLOCKED         (applies_when=true, deps NG)
           │
           └─ 依存タスクが解決 → OPEN
```

`DONE` は手動 unset 以外で他状態に戻らない (= 一度完了したら回答変更でも再オープンしない)。

---

## 5. オーバーライドの優先順位

タスク内容は 3 層で決まる:

```
[task_content_master.csv] (デフォルト)
        ↓ 上書き
[locale_override_master.csv] (?ch=hokuryu のみ適用)
        ↓ 上書き
[channel_override_master.csv] (チャネル別、ALWAYS or 条件付き)
```

評価は読み込み時に行い、`taskDetails[id]` に最終形を格納。
- 北竜町ユーザー: locale_override が適用される
- 葬儀社チャネル (`?ch=funeral`): funeral 用の channel_override が適用
- 直接アクセス (`?ch=direct` or 無指定): いずれも適用しない (デフォルト)

---

## 6. オンボーディング・質問フロー

### 6.1 質問の出し分け

質問は `questions_master.csv` の `onboarding_step` 列で 4 段階に分けられる:
1. **ステップ1** (基本情報): 関係/死亡日/葬儀状況
2. **ステップ2** (D7): 仕事/世帯/健康保険/年金
3. **ステップ3** (D14): 介護/金融/保険/契約
4. **ステップ4** (M3-M10): 不動産/車/税金/相続

各タスクは `onboarding_step` 列を持ち、その時点までに必要な質問だけが事前回答される。
未回答の質問が残っていても OK で、その場合タスクは `NEED_CONFIRM` になる。

### 6.2 まとめて確認 (`bulk confirm`)

`NEED_CONFIRM` のタスク群を、共通の質問だけで一気に確定させる UI。
内部的には `extractQuestionIdsFromCondition()` で各タスクの DSL から関連質問 ID を抽出し、ユニーク化したリストを順に提示。

---

## 7. ピン留め (`pinned tasks`)

ユーザーが特定のタスクを「重要」マークできる機能。
- 保存先: `localStorage.rn_pinned_tasks` (JSON 配列)
- 初期ピン留め: `_seedDefaultPinnedTasks()` で法的期限の短いタスク (RN-D7-06 等) を自動ピン
- ホーム画面の「次にやること」より優先表示はしない設計 (= ホームは時系列・ピンはガイド画面で見える)

---

## 8. 法定期限と残日数計算

`tasks_master.csv` の `legal_due_days_from_dod` 列が設定されているタスクは、
死亡日 (`Q-DOD-01`) からの経過日数で「あと N 日」を表示。

```js
remaining = legal_due_days_from_dod - (今日 - 死亡日 in days)
```

- `remaining < 0` → 期限超過 (赤バッジ)
- `0 <= remaining <= 3` → 緊急 (赤バッジ)
- `4 <= remaining <= 7` → 警告 (琥珀バッジ)
- それ以外 → バッジなし

死亡日が未入力 (`Q-DOD-01 == UNKNOWN`) の場合は「死亡日から N 日以内」表示にフォールバック。

---

## 9. 移植時の注意

### 9.1 三値論理を必ず保持
他言語に移植する際、`true / false / null` の 3 値を明示的に扱える型 (Optional<bool> 等) を使うこと。
2 値に潰すと NEED_CONFIRM が機能しなくなり、安全性が下がる。

### 9.2 評価順序を守る
`not_applicable_when → auto_done_when → applies_when → depends_on` の順序は変更しない。
入れ替えると「該当しない」タスクが BLOCKED 表示される等のバグになる。

### 9.3 DONE 状態は再評価しない
すでに DONE のタスクを再計算で上書きすると、ユーザーが完了したものが消える事故が起きる。
`determineTaskStatus()` の最初で DONE 維持を必ず実装すること。

### 9.4 オーバーライド適用は読み込み時 1 回
毎回の状態評価ではなく、初期化時に `taskDetails[id]` を最終形にすること。
評価のたびに上書き計算を走らせると O(N×M) で重くなる。

---

## 10. テスト戦略 (推奨)

PHP/Node/Python いずれに移植する際も、最低限以下のテストを書くこと:

```
tests/rule-engine/
├── tokenize.test       (DSL トークナイザ)
├── eval-binary.test    (二値ケース 30+ パターン)
├── eval-three-valued.test (三値ケース 20+ パターン)
├── eval-includes.test  (multi_select 配列)
├── status-machine.test (4 ルール × 状態遷移)
├── deps-resolution.test (depends_on の AND/OR/SINGLE)
└── override-merge.test  (3 層マージ)
```

ゴールデンマスター方式 (実環境での回答 → 期待状態を JSON 化) も併用すると安心。

---

## 11. 関連実装

| ロジック | 場所 (`index.html` の関数名) |
|---|---|
| DSL 評価 | `evaluateDSL()`, `tokenizeDSL()`, `parseDSLExpr()` |
| 三値演算 | `evaluateCondition()` |
| 状態判定 | `determineTaskStatus()` |
| 依存解決 | `hasDependencyBlocking()`, `isTaskResolved()` |
| 質問ID抽出 | `extractQuestionIdsFromCondition()` |
| オーバーライド適用 | `buildMasterData()` 内のループ |
| 法定期限計算 | `getTaskRemainingDays()`, `getLegalDueStatus()` |
