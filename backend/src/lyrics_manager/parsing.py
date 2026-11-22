import re
import zlib

from .constants import KRC_KEY, KRC_LINE_RE, KRC_WORD_RE, LRC_TIME_RE, LRC_WORD_RE


class LyricsParsingMixin:
    """LRC/KRC lyric parsing helpers."""

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

