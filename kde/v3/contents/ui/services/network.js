function sendPollRequest() {
    if (pollSocket.status === WebSocket.Open) {
        var modeNames = ["global", "browser", "streaming", "pure"]
        var request = {
            "player": requestedPlayer || null,
            "mode": modeNames[config_playerMode] || "global",
            "convert_to_simplified": config_convertToSimplified
        }
        pollSocket.sendTextMessage(JSON.stringify(request))
    }
}

function sendControl(action) {
    if (controlSocket.status !== WebSocket.Open) {
        console.log("Control socket not connected")
        return
    }
    if (action === "play_pause") {
        playbackStatus = (playbackStatus === "playing") ? "paused" : "playing"
    }
    var request = {
        "action": action,
        "player": requestedPlayer || currentPlayerBusName || null
    }
    controlSocket.sendTextMessage(JSON.stringify(request))
    sendPollRequest()
    quickPollTimer.restart()
}

function searchSpotify(query, type) {
    if (controlSocket.status === WebSocket.Open) {
        var req = {
            "action": "search_spotify",
            "query": query,
            "limit": 20,
            "client_id": config_spotifyClientId,
            "client_secret": config_spotifyClientSecret,
            "search_type": type
        }
        controlSocket.sendTextMessage(JSON.stringify(req))
    }
}

function playSpotifyTrack(uri) {
    if (controlSocket.status === WebSocket.Open) {
        var req = {
            "action": "play_uri",
            "uri": uri,
            "player": "org.mpris.MediaPlayer2.spotify"
        }
        controlSocket.sendTextMessage(JSON.stringify(req))
        sendPollRequest()
        quickPollTimer.restart()
        spotifySearchPopup.visible = false
    }
}
