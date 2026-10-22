import json
import httpx
from datetime import datetime
from typing import Any, Dict, List, Optional

from backend.config import settings
from backend.services.obsidian_service import obsidian_service


WEATHER_CODE_MAP = {
    0: ("快晴", "☀️"),
    1: ("晴れ", "🌤️"),
    2: ("一部曇り", "⛅"),
    3: ("曇り", "☁️"),
    45: ("霧", "🌫️"),
    48: ("霧氷", "🌫️"),
    51: ("小雨(霧雨)", "🌦️"),
    53: ("霧雨", "🌦️"),
    55: ("強い霧雨", "🌧️"),
    61: ("小雨", "🌦️"),
    63: ("雨", "🌧️"),
    65: ("強い雨", "🌧️"),
    71: ("小雪", "🌨️"),
    73: ("雪", "❄️"),
    75: ("大雪", "❄️"),
    80: ("にわか雨", "🌦️"),
    81: ("強いにわか雨", "🌧️"),
    82: ("激しいにわか雨", "⛈️"),
    95: ("雷雨", "⛈️"),
}


class ConciergeService:
    """
    天気・カレンダー・AI提案サービス
    - Open-Meteo API による三軒茶屋・東京の天気取得（オフライン時はスマートフォールバック）
    - GoogleカレンダーiCal連携 ＋ やるメモ.md の確定予定タイムライン
    - 空き時間・天気・予算・やりたいリスト・趣味ガチャを掛け合わせたAI行動提案（Must / Want / 30分試食）
    """

    def __init__(self) -> None:
        self._weather_cache: Optional[Dict[str, Any]] = None
        self._weather_cached_at: Optional[datetime] = None

    async def get_weather(self, force_refresh: bool = False) -> Dict[str, Any]:
        if (
            not force_refresh
            and self._weather_cache
            and self._weather_cached_at
            and (datetime.now() - self._weather_cached_at).total_seconds() < 1800
        ):
            return self._weather_cache

        url = (
            f"https://api.open-meteo.com/v1/forecast"
            f"?latitude={settings.weather_lat}&longitude={settings.weather_lon}"
            f"&current=temperature_2m,weather_code"
            f"&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            f"&timezone=Asia%2FTokyo"
        )
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(url)
                resp.raise_for_status()
                data = resp.json()

            current = data.get("current", {})
            daily = data.get("daily", {})

            w_code = int(current.get("weather_code", 1))
            label, icon = WEATHER_CODE_MAP.get(w_code, ("晴れ時々曇り", "⛅"))

            max_temps = daily.get("temperature_2m_max", [21.0])
            min_temps = daily.get("temperature_2m_min", [13.0])
            precip_probs = daily.get("precipitation_probability_max", [10])
            daily_codes = daily.get("weather_code", [w_code])
            dates = daily.get("time", [])

            forecast_days = []
            for i in range(min(len(dates), 5)):
                dc = int(daily_codes[i]) if i < len(daily_codes) else 1
                dl, di = WEATHER_CODE_MAP.get(dc, ("晴れ", "🌤️"))
                forecast_days.append({
                    "date": dates[i],
                    "label": dl,
                    "icon": di,
                    "temp_max": max_temps[i] if i < len(max_temps) else 20.0,
                    "temp_min": min_temps[i] if i < len(min_temps) else 12.0,
                    "precip_prob": precip_probs[i] if i < len(precip_probs) else 10,
                })

            precip_today = precip_probs[0] if precip_probs else 10
            advice = (
                "傘があると安心です。屋内作業や家でピアノ・開発・執筆がおすすめ！"
                if precip_today >= 40
                else "お出かけ・LUUP散歩・ドライブ日和です！朝晩の寒暖差に注意。"
            )

            result = {
                "location": settings.weather_location_name,
                "latitude": settings.weather_lat,
                "longitude": settings.weather_lon,
                "temperature": current.get("temperature_2m", 19.5),
                "weather_code": w_code,
                "condition": label,
                "icon": icon,
                "temp_max": max_temps[0] if max_temps else 21.0,
                "temp_min": min_temps[0] if min_temps else 13.0,
                "precip_prob": precip_today,
                "advice": advice,
                "forecast": forecast_days,
                "source": "Open-Meteo Live API",
                "fetched_at": datetime.now().isoformat(),
            }
            self._weather_cache = result
            self._weather_cached_at = datetime.now()
            return result
        except Exception:
            fallback = {
                "location": settings.weather_location_name,
                "latitude": settings.weather_lat,
                "longitude": settings.weather_lon,
                "temperature": 19.2,
                "weather_code": 1,
                "condition": "晴れ（秋晴れ）",
                "icon": "🌤️",
                "temp_max": 21.5,
                "temp_min": 13.0,
                "precip_prob": 10,
                "advice": "三軒茶屋周辺は穏やかな秋晴れ。LUUP散歩や帰りの買い物にも快適な気候です。",
                "forecast": [
                    {"date": "今日", "label": "晴れ", "icon": "🌤️", "temp_max": 21.5, "temp_min": 13.0, "precip_prob": 10},
                    {"date": "明日", "label": "晴れ時々曇り", "icon": "⛅", "temp_max": 20.0, "temp_min": 12.5, "precip_prob": 20},
                    {"date": "明後日", "label": "快晴", "icon": "☀️", "temp_max": 22.0, "temp_min": 13.5, "precip_prob": 0},
                ],
                "source": "Fallback Cache (Offline Safe)",
                "fetched_at": datetime.now().isoformat(),
            }
            return fallback

    async def get_schedule_timeline(self) -> Dict[str, Any]:
        """
        GoogleカレンダーiCal (設定時) ＋ やるメモ.md 内の確定スケジュール・マイルストーンを
        時系列タイムラインとして返す。
        """
        fixed_milestones: List[Dict[str, Any]] = [
            {
                "date": "2026-10-22",
                "time": "今日",
                "title": "Daily Concierge 開発 ＆ 10/29〜11/8 休暇プラン整理",
                "category": "今日",
                "location": "学校PC / 自宅PC",
                "cost_note": "¥0",
                "is_milestone": True,
            },
            {
                "date": "2026-10-26",
                "time": "終日目標",
                "title": "『10月26日までに完成させる』統合執筆 完成目標日",
                "category": "創作・目標",
                "location": "Obsidian Vault",
                "cost_note": "¥0",
                "is_milestone": True,
            },
            {
                "date": "2026-10-27",
                "time": "記念日",
                "title": "🎂 20歳の誕生日！（お酒解禁・三茶で嗜む＆ニチジョ的お祝い）",
                "category": "記念日",
                "location": "三軒茶屋 / 実家",
                "cost_note": "家のお酒＋少し購入",
                "is_milestone": True,
            },
            {
                "date": "2026-10-29",
                "time": "夜",
                "title": "11連休初日 ＆ 夜バイト",
                "category": "確定予定・バイト",
                "location": "バイト先",
                "cost_note": "+収入（来月4〜5万へ）",
                "is_milestone": False,
            },
            {
                "date": "2026-10-31",
                "time": "午前〜昼候補",
                "title": "大久保 学園祭出席 (10/31 または 11/1) ＆ 休日朝ドライブ候補①",
                "category": "確定予定",
                "location": "大久保 / 三軒茶屋起点",
                "cost_note": "交通費のみ",
                "is_milestone": False,
            },
            {
                "date": "2026-11-01",
                "time": "午前〜午後候補",
                "title": "学園祭予備日 / 日曜・父の卓球に混ざる相談 / 朝ドライブ候補②",
                "category": "休日計画",
                "location": "大久保 / 地元",
                "cost_note": "¥0〜少額",
                "is_milestone": False,
            },
            {
                "date": "2026-11-03",
                "time": "朝・夜",
                "title": "朝ドライブ候補③ ＆ 夜：映画鑑賞（確定予定）",
                "category": "確定予定",
                "location": "映画館",
                "cost_note": "映画代",
                "is_milestone": True,
            },
            {
                "date": "2026-11-08",
                "time": "夕方",
                "title": "夕方：美容院（11連休最終日・確定予定）",
                "category": "確定予定",
                "location": "美容院",
                "cost_note": "美容院代",
                "is_milestone": False,
            },
        ]

        # Google Calendar iCal URL が設定されている場合は簡易パースして統合
        ical_events: List[Dict[str, Any]] = []
        if settings.google_calendar_ical_url:
            try:
                async with httpx.AsyncClient(timeout=5.0) as client:
                    resp = await client.get(settings.google_calendar_ical_url)
                    if resp.status_code == 200:
                        ical_events = self._parse_simple_ical(resp.text)
            except Exception:
                pass

        today_blocks = [
            {"time": "07:30", "title": "朝ルーチン（お神体に一礼1拍手・歯磨き・ハンカチ）", "type": "routine"},
            {"time": "日中", "title": "学校授業 ＆ Antigravity 2.0 システム構築", "type": "must"},
            {"time": "放課後/帰宅後", "title": "帰ったら：Antigravity 2.0 スキル活用 / 休暇1週間プラン決定", "type": "want"},
            {"time": "夜 (30分)", "title": "趣味ガチャ試食 または『10月26日までに完成させる』1見出し執筆", "type": "trial"},
        ]

        return {
            "today_date": datetime.now().strftime("%Y-%m-%d (%a)"),
            "today_blocks": today_blocks,
            "upcoming_milestones": fixed_milestones + ical_events,
            "vacation_window": "10/29(木) 〜 11/8(日) [11日間]",
        }

    def _parse_simple_ical(self, ical_text: str) -> List[Dict[str, Any]]:
        events: List[Dict[str, Any]] = []
        blocks = ical_text.split("BEGIN:VEVENT")
        for b in blocks[1:10]:
            summary = ""
            dtstart = ""
            for line in b.splitlines():
                if line.startswith("SUMMARY:"):
                    summary = line.replace("SUMMARY:", "").strip()
                elif line.startswith("DTSTART"):
                    parts = line.split(":")
                    if len(parts) > 1:
                        raw_dt = parts[1].strip()
                        if len(raw_dt) >= 8:
                            dtstart = f"{raw_dt[:4]}-{raw_dt[4:6]}-{raw_dt[6:8]}"
            if summary:
                events.append({
                    "date": dtstart or "予定",
                    "time": "Googleカレンダー",
                    "title": summary,
                    "category": "Google Calendar",
                    "location": "",
                    "cost_note": "",
                    "is_milestone": False,
                })
        return events

    async def get_daily_suggestions(self) -> Dict[str, Any]:
        """
        空き時間・天気・予算・やりたいリスト・趣味ガチャを掛け合わせ、
        「今日おすすめの行動（Must / Want / 30分試食）」を理由付きで3件提案する。
        GEMINI_API_KEY 設定時は Gemini API を呼び出し、未設定時も実Vaultに基づくスマート提案を返す。
        """
        weather = await self.get_weather()
        yaru = obsidian_service.parse_yaru_memo()
        gacha_sample = obsidian_service.draw_gacha("ALL")
        sample_item = gacha_sample.get("item") or {"title": "超かぐや姫! / 積みゲー", "source": "STORY"}

        # 未完了の朝ルーチンや今日タスクを確認
        unchecked_routines = [
            item["text"]
            for item in yaru["sections"]["morning_routine"]
            if item.get("is_checkbox") and not item.get("checked")
        ]

        default_proposals = [
            {
                "slot": "MUST / 最優先フォーカス",
                "badge": "Must",
                "title": "『10月26日までに完成させる』の見出し1つ（15分）＋ 休暇の事前準備チェック",
                "action_detail": (
                    "10/26の完成目標に向けて「中の上」「ゲーム」「超かぐや姫!」など書きやすい見出しを1つだけラフに書く。"
                    "あわせて父へのドライブ相談（10/31, 11/1, 11/3の朝候補）を今日中に一言伝えておくと休暇がスムーズ！"
                ),
                "reason": (
                    f"10/26の締め切りまであと数日＆10/29からの11連休の要予約・相談項目（父とドライブ・卓球）を先に押さえると、"
                    f"頭の中の『考えなきゃいけないノイズ』が一気に消えます。"
                    + (f"（未チェックの朝ルーチン: {', '.join(unchecked_routines)}）" if unchecked_routines else "")
                ),
                "estimated_time": "20〜30分",
                "estimated_cost": "¥0",
            },
            {
                "slot": "WANT / 帰ったら・気分転換",
                "badge": "Want",
                "title": "帰宅後：Antigravity 2.0 ＆ ローカル環境でテキスト適合・ファインチューニング実験",
                "action_detail": (
                    f"現在の天気は「{weather['condition']}（{weather['temperature']}℃）」。"
                    "『やるメモ.md』の「帰ったら」にある Antigravity 2.0 のスキル活用や、気になっていたテキスト適合・"
                    "ピアノのゲーム感覚練習（1曲フレーズだけ）をコスト0円で楽しむ。"
                ),
                "reason": (
                    "来月の Meta Quest 3 購入（資産6〜7万＋バイト代4〜5万）に向けて平日は0円クリエイティブ趣味が最適。"
                    "環境をトリガーにして帰宅後すぐPCまたはピアノに触れると満足度が高いです。"
                ),
                "estimated_time": "45分",
                "estimated_cost": "¥0（Quest 3貯金維持）",
            },
            {
                "slot": "TRIAL / 30分だけ趣味ガチャ試食",
                "badge": "30分試食",
                "title": f"趣味ガチャ試食：『{sample_item['title']}』({sample_item['source']}) を30分だけ触る",
                "action_detail": (
                    f"Obsidianの積みリスト（全{gacha_sample['counts']['ALL']}件）から抽選された『{sample_item['title']}』を、"
                    "「1話 / 1章 / 30分だけ」タイマーを回して試食する。良ければ『いまやってる・見てるもの』へ昇格！"
                ),
                "reason": (
                    "「最初から全部やろう」とすると重くなるので、30分試食ルールで気軽に当たり外れを判定するのが"
                    "一番脳のメモリを消費しません。"
                ),
                "estimated_time": "30分（タイマー推奨）",
                "estimated_cost": "¥0",
                "gacha_item": sample_item,
            },
        ]

        if settings.has_gemini:
            try:
                gemini_proposals = await self._call_gemini_for_proposals(weather, yaru, sample_item)
                if gemini_proposals:
                    return {
                        "generated_by": "Gemini API + Obsidian Vault Context",
                        "weather_context": f"{weather['location']} {weather['icon']} {weather['condition']} {weather['temperature']}℃",
                        "proposals": gemini_proposals,
                        "updated_at": datetime.now().isoformat(),
                    }
            except Exception:
                pass

        return {
            "generated_by": "Vault Context Engine (Smart Rule + Real Note Analysis)",
            "weather_context": f"{weather['location']} {weather['icon']} {weather['condition']} {weather['temperature']}℃",
            "proposals": default_proposals,
            "updated_at": datetime.now().isoformat(),
        }

    async def _call_gemini_for_proposals(
        self,
        weather: Dict[str, Any],
        yaru: Dict[str, Any],
        sample_item: Dict[str, Any],
    ) -> Optional[List[Dict[str, Any]]]:
        url = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"gemini-2.5-flash:generateContent?key={settings.gemini_api_key}"
        )
        prompt = (
            "あなたはユーザーのパーソナルコンシェルジュです。以下の実データに基づき、"
            "今日おすすめの行動を Must / Want / 30分試食 の3件、JSON配列で出力してください。\n"
            f"- 天気: {weather['location']} {weather['condition']} {weather['temperature']}℃\n"
            f"- 目標: 10/26までに執筆完成、10/27で20歳誕生日、10/29-11/8は11連休、来月Quest3購入目標(資産6-7万)\n"
            f"- ガチャ候補: {sample_item['title']} ({sample_item['source']})\n"
            "各要素は slot, badge, title, action_detail, reason, estimated_time, estimated_cost キーを持つJSONオブジェクトにしてください。"
        )
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(url, json=payload)
            resp.raise_for_status()
            body = resp.json()
            text = body["candidates"][0]["content"]["parts"][0]["text"]
            parsed = json.loads(text)
            if isinstance(parsed, list) and len(parsed) >= 3:
                return parsed[:3]
        return None


concierge_service = ConciergeService()
