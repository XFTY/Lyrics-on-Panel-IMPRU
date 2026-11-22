import asyncio
import json
from lyrics_manager import LyricsManager
from mpris_player import MprisPlayer
import websockets


def route(*paths):
    """Decorator to mark a method as a WebSocket route handler."""
    def decorator(func):
        func._ws_routes = [p.lstrip("/") for p in paths]
        return func
    return decorator


class LyricsServer:
    """
    WebSocket server for lyrics display clients.

    Endpoints:
        ws://host:port/healthcheck  -> {"status": "ok"}
        ws://host:port/poll         -> {...player state...}
        ws://host:port/control      <- {"action": "play|pause|...", "player": "..."}
    """
    def __init__(self, host="127.0.0.1", port=23560):
        self.host = host
        self.port = port
        self.manager = LyricsManager()
        self._routes = self._collect_routes()
        self._connection_paths = {}


    def _collect_routes(self):
        """Collect all methods decorated with @route."""
        routes = {}
        for name in dir(self):
            method = getattr(self, name)
            if callable(method) and hasattr(method, "_ws_routes"):
                for path in method._ws_routes:
                    routes[path] = method
        return routes


    def process_request(self, connection, request):
        """Store the request path for later use in handler."""
        self._connection_paths[id(connection)] = request.path.strip("/")
        print(f"[DEBUG] process_request: path={request.path}")
        if "connection" in request.headers:
            conn = request.headers["connection"]
            if "upgrade" not in conn.lower():
                del request.headers["connection"]
                request.headers["connection"] = "Upgrade"


    async def handler(self, websocket):
        path = self._connection_paths.pop(id(websocket), "")
        handler = self._routes.get(path)
        if handler:
            await handler(websocket)
        else:
            await websocket.close(1008, f"Unknown endpoint: /{path}")


    @route("/healthcheck")
    async def healthcheck(self, websocket):
        await websocket.send(json.dumps({"status": "ok"}))


    @route("/poll")
    async def poll(self, websocket):
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    requested_player = data.get("player")
                    mode = data.get("mode", "global")
                    convert_to_simplified = bool(data.get("convert_to_simplified", False))
                    loop = asyncio.get_running_loop()
                    state = await loop.run_in_executor(None, self.manager.poll_status, requested_player, mode, convert_to_simplified)
                    await websocket.send(json.dumps(state))
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({"error": "Invalid JSON"}))
        except websockets.ConnectionClosed:
            pass


    @route("/control")
    async def control(self, websocket):
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    action = data.get("action")
                    loop = asyncio.get_running_loop()
                    
                    if action == "search_spotify":
                        query = data.get("query", "")
                        limit = data.get("limit", 10)
                        client_id = data.get("client_id")
                        client_secret = data.get("client_secret")
                        search_type = data.get("search_type", "track")
                        results = await loop.run_in_executor(None, self.manager.search_spotify, query, limit, client_id, client_secret, search_type)
                        await websocket.send(json.dumps({
                            "type": "search_results",
                            "query": query,
                            "search_type": search_type,
                            "results": results
                        }))
                    elif action == "play_uri":
                        uri = data.get("uri")
                        player_name = data.get("player")
                        success = await loop.run_in_executor(None, self.manager.play_uri, uri, player_name)
                        await websocket.send(json.dumps({"success": success, "action": "play_uri", "uri": uri}))
                    elif action == "spotify_login":
                        client_id = data.get("client_id")
                        client_secret = data.get("client_secret")
                        res = await loop.run_in_executor(None, self.manager.start_spotify_user_login, client_id, client_secret)
                        await websocket.send(json.dumps({"type": "spotify_login_response", "res": res}))
                    elif action == "get_spotify_auth_status":
                        client_id = data.get("client_id")
                        status = await loop.run_in_executor(None, self.manager.get_spotify_auth_status, client_id)
                        await websocket.send(json.dumps({"type": "spotify_auth_status", "status": status}))
                    elif action == "spotify_logout":
                        status = await loop.run_in_executor(None, self.manager.spotify_logout)
                        await websocket.send(json.dumps({"type": "spotify_auth_status", "status": status}))
                    else:
                        player_name = data.get("player")
                        success = await loop.run_in_executor(None, self._execute_control, action, player_name)
                        await websocket.send(json.dumps({"success": success}))
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({"error": "Invalid JSON"}))
        except websockets.ConnectionClosed:
            pass


    def _execute_control(self, action, player_name):
        """Execute playback control. Returns True on success, False on failure."""
        name = player_name or self.manager.playername
        if not name:
            return False
        player = MprisPlayer(name)
        if not player or not player.obj:
            return False
        actions = {
            "play": player.play,
            "pause": player.pause,
            "play_pause": player.play_pause,
            "stop": player.stop,
            "next": player.next,
            "previous": player.previous,
            "raise": player.raise_player,
            "quit": player.quit,
        }
        if action not in actions:
            return False
        try:
            actions[action]()
            return True
        except Exception:
            return False


    async def run(self):
        async with websockets.serve(
            self.handler,
            self.host,
            self.port,
            process_request=self.process_request
        ):
            await asyncio.Future()

if __name__ == "__main__":
    server = LyricsServer()
    try:
        asyncio.run(server.run())
    except KeyboardInterrupt:
        pass