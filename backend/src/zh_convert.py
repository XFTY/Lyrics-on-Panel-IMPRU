import ctypes
import ctypes.util
import threading

_lock = threading.Lock()
_lib = None
_handle = None
_load_failed = False
_cache = {}


def _load():
    global _lib, _handle, _load_failed
    if _handle or _load_failed:
        return _handle
    try:
        libname = ctypes.util.find_library("opencc")
        if not libname:
            raise OSError("libopencc not found")
        lib = ctypes.CDLL(libname)
        lib.opencc_open.argtypes = [ctypes.c_char_p]
        lib.opencc_open.restype = ctypes.c_void_p
        lib.opencc_convert_utf8.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
        lib.opencc_convert_utf8.restype = ctypes.c_void_p
        lib.opencc_convert_utf8_free.argtypes = [ctypes.c_void_p]
        lib.opencc_convert_utf8_free.restype = None
        lib.opencc_close.argtypes = [ctypes.c_void_p]
        lib.opencc_close.restype = ctypes.c_int
        handle = lib.opencc_open(b"tw2sp")
        if not handle:
            raise OSError("failed to open OpenCC config tw2sp")
        _lib = lib
        _handle = handle
    except Exception as e:
        _load_failed = True
        print(f"[DEBUG] OpenCC unavailable, traditional->simplified conversion disabled: {e}")
    return _handle


def to_simplified(text):
    if not text:
        return text
    with _lock:
        cached = _cache.get(text)
        if cached is not None:
            return cached
        handle = _load()
        if not handle:
            return text
        data = text.encode("utf-8")
        ptr = _lib.opencc_convert_utf8(handle, data, len(data))
        if not ptr:
            return text
        try:
            result = ctypes.string_at(ptr).decode("utf-8", errors="replace")
        finally:
            _lib.opencc_convert_utf8_free(ptr)
        if len(_cache) > 1000:
            _cache.clear()
        _cache[text] = result
        return result
