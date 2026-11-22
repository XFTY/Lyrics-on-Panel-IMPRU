import base64
import http.server
import json
import socketserver
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.parse import urlencode, urlparse

from mpris_player import MprisPlayer


class SpotifyMixin:
    """Spotify OAuth, search and URI playback."""

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
