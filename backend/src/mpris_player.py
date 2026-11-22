import dbus
from enum import Enum

DBUS_PROPERTIES_IFACE = 'org.freedesktop.DBus.Properties'
MPRIS_ROOT_IFACE = 'org.mpris.MediaPlayer2'
MPRIS_PLAYER_IFACE = 'org.mpris.MediaPlayer2.Player'
MPRIS_OBJECT_PATH = '/org/mpris/MediaPlayer2'

# Cached DBus session bus
_session_bus = None

def get_session_bus():
    """Get or create a cached DBus session bus."""
    global _session_bus
    if _session_bus is None:
        _session_bus = dbus.SessionBus()
    return _session_bus


class PlaybackStatus(Enum):
    PLAYING = "Playing"
    PAUSED = "Paused"
    STOPPED = "Stopped"


class MprisPlayer:
    """
    Wraps a single MPRIS2 media player DBus service.
    Implements org.mpris.MediaPlayer2 and org.mpris.MediaPlayer2.Player interfaces.
    """
    def __init__(self, dbus_identifier):
        self.dbus_identifier = dbus_identifier
        bus = get_session_bus()
        try:
            self.obj = bus.get_object(dbus_identifier, MPRIS_OBJECT_PATH)
            self.props_iface = dbus.Interface(self.obj, DBUS_PROPERTIES_IFACE)
            self.root_iface = dbus.Interface(self.obj, MPRIS_ROOT_IFACE)
            self.player_iface = dbus.Interface(self.obj, MPRIS_PLAYER_IFACE)
        except dbus.exceptions.DBusException:
            self.obj = None


    def _get_property(self, iface, prop_name):
        if not self.obj: return None
        try:
            return self.props_iface.Get(iface, prop_name)
        except dbus.exceptions.DBusException:
            return None


    def raise_player(self):
        """Brings the media player's user interface to the front."""
        if self.can_raise:
            try:
                self.root_iface.Raise()
            except dbus.exceptions.DBusException:
                pass


    def quit(self):
        """Causes the media player to stop running."""
        if self.can_quit:
            try:
                self.root_iface.Quit()
            except dbus.exceptions.DBusException:
                pass


    @property
    def can_quit(self):
        return bool(self._get_property(MPRIS_ROOT_IFACE, 'CanQuit'))


    @property
    def can_raise(self):
        return bool(self._get_property(MPRIS_ROOT_IFACE, 'CanRaise'))


    @property
    def identity(self):
        val = self._get_property(MPRIS_ROOT_IFACE, 'Identity')
        return str(val) if val else "Unknown"


    # ==========================================
    # org.mpris.MediaPlayer2.Player (Player Interface)
    # ==========================================

    # --- Methods ---
    def next(self):
        try: self.player_iface.Next()
        except: pass


    def previous(self):
        try: self.player_iface.Previous()
        except: pass


    def pause(self):
        try: self.player_iface.Pause()
        except: pass


    def play_pause(self):
        try: self.player_iface.PlayPause()
        except: pass


    def stop(self):
        try: self.player_iface.Stop()
        except: pass


    def play(self):
        try: self.player_iface.Play()
        except: pass


    # --- Properties ---
    @property
    def playback_status(self):
        # "Playing", "Paused", "Stopped"
        val = self._get_property(MPRIS_PLAYER_IFACE, 'PlaybackStatus')
        return PlaybackStatus(str(val)) if val else PlaybackStatus.STOPPED


    @property
    def metadata(self):
        val = self._get_property(MPRIS_PLAYER_IFACE, 'Metadata')
        return dict(val) if val else {}


    def _unwrap_str(self, val):
        return str(val) if val else ''


    def _unwrap_list(self, val):
        if not val:
            return []
        # Handle case where val is a string instead of list
        if isinstance(val, str):
            return [val]
        return [str(v) for v in val]


    @property
    def track_info(self):
        """Extract commonly used track info from metadata."""
        meta = self.metadata
        return {
            'title': self._unwrap_str(meta.get('xesam:title', '')),
            'artist': self._unwrap_list(meta.get('xesam:artist', [])),
            'album': self._unwrap_str(meta.get('xesam:album', '')),
            'art_url': self._unwrap_str(meta.get('mpris:artUrl', '')),
            'length': int(meta.get('mpris:length', 0)),
            'url': self._unwrap_str(meta.get('xesam:url', '')),
        }


    @property
    def position(self):
        # Returns position in microseconds
        val = self._get_property(MPRIS_PLAYER_IFACE, 'Position')
        return int(val) if val is not None else 0


    def open_uri(self, uri):
        """Opens a URI in the media player (e.g. spotify:track:xxx)."""
        if not self.obj:
            return False
        try:
            self.player_iface.OpenUri(uri)
            return True
        except dbus.exceptions.DBusException as e:
            print(f"[DEBUG] OpenUri error: {e}")
            return False
