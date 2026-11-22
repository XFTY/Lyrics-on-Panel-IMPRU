import base64
import json
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import urllib.request
from urllib.parse import quote, unquote, urlencode, urlparse


class LyricsFetchingMixin:
    """Lyrics retrieval from local files and online providers."""

    def _store_fetched_lyrics(self, lyrics, fetch_id, artists, title, cache=True):
        with self.lock:
            if self._fetch_id != fetch_id:
                return False
            self.lyrics = lyrics
            if lyrics and cache:
                cache_key = self._make_cache_key(artists, title)
                self.lyrics_cache[cache_key] = lyrics
                self._save_cached_lyrics(cache_key, lyrics)
        return True

    def _fetch_lyrics(self, playername, track_info, fetch_id):
        # Check if this fetch is still current
        if self._fetch_id != fetch_id:
            return
        title = track_info['title']
        artists = track_info['artist']
        artist = artists[0] if artists else ''
        album = track_info['album']
        length = track_info['length']
        url = track_info['url']
        if not title or not artists:
            return
        try:
            lyrics = None
            if playername == 'org.mpris.MediaPlayer2.yesplaymusic':
                lyrics = self._fetch_lyrics_ypm(title)
            elif playername == 'org.mpris.MediaPlayer2.lx-music-desktop':
                lyrics = self._fetch_lyrics_lxmusic()
            else:
                lyrics = self._fetch_lyrics_local(url)
                if lyrics is None:
                    # Check again before expensive HTTP calls
                    if self._fetch_id != fetch_id:
                        return
                    # Show LRCLIB line-synced lyrics immediately when available
                    lyrics = self._fetch_lyrics_lrclib(title, artist, album, length, 8)
                    if lyrics is not None:
                        self._store_fetched_lyrics(lyrics, fetch_id, artists, title, cache=False)
                    # Prefer Kugou KRC when it provides word-level timings
                    if lyrics is None or not self._has_word_lyrics(lyrics):
                        if self._fetch_id != fetch_id:
                            return
                        k_lyrics = self._fetch_lyrics_kugou(title, artist, 8)
                        if k_lyrics:
                            if self._has_word_lyrics(k_lyrics) or lyrics is None or self._is_estimated(lyrics):
                                lyrics = k_lyrics
            self._store_fetched_lyrics(lyrics, fetch_id, artists, title)
        except Exception as e:
            with self.lock:
                if self._fetch_id == fetch_id:
                    self.lyrics = None

    def _http_get(self, url, timeout=10):
        """Simple HTTP GET using urllib with custom User-Agent. Returns (status_code, data) tuple."""
        try:
            req = urllib.request.Request(
                url,
                headers={
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
                }
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read().decode('utf-8')
        except Exception:
            return None, None

    def _fetch_lyrics_ypm(self, title):
        """Fetch lyrics from YesPlayMusic localhost API. Returns parsed lyrics or None."""
        ypm_base_url = "http://localhost:27232"
        status, text = self._http_get(f"{ypm_base_url}/player")
        if status != 200:
            return None
        data = json.loads(text)
        if not data or not data.get('currentTrack') or data['currentTrack'].get('name') != title:
            return None
        track_id = data['currentTrack']['id']
        status, text = self._http_get(f"{ypm_base_url}/api/lyric?id={track_id}")
        if status != 200:
            return None
        data = json.loads(text)
        if data and data.get('lrc') and data['lrc'].get('lyric'):
            return self._parse_lrc(data['lrc']['lyric'])
        return None

    def _fetch_lyrics_lxmusic(self, port=23330):
        """Fetch lyrics from LX Music localhost API. Returns parsed lyrics or None."""
        lxmusic_base_url = f"http://localhost:{port}"
        status, text = self._http_get(f"{lxmusic_base_url}/lyric")
        if status == 200 and text:
            return self._parse_lrc(text)
        return None

    def _fetch_lyrics_local(self, song_path):
        """Fetch lyrics from disk."""
        if not song_path.startswith('file://'):
            return None
        lrc_path = Path(unquote(urlparse(song_path).path)).with_suffix('.lrc')
        try:
            content = lrc_path.read_text(encoding='utf-8')
        except (FileNotFoundError, PermissionError, OSError):
            return None
        return self._parse_lrc(content)

    def _fetch_lyrics_lrclib(self, title, artist, album, length, timeout=5):
        """Fetch lyrics from lrclib.net (compatible mode). Returns parsed lyrics or None."""
        duration_sec = length // 1000000 if length else None
        c_title = self._clean_title(title)
        c_artist = self._clean_artist(artist)

        params = urlencode({
            'track_name': c_title,
            'artist_name': c_artist,
            'album_name': album
        })

        def fetch_exact():
            if not duration_sec:
                return (None, None)
            url = f"https://lrclib.net/api/get?{params}&duration={duration_sec}"
            status, text = self._http_get(url, timeout)
            if status == 200 and text:
                data = json.loads(text)
                return (data.get('syncedLyrics'), data.get('plainLyrics'))
            return (None, None)

        def fetch_search():
            q_str = f"{c_artist} {c_title}"
            url = f"https://lrclib.net/api/search?q={quote(q_str)}"
            status, text = self._http_get(url, timeout)
            if status == 200 and text:
                data = json.loads(text)
                synced_m, plain_m = None, None
                for result in data:
                    res_artist = result.get('artistName', '').lower()
                    if c_artist.lower() in res_artist or res_artist in c_artist.lower() or not c_artist:
                        if result.get('syncedLyrics') and not synced_m:
                            synced_m = result['syncedLyrics']
                        if result.get('plainLyrics') and not plain_m:
                            plain_m = result['plainLyrics']
                return (synced_m, plain_m)
            return (None, None)

        def fetch_fuzzy():
            url = f"https://lrclib.net/api/search?q={quote(c_title)}"
            status, text = self._http_get(url, timeout)
            if status == 200 and text:
                data = json.loads(text)
                synced_m, plain_m = None, None
                for result in data:
                    res_artist = result.get('artistName', '').lower()
                    if c_artist.lower() in res_artist or res_artist in c_artist.lower() or not c_artist:
                        if result.get('syncedLyrics') and not synced_m:
                            synced_m = result['syncedLyrics']
                        if result.get('plainLyrics') and not plain_m:
                            plain_m = result['plainLyrics']
                return (synced_m, plain_m)
            return (None, None)

        # Run all fetches in parallel
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {
                executor.submit(fetch_exact): 0,
                executor.submit(fetch_search): 1,
                executor.submit(fetch_fuzzy): 2,
            }
            results = [(None, None), (None, None), (None, None)]
            for future in as_completed(futures):
                priority = futures[future]
                try:
                    results[priority] = future.result()
                except Exception:
                    pass

        # 1. Prefer synced lyrics
        for synced, plain in results:
            if synced:
                return self._parse_lrc(synced)

        # 2. Fallback to plain lyrics candidate
        for synced, plain in results:
            if plain:
                parsed = self._parse_plain_lrc(plain, length)
                if parsed:
                    return parsed
        return None

    def _fetch_lyrics_kugou(self, title, artist, timeout=5):
        """Fetch lyrics from Kugou Music API. Prefers KRC word-level lyrics."""
        c_title = self._clean_title(title)
        c_artist = self._clean_artist(artist)
        q = f"{c_title} {c_artist}".strip()
        if not q:
            return None
        url = f"http://mobilecdn.kugou.com/api/v3/search/song?keyword={quote(q)}&page=1&pagesize=5"
        status, text = self._http_get(url, timeout)
        if status != 200 or not text:
            return None
        try:
            data = json.loads(text)
            info = data.get('data', {}).get('info', [])
            if not info:
                return None
            hash_val = info[0]['hash']
            l_url = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword={quote(q)}&hash={hash_val}"
            l_status, l_text = self._http_get(l_url, timeout)
            if l_status != 200 or not l_text:
                return None
            l_data = json.loads(l_text)
            cands = l_data.get('candidates', [])
            if not cands:
                return None
            cand_id = cands[0]['id']
            accesskey = cands[0]['accesskey']

            def download(fmt):
                d_url = f"http://krcs.kugou.com/download?ver=1&client=mobi&id={cand_id}&accesskey={accesskey}&fmt={fmt}"
                d_status, d_text = self._http_get(d_url, timeout)
                if d_status != 200 or not d_text:
                    return None
                content = json.loads(d_text).get('content', '')
                if not content:
                    return None
                return base64.b64decode(content)

            krc_raw = download('krc')
            krc_lyrics = None
            if krc_raw:
                decoded = self._decode_krc(krc_raw)
                if decoded:
                    krc_lyrics = self._parse_krc(decoded)
                    if self._has_word_lyrics(krc_lyrics):
                        return krc_lyrics

            lrc_raw = download('lrc')
            if lrc_raw:
                lrc = lrc_raw.decode('utf-8', errors='ignore')
                parsed = self._parse_lrc(lrc)
                if parsed:
                    return parsed
            return krc_lyrics
        except Exception as e:
            print(f"[DEBUG] Kugou lyrics fetch error: {e}")
        return None

