class PlayerSelectionMixin:
    """Player discovery and mode-based selection helpers."""

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

