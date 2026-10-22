from typing import List, Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from backend.config import STATIC_DIR, settings
from backend.services.concierge_service import concierge_service
from backend.services.feed_service import feed_service
from backend.services.obsidian_service import obsidian_service

app = FastAPI(
    title="Daily Concierge & Personal Hub API",
    description="余計なことを考える手間を減らし、今の私を明瞭にするパーソナル情報ハブ＆デイリーコンシェルジュ",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ------------------------------------------------------------------
# Request Models
# ------------------------------------------------------------------
class ToggleTaskRequest(BaseModel):
    line_number: Optional[int] = None
    text_match: Optional[str] = None
    checked: Optional[bool] = None


class QuickMemoRequest(BaseModel):
    text: str
    target_section: str = "auto"
    as_checkbox: bool = True


class GachaDrawRequest(BaseModel):
    category: str = "ALL"


class GachaActionRequest(BaseModel):
    action: str  # "good" | "drop" | "try" | "meh"
    title: str
    source: str  # "GAME" | "STORY" | "SINGLE"
    raw_line: Optional[str] = None


class MarkReadRequest(BaseModel):
    item_ids: Optional[List[int]] = None
    category: Optional[str] = None
    mark_all: bool = False


class BookmarkRequest(BaseModel):
    item_id: int
    clip_to_vault: bool = True


class AddSourceRequest(BaseModel):
    url: str
    instruction: str
    name: Optional[str] = None
    category: str = "sns_diff"
    save: bool = True


# ------------------------------------------------------------------
# API Endpoints: System & Status
# ------------------------------------------------------------------
@app.get("/api/status")
async def get_system_status():
    return {
        "ok": True,
        "vault_path": str(obsidian_service.vault_path),
        "vault_accessible": settings.is_vault_accessible,
        "has_gemini_key": settings.has_gemini,
        "has_supabase": settings.has_supabase,
        "weather_location": settings.weather_location_name,
        "db_path": str(feed_service.db_path),
    }


@app.get("/api/dashboard")
async def get_dashboard_overview():
    """初期表示に必要なToday・天気・予定・AI提案・やるメモ・趣味ガチャ・未読数を一括取得"""
    weather = await concierge_service.get_weather()
    schedule = await concierge_service.get_schedule_timeline()
    suggestions = await concierge_service.get_daily_suggestions()
    yaru_memo = obsidian_service.parse_yaru_memo()
    gacha_info = obsidian_service.get_gacha_pool("ALL")
    profile = obsidian_service.get_profile_summary()
    feeds_summary = feed_service.get_feeds(unread_only=False, limit=30)

    return {
        "ok": True,
        "status": {
            "vault_path": str(obsidian_service.vault_path),
            "vault_accessible": settings.is_vault_accessible,
            "has_gemini": settings.has_gemini,
            "has_supabase": settings.has_supabase,
        },
        "weather": weather,
        "schedule": schedule,
        "suggestions": suggestions,
        "yaru_memo": yaru_memo,
        "gacha": {
            "counts": gacha_info["counts"],
            "current_doing": gacha_info["current_doing"],
            "recent_logs": gacha_info["recent_logs"],
        },
        "profile": profile,
        "feeds_summary": {
            "total_unread": feeds_summary["total_unread"],
            "unread_by_category": feeds_summary["unread_by_category"],
        },
    }


# ------------------------------------------------------------------
# API Endpoints: Obsidian Sync (やるメモ.md / 趣味ガチャ / プロファイル)
# ------------------------------------------------------------------
@app.get("/api/obsidian/yaru-memo")
async def get_yaru_memo():
    return obsidian_service.parse_yaru_memo()


@app.post("/api/obsidian/toggle-task")
async def toggle_yaru_memo_task(req: ToggleTaskRequest):
    res = obsidian_service.toggle_task(
        line_number=req.line_number,
        text_match=req.text_match,
        checked=req.checked,
    )
    if not res.get("ok"):
        raise HTTPException(status_code=400, detail=res.get("error", "Toggle failed"))
    return res


@app.post("/api/obsidian/quick-memo")
async def append_quick_memo(req: QuickMemoRequest):
    res = obsidian_service.append_quick_memo(
        text=req.text,
        target_section=req.target_section,
        as_checkbox=req.as_checkbox,
    )
    if not res.get("ok"):
        raise HTTPException(status_code=400, detail=res.get("error", "Append failed"))
    return res


@app.get("/api/obsidian/gacha/pool")
async def get_gacha_pool(category: str = Query("ALL")):
    return obsidian_service.get_gacha_pool(category)


@app.post("/api/obsidian/gacha/draw")
async def draw_gacha(req: GachaDrawRequest):
    return obsidian_service.draw_gacha(req.category)


@app.post("/api/obsidian/gacha/action")
async def gacha_action(req: GachaActionRequest):
    res = obsidian_service.apply_gacha_action(
        action=req.action,
        title=req.title,
        source=req.source,
        raw_line=req.raw_line,
    )
    if not res.get("ok"):
        raise HTTPException(status_code=400, detail=res.get("error", "Action failed"))
    return res


@app.get("/api/obsidian/profile")
async def get_profile():
    return obsidian_service.get_profile_summary()


# ------------------------------------------------------------------
# API Endpoints: Weather, Schedule & AI Concierge Suggestions
# ------------------------------------------------------------------
@app.get("/api/concierge/weather")
async def get_weather(refresh: bool = Query(False)):
    return await concierge_service.get_weather(force_refresh=refresh)


@app.get("/api/concierge/schedule")
async def get_schedule():
    return await concierge_service.get_schedule_timeline()


@app.get("/api/concierge/suggestions")
async def get_suggestions():
    return await concierge_service.get_daily_suggestions()


# ------------------------------------------------------------------
# API Endpoints: SNS Diff Feeds, AI News, Deals & Watch Sources
# ------------------------------------------------------------------
@app.get("/api/feeds")
async def list_feeds(
    category: Optional[str] = Query(None),
    source_type: Optional[str] = Query(None),
    unread_only: bool = Query(False),
    limit: int = Query(50),
):
    return feed_service.get_feeds(
        category=category,
        source_type=source_type,
        unread_only=unread_only,
        limit=limit,
    )


@app.post("/api/feeds/mark-read")
async def mark_feeds_read(req: MarkReadRequest):
    return feed_service.mark_read(
        item_ids=req.item_ids,
        category=req.category,
        mark_all=req.mark_all,
    )


@app.post("/api/feeds/bookmark")
async def toggle_feed_bookmark(req: BookmarkRequest):
    res = feed_service.toggle_bookmark_and_clip(
        item_id=req.item_id,
        clip_to_vault=req.clip_to_vault,
    )
    if not res.get("ok"):
        raise HTTPException(status_code=404, detail=res.get("error", "Item not found"))
    return res


@app.post("/api/feeds/refresh")
async def refresh_feeds():
    return await feed_service.refresh_all_sources()


@app.get("/api/sources")
async def list_watch_sources():
    return {"sources": feed_service.list_sources()}


@app.post("/api/sources/analyze")
async def analyze_and_add_source(req: AddSourceRequest):
    return await feed_service.analyze_and_add_source(
        url=req.url,
        instruction=req.instruction,
        name=req.name,
        category=req.category,
        save=req.save,
    )


@app.delete("/api/sources/{source_id}")
async def remove_watch_source(source_id: int):
    return feed_service.delete_source(source_id)


# ------------------------------------------------------------------
# Static Files & Web Dashboard Serving
# ------------------------------------------------------------------
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/")
async def serve_dashboard():
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        return FileResponse(str(index_file))
    return {"message": "Daily Concierge API is running. Dashboard UI is at /static/index.html"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=False)
