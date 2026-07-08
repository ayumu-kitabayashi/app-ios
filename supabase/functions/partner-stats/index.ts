// Supabase Edge Function: partner-stats
// パートナー (葬儀社) 向けの匿名統計 API
//
// GET /partner-stats?partner_id=demo&period=2026-04&token=xxx
//
// レスポンス:
// {
//   partner_id, period,
//   kpi: { users, task_completion_rate, ocr_rate, care_rate },
//   monthly_trend: [{ month, users }],
//   feature_ranking: [{ event_type, display_name, count }],
//   task_distribution: [{ range, count }]
// }

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Content-Type": "application/json",
};

// イベントタイプの表示名マップ
const EVENT_DISPLAY_NAMES: Record<string, string> = {
    screen_view: "タスクリスト閲覧",
    ocr_capture_opened: "死亡日 OCR 撮影",
    ocr_run_finished: "OCR 実行",
    ocr_result_confirmed: "OCR 確定",
    grief_log_saved: "こころのケア記録",
    wave_saved: "波の記録",
    ai_chat_sent: "AI 質問",
    breathing_started: "呼吸ガイド",
    task_status_changed: "タスク操作",
    anniv_added: "記念日追加",
    rescue_opened: "レスキュー",
    sos_opened: "SOS",
};

// ノイズとして除外するイベント
const EXCLUDED_EVENTS = new Set([
    "page_view",
    "session_start",
    "session_end",
    "app_init",
]);

// 最低集計人数 (プライバシー保護)
const MIN_USERS_FOR_STATS = 5;

serve(async (req: Request) => {
    // CORS preflight
    if (req.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (req.method !== "GET") {
        return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: CORS_HEADERS }
        );
    }

    const url = new URL(req.url);
    const partnerId = url.searchParams.get("partner_id");
    const period = url.searchParams.get("period"); // YYYY-MM
    const token = url.searchParams.get("token");

    if (!partnerId || !period) {
        return new Response(
            JSON.stringify({ error: "partner_id and period are required" }),
            { status: 400, headers: CORS_HEADERS }
        );
    }

    // トークン認証
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: partner, error: partnerErr } = await supabase
        .from("partners")
        .select("partner_id, name, dashboard_token, token_expires_at")
        .eq("partner_id", partnerId)
        .single();

    if (partnerErr || !partner) {
        return new Response(
            JSON.stringify({ error: "Partner not found" }),
            { status: 404, headers: CORS_HEADERS }
        );
    }

    if (partner.dashboard_token !== token) {
        return new Response(
            JSON.stringify({ error: "Invalid token" }),
            { status: 401, headers: CORS_HEADERS }
        );
    }

    if (new Date(partner.token_expires_at) < new Date()) {
        return new Response(
            JSON.stringify({ error: "Token expired" }),
            { status: 401, headers: CORS_HEADERS }
        );
    }

    // 期間のパース
    const [yearStr, monthStr] = period.split("-");
    const year = parseInt(yearStr, 10);
    const month = parseInt(monthStr, 10);
    if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
        return new Response(
            JSON.stringify({ error: "Invalid period format (expected YYYY-MM)" }),
            { status: 400, headers: CORS_HEADERS }
        );
    }

    const startDate = new Date(year, month - 1, 1).toISOString();
    const endDate = new Date(year, month, 1).toISOString();

    // イベントログ取得
    const { data: logs, error: logsErr } = await supabase
        .from("event_logs")
        .select("user_id, event_type, event_data, created_at")
        .gte("created_at", startDate)
        .lt("created_at", endDate)
        .limit(10000);

    if (logsErr) {
        return new Response(
            JSON.stringify({ error: "Failed to fetch logs" }),
            { status: 500, headers: CORS_HEADERS }
        );
    }

    // partner フィルタ (event_data.partner で絞り込み)
    const filtered = (logs ?? []).filter((l: any) => {
        const ed = l.event_data;
        if (!ed || typeof ed !== "object") return false;
        return ed.partner === partnerId;
    });

    // 集計
    const uniqueUsers = new Set<string>();
    const eventCounts: Record<string, number> = {};
    let ocrAttempts = 0;
    let ocrConfirmed = 0;
    const ocrUsers = new Set<string>();
    const careUsers = new Set<string>();
    let taskCompleted = 0;
    let taskTotal = 0;

    for (const log of filtered) {
        uniqueUsers.add(log.user_id);

        const et = log.event_type;
        if (!EXCLUDED_EVENTS.has(et)) {
            eventCounts[et] = (eventCounts[et] || 0) + 1;
        }

        if (et === "ocr_run_finished") ocrAttempts++;
        if (et === "ocr_result_confirmed") ocrConfirmed++;
        if (et === "ocr_capture_opened") ocrUsers.add(log.user_id);
        if (et === "grief_log_saved" || et === "wave_saved") careUsers.add(log.user_id);
        if (et === "task_status_changed") {
            taskTotal++;
            const ed = log.event_data;
            if (ed && ed.new_status === "DONE") taskCompleted++;
        }
    }

    const userCount = uniqueUsers.size;

    // 最低集計人数チェック
    if (userCount < MIN_USERS_FOR_STATS) {
        return new Response(
            JSON.stringify({
                partner_id: partnerId,
                partner_name: partner.name,
                period,
                insufficient_data: true,
                message: `利用者数が${MIN_USERS_FOR_STATS}人未満のため、統計を表示できません。`,
                user_count: userCount,
            }),
            { status: 200, headers: CORS_HEADERS }
        );
    }

    // KPI
    const taskCompletionRate = taskTotal > 0 ? Math.round((taskCompleted / taskTotal) * 100) : 0;
    const ocrRate = ocrAttempts > 0 ? Math.round((ocrConfirmed / ocrAttempts) * 100) : 0;
    const careRate = userCount > 0 ? Math.round((careUsers.size / userCount) * 100) : 0;

    // 機能ランキング TOP 5
    const featureRanking = Object.entries(eventCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([eventType, count]) => ({
            event_type: eventType,
            display_name: EVENT_DISPLAY_NAMES[eventType] || eventType,
            count,
        }));

    // 前月データ (デルタ計算用)
    const prevStart = new Date(year, month - 2, 1).toISOString();
    const prevEnd = startDate;
    const { data: prevLogs } = await supabase
        .from("event_logs")
        .select("user_id, event_type, event_data")
        .gte("created_at", prevStart)
        .lt("created_at", prevEnd)
        .limit(10000);

    const prevFiltered = (prevLogs ?? []).filter((l: any) => {
        const ed = l.event_data;
        return ed && typeof ed === "object" && ed.partner === partnerId;
    });
    const prevUsers = new Set(prevFiltered.map((l: any) => l.user_id)).size;
    const userDelta = userCount - prevUsers;

    // 月次トレンド (過去 6 ヶ月)
    const monthlyTrend: { month: string; users: number }[] = [];
    for (let i = 5; i >= 0; i--) {
        const tMonth = new Date(year, month - 1 - i, 1);
        const tStart = tMonth.toISOString();
        const tEnd = new Date(tMonth.getFullYear(), tMonth.getMonth() + 1, 1).toISOString();

        const { data: tLogs } = await supabase
            .from("event_logs")
            .select("user_id, event_data")
            .gte("created_at", tStart)
            .lt("created_at", tEnd)
            .limit(10000);

        const tFiltered = (tLogs ?? []).filter((l: any) => {
            const ed = l.event_data;
            return ed && typeof ed === "object" && ed.partner === partnerId;
        });

        monthlyTrend.push({
            month: (tMonth.getMonth() + 1) + "月",
            users: new Set(tFiltered.map((l: any) => l.user_id)).size,
        });
    }

    const response = {
        partner_id: partnerId,
        partner_name: partner.name,
        period,
        kpi: {
            users: userCount,
            user_delta: userDelta,
            task_completion_rate: taskCompletionRate,
            ocr_rate: ocrRate,
            care_rate: careRate,
        },
        monthly_trend: monthlyTrend,
        feature_ranking: featureRanking,
    };

    return new Response(JSON.stringify(response), {
        status: 200,
        headers: CORS_HEADERS,
    });
});
