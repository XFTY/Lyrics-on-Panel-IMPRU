import json
import re
import time
import base64
import zlib
import threading
import hashlib
import subprocess
import http.server
import socketserver
from pathlib import Path
import urllib.request
from urllib.parse import quote, unquote, urlencode, urlparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from mpris_prober import find_players, find_playing_players
from mpris_player import MprisPlayer, PlaybackStatus
from zh_convert import to_simplified

BROWSER_HINTS = ("edge", "firefox", "chrome", "chromium", "brave", "opera", "vivaldi", "browser-integration")
STREAMING_HINTS = (
    "sidra", "cider", "yesplaymusic", "yesplay music", "spotube", "tizonia",
    "qqmusic", "qq音乐", "qq music",
    "spotify",
    "youtubemusic", "youtube music", "youtube-music",
    "tidal", "qobuz",
)
CACHE_VERSION = "3"
KRC_KEY = bytes([
    0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
    0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
])
LRC_TIME_RE = re.compile(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]')
LRC_WORD_RE = re.compile(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>')
KRC_LINE_RE = re.compile(r'^\[(\d+),(\d+)\](.*)$')
KRC_WORD_RE = re.compile(r'<(\d+),(\d+)(?:,(\d+))?>')

class LyricsManager:
    """
    Core Controller: Manages player selection, tracking, and lyrics fetching.

    Note: ms here == microseconds, not miliseconds.
    """
    def __init__(self):
        self.lyrics_cache = {}
        self.players_cache = {}
        self._search_cache = {}
        self._fetch_id = 0
        self._play_order = {}
        self._next_play_order = 0
        self.lock = threading.Lock()
        self.setup()
    
    def get_player(self, playername):
        player = self.players_cache.get(playername)
        if not player or not player.obj:
            player = MprisPlayer(playername)
            self.players_cache[playername] = player
        return player

    def _player_text(self, playername):
        text = playername.lower()
        try:
            identity = self.get_player(playername).identity
            if identity:
                text += " " + identity.lower()
        except Exception:
            pass
        return text

    def _player_matches(self, playername, hints):
        text = self._player_text(playername)
        return any(hint in text for hint in hints)

    def _is_browser_player(self, playername):
        return self._player_matches(playername, BROWSER_HINTS)

    def _is_streaming_player(self, playername):
        return self._player_matches(playername, STREAMING_HINTS)

    def _browser_priority(self, playername):
        text = self._player_text(playername)
        if "edge" in text:
            return 0
        if "firefox" in text:
            return 1
        if "chrome" in text:
            return 2
        if "chromium" in text:
            return 3
        if "brave" in text:
            return 4
        if "opera" in text:
            return 5
        if "vivaldi" in text:
            return 6
        if "browser-integration" in text:
            return 7
        return 9

    def _select_mode_player(self, mode, playernames, playing_playernames, preferred=None):
        def matches(playername):
            if mode == "browser":
                return self._is_browser_player(playername)
            if mode == "streaming":
                return self._is_streaming_player(playername)
            return False

        candidates = [p for p in playernames if matches(p)]
        if not candidates:
            return None

        playing_candidates = [p for p in playing_playernames if p in candidates]
        if playing_candidates:
            if mode == "browser":
                return min(playing_candidates, key=self._browser_priority)
            if mode == "streaming":
                # The streaming app that started playing first keeps display priority.
                return min(playing_candidates, key=lambda p: self._play_order.get(p, float("inf")))
            if preferred in playing_candidates:
                return preferred
            return playing_candidates[0]

        if mode == "browser":
            return min(candidates, key=self._browser_priority)
        if preferred in candidates:
            return preferred
        return candidates[0]

    def _has_other_app_playing(self, mode, playing_playernames, target):
        for playername in playing_playernames:
            if playername == target:
                continue
            if mode == "browser" and not self._is_browser_player(playername):
                return True
            if mode == "streaming" and not self._is_streaming_player(playername):
                return True
        return False
    
    
    def setup(self, playername=None, playerobj=None, title=None, artist=None, album=None,
              duration=0, identity=None, lyrics=None, current_lyric=None,
              playback_status=PlaybackStatus.STOPPED, position_ms=0, available_players=None,
              next_lyric=None, current_lyric_duration_ms=0, time_remaining_ms=0, art_url="",
              has_word_lyrics=False, current_words=None, current_line_start_ms=0,
              current_line_end_ms=0, karaoke_position_ms=0, extra_lyrics_info=None):
        self.playername = playername
        self.playerobj = playerobj
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.identity = identity
        self.lyrics = lyrics
        self.current_lyric = current_lyric
        self.playback_status = playback_status
        self.position_ms = position_ms
        self.available_players = available_players or []
        self.next_lyric = next_lyric
        self.current_lyric_duration_ms = current_lyric_duration_ms
        self.time_remaining_ms = time_remaining_ms
        self.art_url = art_url
        self.has_word_lyrics = has_word_lyrics
        self.current_words = current_words or []
        self.current_line_start_ms = current_line_start_ms
        self.current_line_end_ms = current_line_end_ms
        self.karaoke_position_ms = karaoke_position_ms
        self.extra_lyrics_info = extra_lyrics_info or {}
    
    
    def poll_status(self, requested_playername=None, mode="global", convert_to_simplified=False):
        """
        Polls for player changes and state updates.
        
        requested_playername == None => Global Mode
                        == 'org.mpris.MediaPlayer2.spotify' => Spotify Mode
                        == 'org.mpris.MediaPlayer2.yesplaymusic' => YesPlayMusic Mode

        mode == "global"    => match whichever player is playing (legacy behaviour)
             == "browser"   => only match browsers (Edge > Firefox > Chrome > Chromium > ...)
             == "streaming" => only match Sidra, Cider, YesPlayMusic, Spotube, Tizonia,
                               QQ Music, Spotify, YouTube Music Desktop, Tidal, or Qobuz;
                               the app that started playing first is preferred

        In browser/streaming modes the widget tracks the target player while its
        MPRIS interface exists, including paused states, and hides when the
        target application exits or an unrelated application is playing.
        
        Args:
            requested_playername (str, optional): The specific DBus name to track (e.g. 'org.mpris.MediaPlayer2.spotify').
                                             If None, defaults to the first available player.
            mode (str, optional): Playback matching mode.
        """
        with self.lock:
            playernames = find_players()
            # Clean up cached players that are no longer running
            for name in list(self.players_cache.keys()):
                if name not in playernames:
                    self.players_cache.pop(name, None)
            for name in list(self._play_order.keys()):
                if name not in playernames:
                    self._play_order.pop(name, None)

            # Selection Logic:
                # 1. If there is no avaiable mpris complaint player, return empty State.
                # 2. If a specific target is requested:
                    # 2.1 If the requested target exists in the mpris2 dbus interface: pick it.
                    # 2.2 Otherwise, return empty state as the requested player is not playing.
                # 3. If no target requested, and then we enter the multiplexing mode. 
                    # 3.1 If there is a player with playing status, pick it.
                    # 3.2 If there is no player with playing status, fallback to the first player(paused/stopped) exists in mpris dbus.
                        # 3.2.1 If there is no player exists in the mpris dbus, return empty state.
            def set_free():
                self.setup()
                return self._get_empty_state()
            
            if not playernames:
                return set_free()

            mode = (mode or "global").lower()
            if mode == "sidra":
                mode = "streaming"
            playing_playernames = find_playing_players(playernames)
            for name in playernames:
                if name in playing_playernames and name not in self._play_order:
                    self._play_order[name] = self._next_play_order
                    self._next_play_order += 1

            if mode in ("browser", "streaming"):
                target = self._select_mode_player(mode, playernames, playing_playernames, self.playername)
                if not target:
                    return set_free()
                if self._has_other_app_playing(mode, playing_playernames, target):
                    return set_free()
                requested_playername = target

            current_playername = self.playername
            current_playerobj = None
            if requested_playername:
                 if requested_playername in playernames:
                     current_playername = requested_playername
                 else:
                    return self._get_empty_state()
            else:
                # Global mode: find the best player
                # If we have a current player, check if it's still valid
                if self.playername and self.playername in playernames:
                    try:
                        player = self.get_player(self.playername)
                        if player.obj:
                            if player.playback_status == PlaybackStatus.PLAYING:
                                # Current player is playing, use it
                                current_playername = self.playername
                                current_playerobj = player
                            else:
                                # Current player paused/stopped, check for other playing players
                                if playing_playernames:
                                    current_playername = playing_playernames[0]
                                else:
                                    # No playing player, keep current one
                                    current_playername = self.playername
                                    current_playerobj = player
                    except Exception:
                        pass
                # No valid current player, find one
                if not current_playerobj:
                    if playing_playernames:
                        current_playername = playing_playernames[0]
                    elif playernames:
                        current_playername = playernames[0]
                    else:
                        return set_free()
                    current_playerobj = self.get_player(current_playername)
            if not current_playerobj:
                current_playerobj = self.get_player(current_playername)
            if not current_playerobj.obj:
                return set_free()
            # Cache DBus properties to avoid repeated calls
            try:
                track_info = current_playerobj.track_info
                playback_status = current_playerobj.playback_status
                position = current_playerobj.position
                identity = current_playerobj.identity
            except Exception:
                return set_free()
            if identity == "Unknown":
                self.players_cache.pop(current_playername, None)
                return set_free()
            track_changed = (self.title != track_info['title']
                    or self.artist != track_info['artist']
                    or self.album != track_info['album'])
            if track_changed:
                self.title = track_info['title']
                self.artist = track_info['artist']
                self.album = track_info['album']
                self._fetch_id += 1
                # Check if this track has cached lyrics
                cache_key = self._make_cache_key(track_info['artist'], track_info['title'])
                cached_lyrics = self._get_cached_lyrics(cache_key)
                if cached_lyrics:
                    self.lyrics = cached_lyrics
                else:
                    self.lyrics = None
                    threading.Thread(target=self._fetch_lyrics, args=(current_playername, track_info, self._fetch_id), daemon=True).start()
            self.position_ms = position
            lyrics_info = self._get_lyrics_info(convert_to_simplified)
            self.setup(
                playername=current_playername,
                playerobj=current_playerobj,
                title=track_info['title'],
                artist=track_info['artist'],
                album=track_info['album'],
                duration=track_info['length'],
                identity=identity,
                lyrics=self.lyrics,
                current_lyric=lyrics_info["current_lyric"],
                playback_status=playback_status,
                position_ms=position,
                available_players=playernames,
                next_lyric=lyrics_info["next_lyric"],
                current_lyric_duration_ms=lyrics_info["current_lyric_duration_ms"],
                time_remaining_ms=lyrics_info["time_remaining_ms"],
                art_url=track_info.get('art_url', ''),
                has_word_lyrics=lyrics_info["has_word_lyrics"],
                current_words=lyrics_info["current_words"],
                current_line_start_ms=lyrics_info["current_line_start_ms"],
                current_line_end_ms=lyrics_info["current_line_end_ms"],
                karaoke_position_ms=lyrics_info["position_ms"],
                extra_lyrics_info=lyrics_info
            )
            return self.get_state()


    def _clean_title(self, title):
        if not title:
            return ""
        cleaned = title
        # Remove Chinese transliteration in parentheses e.g. "Song (歌名)"
        cleaned = re.sub(r'[\(（][\u4e00-\u9fff\s·/、]+[\)）]', '', cleaned)
        cleaned = re.sub(r'[\(\[]feat\..*?[\)\]]', '', cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r'[\(\[](official|lyric|video|audio|remastered|live|deluxe|version|edit|explicit).*?[\)\]]', '', cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r'\s*-\s*(remastered|live|deluxe|bonus|radio edit|\d{4} remaster).*$', '', cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r'\s+', ' ', cleaned).strip()
        return cleaned if cleaned else title

    def _clean_artist(self, artist):
        if isinstance(artist, list):
            artist = artist[0] if artist else ""
        if not artist:
            return ""
        # Remove Chinese transliteration in parentheses e.g. "Lil Jon (乔纳森·史密斯)" -> "Lil Jon"
        cleaned = re.sub(r'[\(（][\u4e00-\u9fff\s·/、]+[\)）]', '', artist)
        cleaned = re.sub(r'\s*[/\\-]\s*[\u4e00-\u9fff\s·]+', '', cleaned)
        cleaned = re.sub(r'\s*(feat\.|ft\.).*$', '', cleaned, flags=re.IGNORECASE).strip()
        cleaned = re.sub(r'\s+', ' ', cleaned).strip()
        return cleaned if cleaned else artist

    def _clean_display_artist(self, artists):
        if not artists:
            return ""
        if isinstance(artists, str):
            artists = [artists]
        cleaned_list = []
        for a in artists:
            c = re.sub(r'[\(（][\u4e00-\u9fff\s·/、]+[\)）]', '', a)
            c = re.sub(r'\s*[/\\-]\s*[\u4e00-\u9fff\s·]+', '', c)
            c = re.sub(r'\s+', ' ', c).strip()
            cleaned_list.append(c if c else a)
        return ", ".join(cleaned_list)

    def _clean_display_title(self, title):
        if not title:
            return ""
        c = re.sub(r'[\(（][\u4e00-\u9fff\s·/、]+[\)）]', '', title)
        c = re.sub(r'\s+', ' ', c).strip()
        return c if c else title

    def _make_cache_key(self, artists, title):
        artists_str = ", ".join(artists) if isinstance(artists, list) else (artists or "")
        return f"{CACHE_VERSION}|{artists_str} - {title}"

    def _has_word_lyrics(self, lyrics):
        if not lyrics:
            return False
        return any(line.get('words') for line in lyrics)

    def _is_estimated(self, lyrics):
        return bool(lyrics) and bool(lyrics[0].get('is_estimated', False))

    def _time_to_us(self, minutes, seconds, fraction=None):
        frac = float(f"0.{fraction}") if fraction else 0.0
        return int((int(minutes) * 60 + int(seconds) + frac) * 1000000)

    def _trim_words(self, words):
        if not words:
            return words
        words[0]['text'] = words[0]['text'].lstrip()
        words[-1]['text'] = words[-1]['text'].rstrip()
        while len(words) > 1 and not words[0]['text']:
            words.pop(0)
        while len(words) > 1 and not words[-1]['text']:
            words.pop()
        if words and not words[0]['text']:
            words[0]['text'] = ''
        return words

    def _parse_word_body(self, body, line_time_us):
        words = []
        matches = list(LRC_WORD_RE.finditer(body))
        if matches:
            leading = body[:matches[0].start()]
            if leading.strip():
                words.append({"time_ms": line_time_us, "text": leading})
            for i, match in enumerate(matches):
                end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
                text = body[match.end():end]
                if not text:
                    continue
                word_time = self._time_to_us(match.group(1), match.group(2), match.group(3))
                words.append({"time_ms": word_time, "text": text})
        else:
            text = LRC_WORD_RE.sub('', body)
            if text.strip():
                words.append({"time_ms": line_time_us, "text": text})
        return self._trim_words(words)

    def _parse_krc(self, text):
        lines = []
        for raw in text.splitlines():
            match = KRC_LINE_RE.match(raw.strip())
            if not match:
                continue
            start_ms = int(match.group(1))
            duration_ms = int(match.group(2))
            body = match.group(3)
            words = []
            word_matches = list(KRC_WORD_RE.finditer(body))
            if word_matches:
                leading = body[:word_matches[0].start()]
                if leading.strip():
                    words.append({"time_ms": start_ms * 1000, "text": leading})
                for i, word_match in enumerate(word_matches):
                    end = word_matches[i + 1].start() if i + 1 < len(word_matches) else len(body)
                    word_text = body[word_match.end():end]
                    if not word_text:
                        continue
                    offset_ms = int(word_match.group(1))
                    words.append({
                        "time_ms": (start_ms + offset_ms) * 1000,
                        "text": word_text,
                    })
            else:
                plain = KRC_WORD_RE.sub('', body)
                if plain.strip():
                    words.append({"time_ms": start_ms * 1000, "text": plain})
            words = self._trim_words(words)
            lyric = ''.join(word['text'] for word in words)
            if not lyric or self._is_credit_line(lyric):
                continue
            line = {
                "time_ms": start_ms * 1000,
                "lyric": lyric,
                "duration_ms": duration_ms,
            }
            if len(words) > 1:
                line["words"] = words
            lines.append(line)
        lines.sort(key=lambda item: item['time_ms'])
        return lines

    def _decode_krc(self, raw):
        if not raw or raw[:4] != b'krc1':
            return None
        data = bytearray(raw[4:])
        for i in range(len(data)):
            data[i] ^= KRC_KEY[i % len(KRC_KEY)]
        try:
            return zlib.decompress(bytes(data)).decode('utf-8-sig', errors='ignore')
        except Exception:
            return None

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

    def _parse_plain_lrc(self, plain_text, length):
        if not plain_text:
            return None
        raw_lines = [line.strip() for line in plain_text.splitlines() if line.strip()]
        if not raw_lines:
            return None
        total = len(raw_lines)
        lines = []
        if length and length > 0:
            intro_us = int(length * 0.05)  # 5% intro offset to account for instrumental intro
            vocal_duration_us = int(length * 0.88)  # 88% vocal window
            step_us = vocal_duration_us // max(1, total - 1)
            for i, line in enumerate(raw_lines):
                time_ms = intro_us + (i * step_us)
                lines.append({"time_ms": time_ms, "lyric": line, "is_estimated": True})
        else:
            step_us = 4000000
            for i, line in enumerate(raw_lines):
                lines.append({"time_ms": i * step_us, "lyric": line, "is_estimated": True})
        return lines

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


    def _is_credit_line(self, text):
        if not text:
            return False
        credit_keywords = [
            '作词', '作曲', '编曲', '制作人', '制作', '监制', '混音', '混音师', '混音工程',
            '录音', '录音师', '录音助理', '录音工程', '母带', '母带后期',
            '吉他', '贝斯', '鼓', '弦乐', '键盘', '和声', '合声', '合声编写',
            '企划', '统筹', '出品人', '出品', '发行', '发行人', '翻译',
            '歌词制作', '动态歌词', 'LRC制作', '词', '曲', 'OP', 'SP', 'by:'
        ]
        for kw in credit_keywords:
            if re.match(rf'^\s*{kw}\s*[:：]', text, flags=re.IGNORECASE):
                return True
        return False

    def _parse_lrc(self, lrc_text):
        lines = []
        leading_tags = re.compile(r'^((?:\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+)(.*)$')
        for raw in lrc_text.splitlines():
            line = raw.strip()
            if not line:
                continue
            match = leading_tags.match(line)
            if not match:
                continue
            tags = LRC_TIME_RE.findall(match.group(1))
            if not tags:
                continue
            body = match.group(2)
            tag_times = [self._time_to_us(tag[0], tag[1], tag[2]) for tag in tags]
            has_word_tags = bool(LRC_WORD_RE.search(body))
            words = self._parse_word_body(body, tag_times[0])
            lyric = ''.join(word['text'] for word in words).strip()
            if self._is_credit_line(lyric):
                continue
            for tag_time in tag_times:
                entry = {"time_ms": tag_time, "lyric": lyric}
                if has_word_tags and words:
                    entry["words"] = words
                lines.append(entry)
        lines.sort(key=lambda x: x['time_ms'])
        return lines


    def _get_current_lyric(self):
        if not self.lyrics:
            return None
        lyrics_line_num = len(self.lyrics)
        start = 0
        end = lyrics_line_num - 1
        while start <= end:
            mid = (start + end) >> 1
            if self.position_ms == self.lyrics[mid]['time_ms']:
                end = mid
                break
            if self.position_ms > self.lyrics[mid]['time_ms']:
                start = mid + 1
            else:
                end = mid - 1
        if end < 0:
            return None
        # If current lyric is empty, find the previous non-empty one
        while end >= 0 and not self.lyrics[end]['lyric']:
            end -= 1
        if end < 0:
            return None
        return self.lyrics[end]['lyric']       
        
        
    def _has_synced_lyrics(self):
        """True when the current lyrics have real timestamps (not estimated)."""
        if not self.lyrics or len(self.lyrics) < 2:
            return False
        return not any(line.get('is_estimated', False) for line in self.lyrics)

    def get_state(self):
        if not self.playerobj:
            return self._get_empty_state()
        lyrics_state = {
            'current_lyric': self.current_lyric,
            'next_lyric': getattr(self, 'next_lyric', '') or '',
            'current_lyric_duration_ms': getattr(self, 'current_lyric_duration_ms', 0) or 0,
            'time_remaining_ms': getattr(self, 'time_remaining_ms', 0) or 0,
            'has_synced_lyrics': self._has_synced_lyrics(),
            'has_word_lyrics': getattr(self, 'has_word_lyrics', False),
            'current_words': getattr(self, 'current_words', []) or [],
            'current_line_start_ms': getattr(self, 'current_line_start_ms', 0) or 0,
            'current_line_end_ms': getattr(self, 'current_line_end_ms', 0) or 0,
            'position_ms': getattr(self, 'karaoke_position_ms', 0) or 0,
        }
        lyrics_state.update(getattr(self, 'extra_lyrics_info', {}) or {})
        return {
            "playback_status": self.playback_status.value.lower(),
            "player": {
                "identity": self.identity,
                "bus_name": self.playername
            },
            "track": {
                "title": self._clean_display_title(self.title),
                "artist": self._clean_display_artist(self.artist),
                "album": self.album,
                "duration": self.duration,
                "art_url": getattr(self, 'art_url', '') or ""
            },
            "position_ms": self.position_ms,
            "lyrics": lyrics_state,
            "available_players": self.available_players
        }


    def _get_empty_state(self):
        return {
            "playback_status": PlaybackStatus.STOPPED.value.lower(),
            "player": None,
            "track": None,
            "position_ms": 0,
            "lyrics": None,
            "available_players": None
        }

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

    def _get_lyrics_info(self, convert_to_simplified=False):
        def convert(text):
            return to_simplified(text) if convert_to_simplified and text else text

        def build_line(idx, following_idx=None):
            line = self.lyrics[idx]
            start_us = line['time_ms']
            words = []
            for word in line.get('words', []):
                converted_word = convert(word.get('text', ''))
                if converted_word:
                    words.append({
                        "time_ms": word['time_ms'] // 1000,
                        "text": converted_word,
                    })
            if words:
                text = ''.join(word['text'] for word in words)
            else:
                text = convert(line['lyric']) or ""
            if line.get('duration_ms'):
                end_us = start_us + int(line['duration_ms']) * 1000
            elif following_idx is not None:
                end_us = self.lyrics[following_idx]['time_ms']
            elif self.duration > start_us:
                end_us = self.duration
            else:
                end_us = start_us + 10000000
            return {
                "lyric": text,
                "words": words,
                "has_word_lyrics": bool(words),
                "start_ms": start_us // 1000,
                "end_ms": end_us // 1000,
            }

        def next_indices(after_idx, count=2):
            found = []
            idx = after_idx
            while idx < len(self.lyrics) and len(found) < count:
                if self.lyrics[idx]['lyric']:
                    found.append(idx)
                idx += 1
            return found

        empty_lyrics = {
            "current_lyric": "",
            "next_lyric": "",
            "current_lyric_duration_ms": 0,
            "time_remaining_ms": 0,
            "has_word_lyrics": False,
            "current_words": [],
            "current_line_start_ms": 0,
            "current_line_end_ms": 0,
            "position_ms": self.position_ms // 1000,
            "next_words": [],
            "next_has_word_lyrics": False,
            "next_line_start_ms": 0,
            "next_line_end_ms": 0,
            "after_next_lyric": "",
            "after_next_words": [],
            "after_next_has_word_lyrics": False,
            "after_next_line_start_ms": 0,
            "after_next_line_end_ms": 0,
        }
        if not self.lyrics:
            return empty_lyrics

        lyrics_line_num = len(self.lyrics)
        start = 0
        end = lyrics_line_num - 1
        while start <= end:
            mid = (start + end) >> 1
            if self.position_ms == self.lyrics[mid]['time_ms']:
                end = mid
                break
            if self.position_ms > self.lyrics[mid]['time_ms']:
                start = mid + 1
            else:
                end = mid - 1

        if end < 0:
            upcoming = next_indices(0, 2)
            first_line = build_line(upcoming[0], upcoming[1] if len(upcoming) > 1 else None) if upcoming else None
            second_line = build_line(upcoming[1]) if len(upcoming) > 1 else None
            next_time = first_line['start_ms'] * 1000 if first_line else 0
            remaining_us = max(0, next_time - self.position_ms)
            result = dict(empty_lyrics)
            result.update({
                "next_lyric": first_line['lyric'] if first_line else "",
                "next_words": first_line['words'] if first_line else [],
                "next_has_word_lyrics": first_line['has_word_lyrics'] if first_line else False,
                "next_line_start_ms": first_line['start_ms'] if first_line else 0,
                "next_line_end_ms": first_line['end_ms'] if first_line else 0,
                "after_next_lyric": second_line['lyric'] if second_line else "",
                "after_next_words": second_line['words'] if second_line else [],
                "after_next_has_word_lyrics": second_line['has_word_lyrics'] if second_line else False,
                "after_next_line_start_ms": second_line['start_ms'] if second_line else 0,
                "after_next_line_end_ms": second_line['end_ms'] if second_line else 0,
                "current_lyric_duration_ms": remaining_us // 1000,
                "time_remaining_ms": remaining_us // 1000,
            })
            return result

        curr_idx = end
        while curr_idx >= 0 and not self.lyrics[curr_idx]['lyric']:
            curr_idx -= 1
        upcoming = next_indices(end + 1, 2)
        next_idx = upcoming[0] if upcoming else None
        after_idx = upcoming[1] if len(upcoming) > 1 else None

        current_line = build_line(curr_idx, next_idx) if curr_idx >= 0 else None
        next_line = build_line(next_idx, after_idx) if next_idx is not None else None
        after_line = build_line(after_idx) if after_idx is not None else None

        lyric_time = self.lyrics[curr_idx]['time_ms'] if curr_idx >= 0 else self.lyrics[end]['time_ms']
        next_time = next_line['start_ms'] * 1000 if next_line else 0
        if not next_line:
            if self.duration > 0 and self.duration > lyric_time:
                duration_us = self.duration - lyric_time
                remaining_us = max(0, self.duration - self.position_ms)
            else:
                duration_us = 10000000
                remaining_us = max(0, duration_us - (self.position_ms - lyric_time))
        else:
            duration_us = next_time - lyric_time
            remaining_us = max(0, next_time - self.position_ms)

        result = dict(empty_lyrics)
        if current_line:
            result.update({
                "current_lyric": current_line['lyric'],
                "has_word_lyrics": current_line['has_word_lyrics'],
                "current_words": current_line['words'],
                "current_line_start_ms": current_line['start_ms'],
                "current_line_end_ms": current_line['end_ms'],
            })
        if next_line:
            result.update({
                "next_lyric": next_line['lyric'],
                "next_words": next_line['words'],
                "next_has_word_lyrics": next_line['has_word_lyrics'],
                "next_line_start_ms": next_line['start_ms'],
                "next_line_end_ms": next_line['end_ms'],
            })
        if after_line:
            result.update({
                "after_next_lyric": after_line['lyric'],
                "after_next_words": after_line['words'],
                "after_next_has_word_lyrics": after_line['has_word_lyrics'],
                "after_next_line_start_ms": after_line['start_ms'],
                "after_next_line_end_ms": after_line['end_ms'],
            })
        result.update({
            "current_lyric_duration_ms": duration_us // 1000,
            "time_remaining_ms": remaining_us // 1000,
        })
        return result

    _spotify_token = None
    _spotify_token_expires_at = 0

    def _get_spotify_token(self):
        """Retrieves an anonymous access token from Spotify embed page."""
        now = time.time()
        if self._spotify_token and now < self._spotify_token_expires_at:
            return self._spotify_token
        
        try:
            url = 'https://open.spotify.com/embed/track/4cOdK2wGLETKBW3PvgPWqT'
            status, html = self._http_get(url, timeout=5)
            if status == 200 and html:
                m = re.search(r'\"accessToken\":\"([^\"]+)\"', html)
                if m:
                    self._spotify_token = m.group(1)
                    self._spotify_token_expires_at = now + 2700
                    return self._spotify_token
        except Exception as e:
            print(f"[DEBUG] Error fetching Spotify token: {e}")
        return None

    _app_tokens = {}
    _auth_file_path = Path.home() / '.config' / 'lyrics-on-panel' / 'spotify_user_auth.json'
    _auth_server = None

    def get_spotify_auth_status(self, client_id=None):
        """Returns the current Spotify user authorization status, verifying client_id match if provided."""
        try:
            if not client_id or not client_id.strip():
                return {"connected": False, "user_name": "", "user_id": ""}

            if self._auth_file_path.exists():
                with open(self._auth_file_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    saved_cid = data.get('client_id', '').strip()
                    if saved_cid and saved_cid != client_id.strip():
                        return {"connected": False, "user_name": "", "user_id": ""}

                    if data.get('refresh_token') or data.get('access_token'):
                        return {
                            "connected": True,
                            "user_name": data.get("user_name", "Usuario"),
                            "user_id": data.get("user_id", "")
                        }
        except Exception as e:
            print(f"[DEBUG] Error reading Spotify auth file: {e}")
        return {"connected": False, "user_name": "", "user_id": ""}

    def spotify_logout(self):
        """Logs out and deletes the stored Spotify user credentials."""
        try:
            if self._auth_file_path.exists():
                self._auth_file_path.unlink(missing_ok=True)
            return {"connected": False, "success": True}
        except Exception as e:
            print(f"[DEBUG] Error logging out of Spotify: {e}")
            return {"connected": False, "success": False}

    def start_spotify_user_login(self, client_id, client_secret):
        """Starts a temporary local server on port 8888 and opens the Spotify OAuth authorization URL in the browser."""
        if not client_id or not client_secret:
            return {"success": False, "error": "Missing client credentials"}

        # Stop any existing auth server
        if self._auth_server:
            try:
                self._auth_server.shutdown()
                self._auth_server.server_close()
            except Exception:
                pass
            self._auth_server = None

        manager_ref = self

        class OAuthCallbackHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def do_GET(self):
                parsed = urlparse(self.path)
                if parsed.path == '/callback':
                    params = urllib.parse.parse_qs(parsed.query)
                    code = params.get('code', [None])[0]
                    if code:
                        try:
                            auth_str = f"{client_id.strip()}:{client_secret.strip()}"
                            b64_auth = base64.b64encode(auth_str.encode('utf-8')).decode('utf-8')
                            token_data = urlencode({
                                'grant_type': 'authorization_code',
                                'code': code,
                                'redirect_uri': 'http://127.0.0.1:8888/callback'
                            }).encode('utf-8')
                            req = urllib.request.Request('https://accounts.spotify.com/api/token', data=token_data, headers={
                                'Authorization': f'Basic {b64_auth}',
                                'Content-Type': 'application/x-www-form-urlencoded'
                            })
                            with urllib.request.urlopen(req, timeout=8) as r:
                                token_resp = json.loads(r.read().decode('utf-8'))
                            
                            access_token = token_resp.get('access_token')
                            refresh_token = token_resp.get('refresh_token')
                            expires_in = token_resp.get('expires_in', 3600)
                            
                            user_name = "Usuario"
                            user_id = ""
                            try:
                                u_req = urllib.request.Request('https://api.spotify.com/v1/me', headers={
                                    'Authorization': f'Bearer {access_token}'
                                })
                                with urllib.request.urlopen(u_req, timeout=5) as u_r:
                                    u_data = json.loads(u_r.read().decode('utf-8'))
                                    user_name = u_data.get('display_name') or u_data.get('id') or "Usuario"
                                    user_id = u_data.get('id', '')
                            except Exception:
                                pass

                            manager_ref._auth_file_path.parent.mkdir(parents=True, exist_ok=True)
                            with open(manager_ref._auth_file_path, 'w', encoding='utf-8') as f:
                                json.dump({
                                    "access_token": access_token,
                                    "refresh_token": refresh_token,
                                    "expires_at": time.time() + expires_in - 60,
                                    "user_name": user_name,
                                    "user_id": user_id,
                                    "client_id": client_id.strip(),
                                    "client_secret": client_secret.strip()
                                }, f, indent=2)
                            
                            self.send_response(200)
                            self.send_header('Content-type', 'text/html; charset=utf-8')
                            self.end_headers()
                            html = f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Spotify Conectado</title></head>
<body style="background:#121212;color:#fff;font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
  <div style="text-align:center;background:#181818;padding:40px;border-radius:16px;box-shadow:0 8px 30px rgba(0,0,0,0.5);border:1px solid #282828;max-width:420px;">
    <div style="font-size:48px;margin-bottom:16px;">✅</div>
    <h2 style="color:#1db954;margin:0 0 10px 0;">¡Spotify Conectado!</h2>
    <p style="color:#e4e4e7;font-size:15px;margin:0 0 8px 0;">Bienvenido, <b>{user_name}</b>.</p>
    <p style="color:#71717a;font-size:13px;margin:0;">Tu biblioteca de playlists ya está sincronizada con Lyrics-on-Panel. Puedes cerrar esta pestaña.</p>
  </div>
</body>
</html>"""
                            self.wfile.write(html.encode('utf-8'))
                        except Exception as e:
                            print(f"[DEBUG] Error exchanging Spotify OAuth token: {e}")
                            self.send_response(500)
                            self.end_headers()
                            self.wfile.write(b"Error connecting to Spotify")
                    else:
                        self.send_response(400)
                        self.end_headers()
                        self.wfile.write(b"Missing code parameter")
                    
                    threading.Thread(target=manager_ref._stop_auth_server, daemon=True).start()
                else:
                    self.send_response(404)
                    self.end_headers()

        class ReusableServer(socketserver.TCPServer):
            allow_reuse_address = True

        try:
            self._auth_server = ReusableServer(('127.0.0.1', 8888), OAuthCallbackHandler)
            threading.Thread(target=self._auth_server.serve_forever, daemon=True).start()
        except Exception as e:
            print(f"[DEBUG] Error starting local OAuth server: {e}")
            return {"success": False, "error": str(e)}

        auth_url = 'https://accounts.spotify.com/authorize?' + urlencode({
            'client_id': client_id.strip(),
            'response_type': 'code',
            'redirect_uri': 'http://127.0.0.1:8888/callback',
            'scope': 'playlist-read-private playlist-read-collaborative user-library-read'
        })

        try:
            subprocess.Popen(['xdg-open', auth_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

        return {"success": True, "auth_url": auth_url}

    def _stop_auth_server(self):
        time.sleep(1)
        if self._auth_server:
            try:
                self._auth_server.shutdown()
                self._auth_server.server_close()
            except Exception:
                pass
            self._auth_server = None

    def _get_spotify_user_token(self, client_id=None, client_secret=None):
        """Returns a valid user access token, automatically refreshing it if expired."""
        if not self._auth_file_path.exists():
            return None
        
        if not client_id or not client_id.strip():
            return None

        try:
            with open(self._auth_file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            saved_cid = data.get('client_id', '').strip()
            if saved_cid and saved_cid != client_id.strip():
                return None

            now = time.time()
            if now < data.get('expires_at', 0):
                return data.get('access_token')
            
            refresh_token = data.get('refresh_token')
            cid = client_id or data.get('client_id')
            csec = client_secret or data.get('client_secret')
            if refresh_token and cid and csec:
                auth_str = f"{cid.strip()}:{csec.strip()}"
                b64_auth = base64.b64encode(auth_str.encode('utf-8')).decode('utf-8')
                post_data = urlencode({
                    'grant_type': 'refresh_token',
                    'refresh_token': refresh_token
                }).encode('utf-8')
                req = urllib.request.Request('https://accounts.spotify.com/api/token', data=post_data, headers={
                    'Authorization': f'Basic {b64_auth}',
                    'Content-Type': 'application/x-www-form-urlencoded'
                })
                with urllib.request.urlopen(req, timeout=6) as r:
                    refreshed = json.loads(r.read().decode('utf-8'))
                    new_access = refreshed.get('access_token')
                    expires_in = refreshed.get('expires_in', 3600)
                    if new_access:
                        data['access_token'] = new_access
                        data['expires_at'] = now + expires_in - 60
                        if 'refresh_token' in refreshed:
                            data['refresh_token'] = refreshed['refresh_token']
                        with open(self._auth_file_path, 'w', encoding='utf-8') as fw:
                            json.dump(data, fw, indent=2)
                        return new_access
        except Exception as e:
            print(f"[DEBUG] Error refreshing Spotify user token: {e}")
        return None

    def get_user_playlists(self, client_id=None, client_secret=None):
        """Fetches the user's personal playlists library (including private & collaborative)."""
        token = self._get_spotify_user_token(client_id, client_secret)
        if not token:
            return []
        
        try:
            req = urllib.request.Request('https://api.spotify.com/v1/me/playlists?limit=50', headers={
                'Authorization': f'Bearer {token}',
                'Accept': 'application/json'
            })
            with urllib.request.urlopen(req, timeout=5) as r:
                data = json.loads(r.read().decode('utf-8'))
                playlists = []
                for item in data.get('items', []):
                    if not item:
                        continue
                    title = item.get('name', '')
                    owner_name = item.get('owner', {}).get('display_name', '')
                    total_tracks = item.get('tracks', {}).get('total', 0)
                    is_public = item.get('public', True)
                    
                    sub = f"Playlist • {owner_name}" if owner_name else "Playlist"
                    if total_tracks:
                        sub += f" ({total_tracks} canciones)"
                    if not is_public:
                        sub += " 🔒"
                    
                    images = item.get('images', [])
                    art_url = images[0].get('url') if images else ''
                    uri = item.get('uri', '') # spotify:playlist:ID
                    playlists.append({
                        "title": title,
                        "artist": sub,
                        "album": "",
                        "art_url": art_url,
                        "uri": uri,
                        "duration_ms": 0,
                        "item_type": "playlist",
                        "is_private": not is_public
                    })
                return playlists
        except Exception as e:
            print(f"[DEBUG] Error fetching user playlists: {e}")
            return []

    def _get_spotify_app_token(self, client_id, client_secret):
        """Generates an official Spotify OAuth2 access token using developer client credentials."""
        if not client_id or not client_secret:
            return None
        now = time.time()
        cached = self._app_tokens.get(client_id)
        if cached and now < cached[0]:
            return cached[1]
        
        try:
            auth_str = f"{client_id.strip()}:{client_secret.strip()}"
            b64_auth = base64.b64encode(auth_str.encode('utf-8')).decode('utf-8')
            data = urllib.parse.urlencode({'grant_type': 'client_credentials'}).encode('utf-8')
            req = urllib.request.Request('https://accounts.spotify.com/api/token', data=data, headers={
                'Authorization': f'Basic {b64_auth}',
                'Content-Type': 'application/x-www-form-urlencoded'
            })
            with urllib.request.urlopen(req, timeout=5) as r:
                res = json.loads(r.read().decode('utf-8'))
                token = res.get('access_token')
                expires_in = res.get('expires_in', 3600)
                if token:
                    self._app_tokens[client_id] = (now + expires_in - 60, token)
                    return token
        except Exception as e:
            print(f"[DEBUG] Error obtaining Spotify App token: {e}")
        return None

    def search_spotify(self, query, limit=10, client_id=None, client_secret=None, search_type="track"):
        """Searches for tracks or playlists and returns structured results with album art and Spotify URIs."""
        stype = search_type or "track"

        # Auto-load credentials from saved session if not provided
        if (not client_id or not client_secret) and self._auth_file_path.exists():
            try:
                with open(self._auth_file_path, 'r', encoding='utf-8') as f:
                    saved_cfg = json.load(f)
                    client_id = client_id or saved_cfg.get('client_id')
                    client_secret = client_secret or saved_cfg.get('client_secret')
            except Exception:
                pass

        # If empty query in playlist mode, load the user's personal playlists library!
        if (not query or not query.strip()) and stype == "playlist":
            return self.get_user_playlists(client_id, client_secret)

        if not query or not query.strip():
            return []
        
        stype = search_type or "track"
        cache_key = f"{stype}:{query.strip().lower()}"
        now = time.time()
        
        # Check cache
        if cache_key in self._search_cache:
            expires_at, cached_items = self._search_cache[cache_key]
            if now < expires_at:
                return cached_items
        
        results = []

        # 1. Primary: If Spotify credentials or user token available, use official Spotify Web API
        token = None
        if client_id and client_secret:
            token = self._get_spotify_app_token(client_id, client_secret) or self._get_spotify_user_token(client_id, client_secret)
        elif self._auth_file_path.exists():
            token = self._get_spotify_user_token()

        if token:
            try:
                search_url = f"https://api.spotify.com/v1/search?q={quote(query.strip())}&type={stype}&limit={limit}"
                req = urllib.request.Request(search_url, headers={'Authorization': f'Bearer {token}'})
                with urllib.request.urlopen(req, timeout=4) as resp:
                    data = json.loads(resp.read().decode('utf-8'))
                    if stype == "playlist":
                        for item in data.get('playlists', {}).get('items', []):
                            if not item:
                                continue
                            title = item.get('name', '')
                            owner_name = item.get('owner', {}).get('display_name', '')
                            total_tracks = item.get('tracks', {}).get('total', 0)
                            subtitle = f"Playlist • {owner_name}" if owner_name else "Playlist"
                            if total_tracks:
                                subtitle += f" ({total_tracks} canciones)"
                            images = item.get('images', [])
                            art_url = images[0].get('url') if images else ''
                            uri = item.get('uri', '') # spotify:playlist:ID
                            results.append({
                                "title": title,
                                "artist": subtitle,
                                "album": "",
                                "art_url": art_url,
                                "uri": uri,
                                "duration_ms": 0,
                                "item_type": "playlist"
                            })
                    else:
                        for item in data.get('tracks', {}).get('items', []):
                            if not item:
                                continue
                            title = self._clean_display_title(item.get('name', ''))
                            artists_raw = [a.get('name', '') for a in item.get('artists', [])]
                            artist = self._clean_display_artist(artists_raw)
                            album_obj = item.get('album', {})
                            album = self._clean_display_title(album_obj.get('name', ''))
                            images = album_obj.get('images', [])
                            art_url = images[0].get('url') if images else ''
                            uri = item.get('uri', '') # spotify:track:ID
                            duration_ms = item.get('duration_ms', 0)
                            results.append({
                                "title": title,
                                "artist": artist,
                                "album": album,
                                "art_url": art_url,
                                "uri": uri,
                                "duration_ms": duration_ms,
                                "item_type": "track"
                            })
                    if results:
                        self._search_cache[cache_key] = (now + 600, results)
                        return results
            except Exception as e:
                print(f"[DEBUG] Official Spotify API search error: {e}")
        
        # 2. Secondary: iTunes Search API (Tracks fallback)
        if stype == "track":
            try:
                url = f"https://itunes.apple.com/search?term={quote(query.strip())}&entity=song&limit={limit}"
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'})
                with urllib.request.urlopen(req, timeout=4) as r:
                    data = json.loads(r.read().decode('utf-8'))
                    for item in data.get('results', []):
                        title = self._clean_display_title(item.get('trackName', ''))
                        artist = self._clean_display_artist(item.get('artistName', ''))
                        album = self._clean_display_title(item.get('collectionName', ''))
                        art_url = item.get('artworkUrl100', '').replace('100x100bb', '300x300bb')
                        duration_ms = item.get('trackTimeMillis', 0)
                        uri = f"spotify:search:{quote(artist + ' ' + title)}"
                        results.append({
                            "title": title,
                            "artist": artist,
                            "album": album,
                            "art_url": art_url,
                            "uri": uri,
                            "duration_ms": duration_ms,
                            "item_type": "track"
                        })
            except Exception as e:
                print(f"[DEBUG] iTunes search fallback: {e}")
            
            # 3. Tertiary: Deezer Search API (Fallback)
            if not results:
                try:
                    url = f"https://api.deezer.com/search?q={quote(query.strip())}&limit={limit}"
                    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)'})
                    with urllib.request.urlopen(req, timeout=4) as r:
                        data = json.loads(r.read().decode('utf-8'))
                        for item in data.get('data', []):
                            title = self._clean_display_title(item.get('title', ''))
                            artist = self._clean_display_artist(item.get('artist', {}).get('name', ''))
                            album = self._clean_display_title(item.get('album', {}).get('title', ''))
                            art_url = item.get('album', {}).get('cover_medium', '')
                            duration_ms = item.get('duration', 0) * 1000
                            uri = f"spotify:search:{quote(artist + ' ' + title)}"
                            results.append({
                                "title": title,
                                "artist": artist,
                                "album": album,
                                "art_url": art_url,
                                "uri": uri,
                                "duration_ms": duration_ms,
                                "item_type": "track"
                            })
                except Exception as e:
                    print(f"[DEBUG] Deezer search fallback: {e}")
        
        # Cache results for 10 minutes (max 20 queries)
        if results:
            if len(self._search_cache) >= 20:
                self._search_cache = {k: v for k, v in self._search_cache.items() if now < v[0]}
                if len(self._search_cache) >= 20:
                    oldest_k = next(iter(self._search_cache))
                    self._search_cache.pop(oldest_k, None)
            self._search_cache[cache_key] = (now + 600, results)
        
        return results

    def play_uri(self, uri, playername=None):
        """Sends open_uri command to Spotify or specified player, launching Spotify if not active."""
        if not uri:
            return False
        
        # If generic search URI, resolve it to exact track ID if a Spotify token is available
        if uri.startswith("spotify:search:"):
            term = unquote(uri[len("spotify:search:"):])
            token = None
            if self._auth_file_path.exists():
                token = self._get_spotify_user_token()
            if not token and self._app_tokens:
                for cid, (exp, tok) in self._app_tokens.items():
                    if time.time() < exp:
                        token = tok
                        break
            if token:
                try:
                    s_url = f"https://api.spotify.com/v1/search?q={quote(term)}&type=track&limit=1"
                    s_req = urllib.request.Request(s_url, headers={'Authorization': f'Bearer {token}'})
                    with urllib.request.urlopen(s_req, timeout=3) as s_resp:
                        s_data = json.loads(s_resp.read().decode('utf-8'))
                        items = s_data.get('tracks', {}).get('items', [])
                        if items and items[0].get('uri'):
                            uri = items[0]['uri']
                except Exception as e:
                    print(f"[DEBUG] Error resolving search URI to exact track ID: {e}")

        target_playername = playername or 'org.mpris.MediaPlayer2.spotify'
        player = self.players_cache.get(target_playername)
        if not player or not player.obj:
            player = MprisPlayer(target_playername)
            self.players_cache[target_playername] = player
        
        if player and player.obj:
            try:
                success = player.open_uri(uri)
                if success:
                    return True
            except Exception:
                pass
        
        # Fallback if DBus interface is not active
        try:
            subprocess.Popen(['xdg-open', uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except Exception:
            try:
                subprocess.Popen(['spotify', '--uri=' + uri], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return True
            except Exception as e:
                print(f"[DEBUG] Error launching Spotify URI: {e}")
                return False