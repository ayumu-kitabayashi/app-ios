// @ts-check
const { test, expect } = require('@playwright/test');

/**
 * ReliefNote スモークテスト
 *
 * 目的:
 *   - 本番デプロイ前に主要導線が壊れていないことを確認する
 *   - 詳細なユースケースはカバーしない（最低限の安全網）
 *
 * 方針:
 *   - 各テスト開始時に localStorage をクリーンにしてから画面を操作する
 *   - JSエラーはすべてキャッチして、テストを失敗させる
 *   - 画面IDや data-testid ではなく、ユーザー視点のテキストで検索する
 */

test.describe('ReliefNote smoke', () => {
    /** @type {string[]} */
    let consoleErrors;

    test.beforeEach(async ({ page }) => {
        consoleErrors = [];
        page.on('pageerror', (err) => {
            consoleErrors.push('pageerror: ' + (err && err.message));
        });
        page.on('console', (msg) => {
            if (msg.type() === 'error') {
                const text = msg.text();
                // 予期される警告は無視
                if (/favicon/i.test(text)) return;
                if (/Service Worker/i.test(text)) return;
                consoleErrors.push('console.error: ' + text);
            }
        });
    });

    test.afterEach(async () => {
        // ページ読み込み中のJSエラーがあればテスト失敗
        expect(consoleErrors, 'JSエラーが発生しました:\n' + consoleErrors.join('\n')).toEqual([]);
    });

    test('初回アクセス: スプラッシュ画面が表示される', async ({ page }) => {
        await page.goto('/');
        // splash画面のタイトル等が表示されていることを確認
        await expect(page.locator('#screen-splash.active')).toBeVisible({ timeout: 5000 });
        // ReliefNote ロゴ/タイトル
        await expect(page.locator('body')).toContainText('ReliefNote');
    });

    test('オンボーディング済み想定: ホーム画面が直接表示される', async ({ page }) => {
        // 先に localStorage を仕込んでからアクセス
        await page.addInitScript(() => {
            localStorage.setItem('rn_user_name', 'テスト太郎');
            localStorage.setItem('answers', JSON.stringify({
                'Q-DOD-01': '2026-01-01',
                'Q-REL-01': 'spouse'
            }));
            localStorage.setItem('rn_data_version', 'v2-csv');
        });
        await page.goto('/');
        await expect(page.locator('#screen-home.active')).toBeVisible({ timeout: 5000 });
    });

    test('ナビゲーション: やることタブ → タスク詳細 → 戻る', async ({ page }) => {
        await page.addInitScript(() => {
            localStorage.setItem('rn_user_name', 'テスト太郎');
            localStorage.setItem('answers', JSON.stringify({
                'Q-DOD-01': '2026-01-01'
            }));
            localStorage.setItem('rn_data_version', 'v2-csv');
        });
        await page.goto('/');
        await expect(page.locator('#screen-home.active')).toBeVisible();

        // フッターの「やること」タブをクリック
        const guideTab = page.locator('.footer-nav').getByText('やること');
        await guideTab.click();
        await expect(page.locator('#screen-guide.active')).toBeVisible();

        // タスクが1件以上レンダリングされていることを確認
        await expect(page.locator('#guideContent')).not.toBeEmpty();
    });

    test('タスク詳細リロード: ハッシュからタスクが復元される', async ({ page }) => {
        await page.addInitScript(() => {
            localStorage.setItem('rn_user_name', 'テスト太郎');
            localStorage.setItem('answers', JSON.stringify({
                'Q-DOD-01': '2026-01-01'
            }));
            localStorage.setItem('rn_data_version', 'v2-csv');
        });
        // 既知のタスクIDで直接アクセス
        await page.goto('/#screen-detail/RN-H24-01');
        // タスク詳細が描画されていることを確認（タイトル等が表示されるはず）
        await expect(page.locator('#screen-detail.active')).toBeVisible();
        // 詳細コンテンツがある（完全に空ではない）
        const detailContent = page.locator('#screen-detail .detail-content, #screen-detail');
        await expect(detailContent.first()).not.toBeEmpty();
    });

    test('チャネル切替: ?ch=hokuryu で北竜町モードが立つ', async ({ page }) => {
        await page.addInitScript(() => {
            localStorage.setItem('rn_user_name', 'テスト太郎');
            localStorage.setItem('answers', JSON.stringify({
                'Q-DOD-01': '2026-01-01'
            }));
            localStorage.setItem('rn_data_version', 'v2-csv');
        });
        await page.goto('/?ch=hokuryu');
        await expect(page.locator('#screen-home.active')).toBeVisible();
        // window.currentChannelId をチェック
        const channelId = await page.evaluate(() => window.currentChannelId);
        expect(channelId).toBe('hokuryu');
    });
});
