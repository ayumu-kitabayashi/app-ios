// @ts-check
const { defineConfig, devices } = require('@playwright/test');

/**
 * ReliefNote E2E テスト設定
 *
 * 使い方:
 *   1. npm install（初回のみ）
 *   2. npx playwright install chromium（初回のみ）
 *   3. npm test
 *
 * ローカルサーバーは自動起動（http-server）。ポート8080で index.html を配信。
 */
module.exports = defineConfig({
    testDir: './tests',
    timeout: 30_000,
    expect: { timeout: 5_000 },
    fullyParallel: true,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 2 : 0,
    workers: process.env.CI ? 1 : undefined,
    reporter: [['list']],

    use: {
        baseURL: 'http://127.0.0.1:8080',
        trace: 'retain-on-failure',
        screenshot: 'only-on-failure',
        video: 'retain-on-failure',
    },

    projects: [
        {
            name: 'chromium',
            use: { ...devices['Desktop Chrome'] },
        },
        {
            name: 'mobile-safari',
            use: { ...devices['iPhone 13'] },
        },
    ],

    webServer: {
        command: 'npx http-server -p 8080 -c-1 -s .',
        url: 'http://127.0.0.1:8080',
        reuseExistingServer: !process.env.CI,
        timeout: 30_000,
    },
});
