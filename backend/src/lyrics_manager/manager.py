import re
import threading

from mpris_player import MprisPlayer, PlaybackStatus
from mpris_prober import find_players, find_playing_players

from .cache import CacheMixin
from .fetching import LyricsFetchingMixin
from .info import LyricsInfoMixin
from .parsing import LyricsParsingMixin
from .selection import PlayerSelectionMixin
from .spotify import SpotifyMixin


class LyricsManager(
    PlayerSelectionMixin,
    LyricsParsingMixin,
    LyricsFetchingMixin,
    CacheMixin,
    LyricsInfoMixin,
    SpotifyMixin,
):
    """Core controller: player selection, tracking and lyrics fetching."""

    def __init__(self):
        self.lyrics_cache = {}
        self.players_cache = {}
        self._search_cache = {}
        self._fetch_id = 0
        self._lyrics_skip_id = None
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

    def setup(self, playername=None, playerobj=None, title=None, artist=None, album=None,
              duration=0, identity=None, lyrics=None, current_lyric=None,
              playback_status=PlaybackStatus.STOPPED, position_ms=0, available_players=None,
              next_lyric=None, current_lyric_duration_ms=0, time_remaining_ms=0, art_url="",
              has_word_lyrics=False, current_words=None, current_line_start_ms=0,
              current_line_end_ms=0, karaoke_position_ms=0, extra_lyrics_info=None,
              pure_music=False):
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
        self.pure_music = pure_music

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
             == "pure"      => follow the active player without matching lyrics; only the
                               current track title is exposed to the client

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
            pure_mode = mode == "pure"
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
                fetch_id = self._fetch_id
                # Check if this track has cached lyrics
                cache_key = self._make_cache_key(track_info['artist'], track_info['title'])
                cached_lyrics = self._get_cached_lyrics(cache_key)
                if cached_lyrics:
                    self.lyrics = cached_lyrics
                    self._lyrics_skip_id = None
                elif pure_mode:
                    # Pure music mode does not fetch or match lyrics.
                    self.lyrics = None
                    self._lyrics_skip_id = fetch_id
                else:
                    self.lyrics = None
                    self._lyrics_skip_id = None
                    threading.Thread(target=self._fetch_lyrics, args=(current_playername, track_info, fetch_id), daemon=True).start()
            elif (not pure_mode and self.lyrics is None
                    and self._lyrics_skip_id == self._fetch_id):
                # The current track was first seen in pure music mode. Fetch its
                # lyrics now that another mode needs them.
                self._lyrics_skip_id = None
                cache_key = self._make_cache_key(track_info['artist'], track_info['title'])
                cached_lyrics = self._get_cached_lyrics(cache_key)
                if cached_lyrics:
                    self.lyrics = cached_lyrics
                else:
                    fetch_id = self._fetch_id
                    threading.Thread(target=self._fetch_lyrics, args=(current_playername, track_info, fetch_id), daemon=True).start()
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
                extra_lyrics_info=lyrics_info,
                pure_music=pure_mode
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

    def _clean_display_title(self, title):
        if not title:
            return ""
        cleaned = re.sub(r'[\(（][\u4e00-\u9fff\s·/、]+[\)）]', '', title)
        cleaned = re.sub(r'\s+', ' ', cleaned).strip()
        return cleaned if cleaned else title

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

    def get_state(self):
        if not self.playerobj:
            return self._get_empty_state()
        lyrics_state = None
        if not getattr(self, 'pure_music', False):
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

