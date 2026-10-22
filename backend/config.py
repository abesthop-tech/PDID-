import os
from pathlib import Path
from dotenv import load_dotenv

# Project root and backend directories
BACKEND_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BACKEND_DIR.parent
DATA_DIR = BACKEND_DIR / "data"
STATIC_DIR = BACKEND_DIR / "static"

# Ensure data and static directories exist
DATA_DIR.mkdir(parents=True, exist_ok=True)
STATIC_DIR.mkdir(parents=True, exist_ok=True)

# Load .env from project root or backend directory
env_path = PROJECT_ROOT / ".env"
if env_path.exists():
    load_dotenv(env_path)
else:
    backend_env = BACKEND_DIR / ".env"
    if backend_env.exists():
        load_dotenv(backend_env)


def detect_obsidian_vault_path() -> Path:
    r"""
    Detect Obsidian Vault path:
    1. Explicit OBSIDIAN_VAULT_PATH from environment / .env
    2. School PC network redirect path: \\10.32.97.1\ProfilesRedirect$\25JN0419\Documents\obs
    3. Common home PC paths: ~/Documents/obs, ~/Obsidian/obs
    4. Fallback local mock vault inside backend/data/mock_vault if none exist
    """
    env_val = os.getenv("OBSIDIAN_VAULT_PATH", "").strip()
    if env_val:
        p = Path(env_val).expanduser()
        if p.exists():
            return p

    candidates = [
        Path(r"\\10.32.97.1\ProfilesRedirect$\25JN0419\Documents\obs"),
        Path.home() / "Documents" / "obs",
        Path.home() / "Obsidian" / "obs",
        Path.home() / "OneDrive" / "Documents" / "obs",
    ]
    for candidate in candidates:
        try:
            if candidate.exists():
                return candidate
        except Exception:
            continue

    if env_val:
        return Path(env_val).expanduser()

    fallback = DATA_DIR / "mock_vault"
    (fallback / "01_Inbox").mkdir(parents=True, exist_ok=True)
    return fallback


class Settings:
    def __init__(self) -> None:
        self.obsidian_vault_path: Path = detect_obsidian_vault_path()
        self.gemini_api_key: str = os.getenv("GEMINI_API_KEY", "").strip()
        self.supabase_url: str = os.getenv("SUPABASE_URL", "").strip()
        self.supabase_key: str = (
            os.getenv("SUPABASE_KEY", "").strip()
            or os.getenv("SUPABASE_ANON_KEY", "").strip()
        )
        self.weather_lat: float = float(os.getenv("WEATHER_LAT", "35.6436"))
        self.weather_lon: float = float(os.getenv("WEATHER_LON", "139.6715"))
        self.weather_location_name: str = os.getenv(
            "WEATHER_LOCATION_NAME", "三軒茶屋・世田谷"
        ).strip()
        self.google_calendar_ical_url: str = os.getenv(
            "GOOGLE_CALENDAR_ICAL_URL", ""
        ).strip()
        self.db_path: Path = DATA_DIR / "concierge.db"
        self.backup_dir: Path = DATA_DIR / "vault_backups"
        self.backup_dir.mkdir(parents=True, exist_ok=True)

    @property
    def is_vault_accessible(self) -> bool:
        try:
            return self.obsidian_vault_path.exists()
        except Exception:
            return False

    @property
    def has_gemini(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def has_supabase(self) -> bool:
        return bool(self.supabase_url and self.supabase_key)


settings = Settings()
