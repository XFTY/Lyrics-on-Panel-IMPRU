import re


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

