from zh_convert import to_simplified


class LyricsInfoMixin:
    """Current/next/after-next lyric computation."""

    def _has_synced_lyrics(self):
        """True when the current lyrics have real timestamps (not estimated)."""
        if not self.lyrics or len(self.lyrics) < 2:
            return False
        return not any(line.get('is_estimated', False) for line in self.lyrics)

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

