import hashlib
import json
import time
from pathlib import Path

from .constants import CACHE_VERSION


class CacheMixin:
    """In-memory and on-disk lyrics cache."""

    def _make_cache_key(self, artists, title):
        artists_str = ", ".join(artists) if isinstance(artists, list) else (artists or "")
        return f"{CACHE_VERSION}|{artists_str} - {title}"

    def _get_cached_lyrics(self, cache_key):
        # 1. Check in-memory cache
        if cache_key in self.lyrics_cache:
            return self.lyrics_cache[cache_key]
        
        # 2. Check disk cache
        try:
            h = hashlib.sha256(cache_key.encode('utf-8')).hexdigest()
            cache_file = Path("/tmp/lyrics-on-panel-cache") / f"{h}.json"
            if cache_file.exists():
                lyrics = json.loads(cache_file.read_text(encoding='utf-8'))
                self.lyrics_cache[cache_key] = lyrics
                return lyrics
        except Exception as e:
            print(f"[DEBUG] Error reading disk cache: {e}")
        return None

    def _save_cached_lyrics(self, cache_key, lyrics):
        try:
            # Keep memory cache under 50 items
            if len(self.lyrics_cache) > 50:
                oldest = next(iter(self.lyrics_cache))
                self.lyrics_cache.pop(oldest, None)
            
            cache_dir = Path("/tmp/lyrics-on-panel-cache")
            cache_dir.mkdir(parents=True, exist_ok=True)
            h = hashlib.sha256(cache_key.encode('utf-8')).hexdigest()
            cache_file = cache_dir / f"{h}.json"
            cache_file.write_text(json.dumps(lyrics), encoding='utf-8')
            
            # Prune disk cache if more than 100 files
            files = list(cache_dir.glob("*.json"))
            if len(files) > 100:
                now = time.time()
                for f in files:
                    try:
                        if now - f.stat().st_mtime > 3 * 86400:
                            f.unlink(missing_ok=True)
                    except Exception:
                        pass
        except Exception as e:
            print(f"[DEBUG] Error writing disk cache: {e}")

