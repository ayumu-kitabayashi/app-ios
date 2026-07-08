-- =========================================================
-- ReliefNote: 北竜町実証実験 KPI 集計ビュー
-- =========================================================
-- 背景:
--  - event_logs を毎回生クエリで叩くと負荷も読みづらさも増す
--  - 北竜町向けに「DAU・タスク完了率・画面ファネル・グリーフ継続率」を
--    view 化しておけば、Dashboard から SELECT するだけで済む
--  - 個別 user_id を直接見せたくないので、集計済みビューを基本入口にする
--
-- 前提:
--  - 006 までで feedback テーブルが存在
--  - index.html の logEvent に screen_viewed / session_start / session_end が
--    入っていること (PILOT-1)
--  - user_id は端末固有 UUID (PILOT-2)

-- ============================================================
-- 1. 北竜町チャネルのみのベースビュー
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_events AS
SELECT
    id,
    user_id,
    event_type,
    event_data,
    (event_data->>'channel') AS channel,
    (event_data->>'session_id') AS session_id,
    (event_data->>'screen_id') AS screen_id,
    (event_data->>'from_screen') AS from_screen,
    (event_data->>'task_id') AS task_id,
    created_at,
    (created_at AT TIME ZONE 'Asia/Tokyo')::date AS jst_date
FROM public.event_logs
WHERE event_data->>'channel' = 'hokuryu';

COMMENT ON VIEW public.v_hokuryu_events IS '北竜町チャネルのイベントだけを抽出。JST 日付列付き';

-- ============================================================
-- 2. 日次 DAU / セッション数
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_daily AS
SELECT
    jst_date,
    COUNT(DISTINCT user_id)                          AS dau,
    COUNT(*) FILTER (WHERE event_type='session_start') AS sessions,
    COUNT(*) FILTER (WHERE event_type='task_completed') AS tasks_done,
    COUNT(*) FILTER (WHERE event_type='grief_log_saved') AS grief_logs,
    COUNT(*) FILTER (WHERE event_type='grief_alert_triggered') AS grief_alerts
FROM public.v_hokuryu_events
GROUP BY jst_date
ORDER BY jst_date DESC;

COMMENT ON VIEW public.v_hokuryu_daily IS '日次 DAU/セッション数/タスク完了数/グリーフ記録/アラート発火';

-- ============================================================
-- 3. 画面ファネル (どの画面から離脱するか)
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_screen_funnel AS
SELECT
    screen_id,
    from_screen,
    COUNT(*)                  AS visits,
    COUNT(DISTINCT user_id)   AS unique_users,
    COUNT(DISTINCT session_id) AS sessions
FROM public.v_hokuryu_events
WHERE event_type='screen_viewed' AND screen_id IS NOT NULL
GROUP BY screen_id, from_screen
ORDER BY visits DESC;

COMMENT ON VIEW public.v_hokuryu_screen_funnel IS '画面遷移ペア (from→to) ごとの訪問数。詰まりポイント特定用';

-- ============================================================
-- 4. タスク完了ランキング (どのタスクが終わるか / 終わらないか)
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_task_completion AS
SELECT
    task_id,
    COUNT(*) FILTER (WHERE event_type='task_started')   AS started,
    COUNT(*) FILTER (WHERE event_type='task_completed') AS completed,
    COUNT(DISTINCT user_id) FILTER (WHERE event_type='task_completed') AS unique_completers
FROM public.v_hokuryu_events
WHERE task_id IS NOT NULL
GROUP BY task_id
ORDER BY completed DESC;

COMMENT ON VIEW public.v_hokuryu_task_completion IS 'タスク別 着手/完了回数。紙の案内紙との突合に使う';

-- ============================================================
-- 5. セッション継続秒数の分布
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_session_duration AS
SELECT
    jst_date,
    COUNT(*)                                              AS sessions,
    AVG((event_data->>'duration_sec')::int)::int          AS avg_sec,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY (event_data->>'duration_sec')::int) AS p50_sec,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY (event_data->>'duration_sec')::int) AS p90_sec
FROM public.v_hokuryu_events
WHERE event_type='session_end'
  AND event_data ? 'duration_sec'
  AND (event_data->>'duration_sec') ~ '^[0-9]+$'  -- 非数値 (null/文字列) を除外して ::int 例外を防ぐ
GROUP BY jst_date
ORDER BY jst_date DESC;

COMMENT ON VIEW public.v_hokuryu_session_duration IS '日次セッション滞在秒数の平均/P50/P90';

-- ============================================================
-- 6. ユーザー単位の継続日数 (リテンション)
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_user_retention AS
WITH per_user AS (
    SELECT
        user_id,
        MIN(jst_date) AS first_day,
        MAX(jst_date) AS last_day,
        COUNT(DISTINCT jst_date) AS active_days
    FROM public.v_hokuryu_events
    GROUP BY user_id
)
SELECT
    user_id,
    first_day,
    last_day,
    active_days,
    (last_day - first_day) AS span_days
FROM per_user
ORDER BY active_days DESC;

COMMENT ON VIEW public.v_hokuryu_user_retention IS 'ユーザーごとの初回日/最終日/アクティブ日数。継続率計算の元ネタ';

-- ============================================================
-- 7. レビュー (feedback テーブル) の北竜町集計
-- ============================================================
CREATE OR REPLACE VIEW public.v_hokuryu_feedback AS
SELECT
    (created_at AT TIME ZONE 'Asia/Tokyo')::date AS jst_date,
    rating,
    COUNT(*)                                     AS n,
    AVG(milestone_pct)::int                      AS avg_pct,
    AVG(days_since_death)::int                   AS avg_dsd
FROM public.feedback
WHERE channel_id = 'hokuryu'
GROUP BY jst_date, rating
ORDER BY jst_date DESC, rating;

COMMENT ON VIEW public.v_hokuryu_feedback IS '北竜町チャネルの日次レビュー集計';

-- =========================================================
-- 利用例 (週次レポート)
-- =========================================================
-- 直近7日のサマリ:
--   SELECT * FROM public.v_hokuryu_daily
--    WHERE jst_date > current_date - 7 ORDER BY jst_date;
--
-- ファネル詰まり Top10:
--   SELECT * FROM public.v_hokuryu_screen_funnel LIMIT 10;
--
-- タスク完了率:
--   SELECT task_id,
--          completed::float / NULLIF(started, 0) AS completion_rate
--     FROM public.v_hokuryu_task_completion
--    WHERE started > 0 ORDER BY completion_rate;
--
-- リテンション分布:
--   SELECT active_days, COUNT(*)
--     FROM public.v_hokuryu_user_retention
--    GROUP BY active_days ORDER BY active_days;
